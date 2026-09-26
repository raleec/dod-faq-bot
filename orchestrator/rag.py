"""RAG pipeline mirroring cachebot/deploy/rag-query.ps1."""
from __future__ import annotations

import hashlib
import logging
import os
import re
import time
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

import aiohttp
from azure.identity.aio import DefaultAzureCredential

log = logging.getLogger("orchestrator.rag")

# ---- Config (env) ----
AOAI_ENDPOINT   = os.environ["AOAI_ENDPOINT"].rstrip("/")
EMBED_DEPLOY    = os.environ.get("EMBED_DEPLOY", "text-embedding-3-large")
CHAT_DEPLOY     = os.environ.get("CHAT_DEPLOY",  "gpt-4o")
SEARCH_ENDPOINT = os.environ["SEARCH_ENDPOINT"].rstrip("/")
INDEX_NAME      = os.environ.get("INDEX_NAME",   "cachebot-index")
CACHE_INDEX     = os.environ.get("CACHE_INDEX",  "cachebot-cache")
API_VERSION     = os.environ.get("AOAI_API_VERSION",   "2024-08-01-preview")
SEARCH_API_VER  = os.environ.get("SEARCH_API_VERSION", "2024-07-01")

# Cache tuning
CACHE_TTL_HOURS = int(os.environ.get("CACHE_TTL_HOURS", "336"))  # 14 days
L2_THRESHOLD    = float(os.environ.get("L2_THRESHOLD", "0.85"))
PROMPT_VERSION  = os.environ.get("PROMPT_VERSION", "v1")
# Max number of L1 hash aliases per canonical cache entry. Once reached, older
# aliases are FIFO-evicted; the canonical entry (with its answer + embedding)
# is never removed by this cap.
MAX_L1_ALIASES  = int(os.environ.get("MAX_L1_ALIASES", "32"))
TOP_K           = int(os.environ.get("TOP_K", "3"))

# Optional Search admin key fallback (when MI RBAC on Search is not yet propagated)
SEARCH_KEY      = os.environ.get("SEARCH_KEY", "").strip() or None


SYSTEM_PROMPT = (
    "You are a federal / Azure Government FAQ assistant. Answer ONLY from the CONTEXT below. "
    "Cite each factual sentence with the bracketed source number, e.g. [1]. "
    "If the context does not contain the answer, say so and suggest escalating to a human FAQ owner. "
    "Keep answers under 150 words."
)


# ---- Credential (module-level, reused) ----
_cred: DefaultAzureCredential | None = None


def _get_cred() -> DefaultAzureCredential:
    global _cred
    if _cred is None:
        _cred = DefaultAzureCredential()
    return _cred


async def _token(scope: str) -> str:
    tok = await _get_cred().get_token(scope)
    return tok.token


def _normalize(q: str) -> str:
    q = q.lower()
    q = re.sub(r"\s+", " ", q).strip()
    q = re.sub(r"[^\w\s]", "", q, flags=re.UNICODE)
    return q


def _hash(q: str) -> str:
    return hashlib.sha256(_normalize(q).encode("utf-8")).hexdigest()


def _model_ver() -> str:
    return f"{CHAT_DEPLOY}+{EMBED_DEPLOY}"


@dataclass
class RagResult:
    answer: str
    citations: list[str]
    retrieved_chunk_ids: list[str]
    cache_layer: str  # 'L1' | 'L2' | 'miss' | 'skip'
    prompt_tokens: int = 0
    completion_tokens: int = 0
    duration_ms: int = 0
    cache_id_hit: str | None = None
    l2_cosine: float | None = None


async def _aoai_headers() -> dict[str, str]:
    tok = await _token("https://cognitiveservices.azure.com/.default")
    return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


async def _search_headers() -> dict[str, str]:
    if SEARCH_KEY:
        return {"api-key": SEARCH_KEY, "Content-Type": "application/json"}
    tok = await _token("https://search.azure.com/.default")
    return {"Authorization": f"Bearer {tok}", "Content-Type": "application/json"}


async def _embed(session: aiohttp.ClientSession, text: str) -> list[float]:
    h = await _aoai_headers()
    url = f"{AOAI_ENDPOINT}/openai/deployments/{EMBED_DEPLOY}/embeddings?api-version={API_VERSION}"
    async with session.post(url, headers=h, json={"input": text}) as r:
        r.raise_for_status()
        body = await r.json()
        return body["data"][0]["embedding"]


async def _try_l1(session: aiohttp.ClientSession, q_hash: str) -> dict[str, Any] | None:
    now = datetime.now(timezone.utc).isoformat()
    # cacheKeyHash is Collection(Edm.String) — filter with any(h: h eq '<sha>')
    # so both the original writer's hash and any promoted L2-alias hashes hit.
    flt = (
        f"cacheKeyHash/any(h: h eq '{q_hash}') and expiresAt gt {now} "
        f"and promptVersion eq '{PROMPT_VERSION}' and modelVersion eq '{_model_ver()}'"
    )
    body = {"filter": flt, "top": 1,
            "select": "id,question,answer,citations,cacheKeyHash,createdAt,hitCount"}
    h = await _search_headers()
    url = f"{SEARCH_ENDPOINT}/indexes/{CACHE_INDEX}/docs/search?api-version={SEARCH_API_VER}"
    async with session.post(url, headers=h, json=body) as r:
        r.raise_for_status()
        j = await r.json()
        return j["value"][0] if j["value"] else None


async def _try_l2(session: aiohttp.ClientSession, vec: list[float]) -> tuple[dict[str, Any] | None, float | None]:
    now = datetime.now(timezone.utc).isoformat()
    flt = (
        f"expiresAt gt {now} "
        f"and promptVersion eq '{PROMPT_VERSION}' and modelVersion eq '{_model_ver()}'"
    )
    body = {
        "vectorQueries": [{"kind": "vector", "vector": vec,
                           "fields": "questionEmbedding", "k": 1}],
        "top": 1, "filter": flt,
        "select": "id,question,answer,citations,cacheKeyHash,createdAt,hitCount",
    }
    h = await _search_headers()
    url = f"{SEARCH_ENDPOINT}/indexes/{CACHE_INDEX}/docs/search?api-version={SEARCH_API_VER}"
    async with session.post(url, headers=h, json=body) as r:
        r.raise_for_status()
        j = await r.json()
    if not j["value"]:
        return None, None
    hit = j["value"][0]
    score = hit.get("@search.score", 0)
    # Azure AI Search cosine: score = 1 / (2 - cosine)  =>  cosine = 2 - 1/score
    cosine = 2.0 - (1.0 / score) if score > 0 else 0.0
    return (hit, cosine) if cosine >= L2_THRESHOLD else (None, cosine)


async def _write_cache(session: aiohttp.ClientSession, question: str, q_hash: str,
                       vec: list[float], answer: str, citations: list[str],
                       chunk_ids: list[str]) -> None:
    now = datetime.now(timezone.utc)
    exp = now + timedelta(hours=CACHE_TTL_HOURS)
    doc = {
        "@search.action": "mergeOrUpload",
        "id": uuid.uuid4().hex,
        "cacheKeyHash": [q_hash],
        "question": question,
        "answer": answer,
        "citations": citations,
        "retrievedChunkIds": chunk_ids,
        "sourceDocsVersion": os.environ.get("SOURCE_DOCS_VERSION", "seed-2026-07-27"),
        "promptVersion": PROMPT_VERSION,
        "modelVersion": _model_ver(),
        "createdAt": now.isoformat(),
        "expiresAt": exp.isoformat(),
        "sensitivityLabel": os.environ.get("SENSITIVITY_LABEL", "unclassified"),
        "hitCount": 0,
        "questionEmbedding": vec,
    }
    h = await _search_headers()
    url = f"{SEARCH_ENDPOINT}/indexes/{CACHE_INDEX}/docs/index?api-version={SEARCH_API_VER}"
    async with session.post(url, headers=h, json={"value": [doc]}) as r:
        if r.status >= 400:
            log.warning("cache write failed: %s %s", r.status, await r.text())


async def _bump_hit(session: aiohttp.ClientSession, doc_id: str, current: int) -> None:
    """L1 hit path: bump hitCount only (the winning hash is already present)."""
    doc = {"@search.action": "merge", "id": doc_id, "hitCount": current + 1}
    h = await _search_headers()
    url = f"{SEARCH_ENDPOINT}/indexes/{CACHE_INDEX}/docs/index?api-version={SEARCH_API_VER}"
    async with session.post(url, headers=h, json={"value": [doc]}) as r:
        if r.status >= 400:
            log.warning("hit bump failed: %s %s", r.status, await r.text())


async def _promote_to_l1(session: aiohttp.ClientSession, hit: dict[str, Any], new_hash: str) -> None:
    """L2 hit path: append the current question's hash to the winning entry so
    future asks of *this* exact phrasing become L1 hits (no embed step).
    Also bumps hitCount in the same merge call.

    Azure AI Search `merge` action REPLACES collection fields (no append
    primitive), so we read → append (deduped, FIFO-capped) → write back."""
    existing = list(hit.get("cacheKeyHash") or [])
    if new_hash in existing:
        # Race: another replica already promoted this hash. Nothing to do beyond hitCount.
        await _bump_hit(session, hit["id"], hit.get("hitCount") or 0)
        return

    aliases = existing + [new_hash]
    if len(aliases) > MAX_L1_ALIASES:
        # FIFO evict oldest aliases; canonical answer + embedding stay put.
        aliases = aliases[-MAX_L1_ALIASES:]

    doc = {
        "@search.action": "merge",
        "id": hit["id"],
        "cacheKeyHash": aliases,
        "hitCount": (hit.get("hitCount") or 0) + 1,
    }
    h = await _search_headers()
    url = f"{SEARCH_ENDPOINT}/indexes/{CACHE_INDEX}/docs/index?api-version={SEARCH_API_VER}"
    async with session.post(url, headers=h, json={"value": [doc]}) as r:
        if r.status >= 400:
            log.warning("L2->L1 promotion failed: %s %s", r.status, await r.text())
        else:
            log.info("L2->L1 promoted new_hash=%s to cache_id=%s (aliases=%d)",
                     new_hash[:12], hit["id"], len(aliases))


async def _retrieve(session: aiohttp.ClientSession, vec: list[float], hybrid_text: str | None) -> list[dict[str, Any]]:
    body: dict[str, Any] = {
        "vectorQueries": [{"kind": "vector", "vector": vec, "fields": "contentVector", "k": TOP_K}],
        "select": "id,title,content,source",
        "top": TOP_K,
    }
    if hybrid_text:
        body["search"] = hybrid_text
    h = await _search_headers()
    url = f"{SEARCH_ENDPOINT}/indexes/{INDEX_NAME}/docs/search?api-version={SEARCH_API_VER}"
    async with session.post(url, headers=h, json=body) as r:
        r.raise_for_status()
        j = await r.json()
        return j["value"]


async def _chat(session: aiohttp.ClientSession, question: str,
                hits: list[dict[str, Any]]) -> tuple[str, int, int]:
    ctx_parts = []
    for i, h in enumerate(hits, 1):
        ctx_parts.append(f"[{i}] Title: {h['title']}\nSource: {h['source']}\n{h['content']}")
    context = "\n\n---\n\n".join(ctx_parts)
    system = f"{SYSTEM_PROMPT}\n\nCONTEXT:\n{context}"
    body = {
        "messages": [
            {"role": "system", "content": system},
            {"role": "user",   "content": question},
        ],
        "temperature": 0.2,
        "max_tokens": 400,
    }
    hdr = await _aoai_headers()
    url = f"{AOAI_ENDPOINT}/openai/deployments/{CHAT_DEPLOY}/chat/completions?api-version={API_VERSION}"
    async with session.post(url, headers=hdr, json=body) as r:
        r.raise_for_status()
        j = await r.json()
    return (
        j["choices"][0]["message"]["content"],
        j["usage"]["prompt_tokens"],
        j["usage"]["completion_tokens"],
    )


async def answer(question: str, hybrid: bool = False, skip_cache: bool = False) -> RagResult:
    t0 = time.perf_counter()
    q_hash = _hash(question)
    log.info("Q hash=%s hybrid=%s skip_cache=%s", q_hash[:12], hybrid, skip_cache)

    timeout = aiohttp.ClientTimeout(total=45)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        # L1
        if not skip_cache:
            l1 = await _try_l1(session, q_hash)
            if l1:
                await _bump_hit(session, l1["id"], l1.get("hitCount") or 0)
                return RagResult(
                    answer=l1["answer"],
                    citations=list(l1.get("citations") or []),
                    retrieved_chunk_ids=[],
                    cache_layer="L1",
                    cache_id_hit=l1["id"],
                    duration_ms=int((time.perf_counter() - t0) * 1000),
                )

        # Embed once
        vec = await _embed(session, question)

        # L2
        cache_layer = "skip" if skip_cache else "miss"
        l2_cosine: float | None = None
        if not skip_cache:
            l2, cos = await _try_l2(session, vec)
            l2_cosine = cos
            if l2:
                await _promote_to_l1(session, l2, q_hash)
                return RagResult(
                    answer=l2["answer"],
                    citations=list(l2.get("citations") or []),
                    retrieved_chunk_ids=[],
                    cache_layer="L2",
                    cache_id_hit=l2["id"],
                    l2_cosine=cos,
                    duration_ms=int((time.perf_counter() - t0) * 1000),
                )

        # RAG
        hits = await _retrieve(session, vec, question if hybrid else None)
        ans, p_tok, c_tok = await _chat(session, question, hits)
        citations = [h["source"] for h in hits]
        chunk_ids = [h["id"]     for h in hits]

        if not skip_cache:
            try:
                await _write_cache(session, question, q_hash, vec, ans, citations, chunk_ids)
            except Exception as e:
                log.warning("cache write raised: %s", e)

        return RagResult(
            answer=ans,
            citations=citations,
            retrieved_chunk_ids=chunk_ids,
            cache_layer=cache_layer,
            prompt_tokens=p_tok,
            completion_tokens=c_tok,
            l2_cosine=l2_cosine,
            duration_ms=int((time.perf_counter() - t0) * 1000),
        )
