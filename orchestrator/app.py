"""aiohttp server that hosts:
   POST /api/messages   -- Bot Framework channel endpoint (Direct Line, Teams, Emulator)
   GET  /health         -- liveness for Container Apps
   GET  /ready          -- readiness: makes a tiny AOAI + Search call
   POST /debug/query    -- direct RAG hit for smoke tests
"""
from __future__ import annotations

import logging
import os
import sys
import uuid
from typing import Any

import aiohttp
from aiohttp import web

import rag
import bot

logging.basicConfig(
    level=os.environ.get("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("orchestrator.app")


async def health(_: web.Request) -> web.Response:
    return web.json_response({"status": "ok"})


async def ready(_: web.Request) -> web.Response:
    """Lightweight probe: embed the token 'ping' + read index doc count."""
    try:
        timeout = aiohttp.ClientTimeout(total=10)
        async with aiohttp.ClientSession(timeout=timeout) as s:
            vec = await rag._embed(s, "ping")
            h = await rag._search_headers()
            url = f"{rag.SEARCH_ENDPOINT}/indexes/{rag.INDEX_NAME}/docs/$count?api-version={rag.SEARCH_API_VER}"
            async with s.get(url, headers=h) as r:
                r.raise_for_status()
                count = int(await r.text())
        return web.json_response({"status": "ready", "embed_dim": len(vec), "index_docs": count})
    except Exception as e:
        log.exception("ready probe failed")
        return web.json_response({"status": "error", "detail": str(e)}, status=503)


async def debug_query(req: web.Request) -> web.Response:
    body = await req.json()
    question = (body.get("question") or "").strip()
    if not question:
        return web.json_response({"error": "missing 'question'"}, status=400)
    r = await rag.answer(
        question,
        hybrid=bool(body.get("hybrid")),
        skip_cache=bool(body.get("skipCache")),
    )
    return web.json_response({
        "answer":            r.answer,
        "citations":         r.citations,
        "retrievedChunkIds": r.retrieved_chunk_ids,
        "cacheLayer":        r.cache_layer,
        "l2Cosine":          r.l2_cosine,
        "promptTokens":      r.prompt_tokens,
        "completionTokens":  r.completion_tokens,
        "durationMs":        r.duration_ms,
    })


async def _log_escalation(activity: dict[str, Any], data: dict[str, Any]) -> None:
    """Escalation sink. For pilot: structured stdout (goes to Container Apps logs).
    In production, replace with a Teams webhook post or a SharePoint list write.
    """
    log.warning(
        "ESCALATION user=%s convo=%s question_id=%s data=%s",
        (activity.get("from") or {}).get("name"),
        (activity.get("conversation") or {}).get("id"),
        data.get("questionId"),
        data,
    )
    webhook = os.environ.get("ESCALATION_WEBHOOK", "").strip()
    if webhook:
        try:
            timeout = aiohttp.ClientTimeout(total=10)
            async with aiohttp.ClientSession(timeout=timeout) as s:
                await s.post(webhook, json={
                    "user":       (activity.get("from") or {}).get("name"),
                    "convo":      (activity.get("conversation") or {}).get("id"),
                    "questionId": data.get("questionId"),
                    "channel":    activity.get("channelId"),
                })
        except Exception:
            log.exception("escalation webhook failed")


async def messages(req: web.Request) -> web.Response:
    """Bot Framework channel endpoint. Handles 'message' (question) and 'invoke'/'message'
    with Adaptive Card Action.Submit (feedback / escalation).

    Set env LOOPBACK_MODE=1 (or send header X-Loopback: 1) to echo the reply activity in
    the HTTP response body instead of POSTing it back to serviceUrl — useful for local
    smoke tests without a real Bot Framework channel.
    """
    try:
        activity = await req.json()
    except Exception:
        return web.json_response({"error": "invalid JSON"}, status=400)

    loopback = (
        os.environ.get("LOOPBACK_MODE") == "1"
        or req.headers.get("X-Loopback") == "1"
    )

    a_type = activity.get("type")
    text   = (activity.get("text") or "").strip()
    value  = activity.get("value") or {}

    async def _deliver(reply: dict[str, Any], session: aiohttp.ClientSession) -> web.Response:
        if loopback:
            return web.json_response({"reply": reply}, status=200)
        try:
            await bot.send_reply(session, activity, reply)
        except Exception:
            log.exception("send_reply failed; returning 200 anyway (channel outbound is best-effort)")
        return web.json_response({}, status=200)

    async with aiohttp.ClientSession() as session:
        # ---- Adaptive Card submit ----
        if isinstance(value, dict) and value.get("action") in ("helpful", "not_helpful", "escalate"):
            action = value["action"]
            if action in ("escalate", "not_helpful"):
                await _log_escalation(activity, value)
                reply = bot.build_reply(activity,
                    "Thanks — I flagged this for the FAQ owners. You'll hear back shortly.")
            else:
                reply = bot.build_reply(activity, "Thanks for the feedback \U0001F64F")
            return await _deliver(reply, session)

        # ---- Ordinary chat message ----
        if a_type == "message" and text:
            q_id = uuid.uuid4().hex
            try:
                r = await rag.answer(text, hybrid=False, skip_cache=False)
            except Exception as e:
                log.exception("rag failure")
                reply = bot.build_reply(activity,
                    f"Sorry — I hit an error retrieving that. (Please try again.) `{e}`")
                return await _deliver(reply, session)

            body_md = r.answer
            if r.citations:
                unique = []
                for c in r.citations:
                    if c not in unique:
                        unique.append(c)
                body_md += "\n\n**Sources:** " + ", ".join(f"`{c}`" for c in unique)
            body_md += f"\n\n_cache: {r.cache_layer}_"

            reply = bot.build_reply(
                activity, body_md,
                attachments=[bot.feedback_adaptive_card(q_id)],
            )
            return await _deliver(reply, session)

        # Conversation update, typing, etc.  Ack quietly.
        return web.json_response({}, status=200)


def make_app() -> web.Application:
    app = web.Application(client_max_size=1 << 20)
    app.router.add_get("/health",       health)
    app.router.add_get("/ready",        ready)
    app.router.add_post("/api/messages", messages)
    app.router.add_post("/debug/query",  debug_query)
    return app


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "3978"))
    log.info("starting orchestrator on 0.0.0.0:%d", port)
    web.run_app(make_app(), host="0.0.0.0", port=port)
