"""Bot Framework helpers: outbound auth + reply POST.

We skip the botbuilder-core dependency and just call the REST channel API directly.
In pilot mode (BOT_APP_ID unset), auth is skipped — Bot Framework Emulator can still
reach /api/messages without JWT validation.
"""
from __future__ import annotations

import logging
import os
import time
from typing import Any

import aiohttp

log = logging.getLogger("orchestrator.bot")

BOT_APP_ID     = os.environ.get("BOT_APP_ID", "").strip()
BOT_APP_SECRET = os.environ.get("BOT_APP_SECRET", "").strip()
BOT_TENANT_ID  = os.environ.get("BOT_TENANT_ID", "botframework.com").strip() or "botframework.com"

# In-memory token cache (single-instance app; sufficient for pilot)
_token_cache: dict[str, Any] = {"access_token": None, "expires_at": 0.0}


async def get_bot_token(session: aiohttp.ClientSession) -> str | None:
    """Client-credentials grant for Bot Framework channel outbound calls."""
    if not BOT_APP_ID or not BOT_APP_SECRET:
        return None
    now = time.time()
    if _token_cache["access_token"] and now < _token_cache["expires_at"] - 60:
        return _token_cache["access_token"]

    url = f"https://login.microsoftonline.com/{BOT_TENANT_ID}/oauth2/v2.0/token"
    data = {
        "grant_type":    "client_credentials",
        "client_id":     BOT_APP_ID,
        "client_secret": BOT_APP_SECRET,
        "scope":         "https://api.botframework.com/.default",
    }
    async with session.post(url, data=data) as r:
        r.raise_for_status()
        body = await r.json()
    _token_cache["access_token"] = body["access_token"]
    _token_cache["expires_at"]  = now + int(body.get("expires_in", 3599))
    return body["access_token"]


def build_reply(activity: dict[str, Any], text: str,
                attachments: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    """Construct a reply Activity that echoes the conversation and from/recipient identities."""
    reply: dict[str, Any] = {
        "type": "message",
        "from": activity.get("recipient") or {},
        "recipient": activity.get("from")  or {},
        "conversation": activity.get("conversation") or {},
        "replyToId": activity.get("id"),
        "channelId": activity.get("channelId"),
        "serviceUrl": activity.get("serviceUrl"),
        "text": text,
        "textFormat": "markdown",
    }
    if attachments:
        reply["attachments"]     = attachments
        reply["attachmentLayout"] = "list"
    return reply


async def send_reply(session: aiohttp.ClientSession, activity: dict[str, Any], reply: dict[str, Any]) -> None:
    service_url  = activity["serviceUrl"].rstrip("/")
    conv_id      = activity["conversation"]["id"]
    activity_id  = activity.get("id", "")
    if activity_id:
        url = f"{service_url}/v3/conversations/{conv_id}/activities/{activity_id}"
    else:
        url = f"{service_url}/v3/conversations/{conv_id}/activities"
    headers = {"Content-Type": "application/json"}
    tok = await get_bot_token(session)
    if tok:
        headers["Authorization"] = f"Bearer {tok}"
    async with session.post(url, headers=headers, json=reply) as r:
        if r.status >= 400:
            body = await r.text()
            log.error("send_reply %s -> %s %s", url, r.status, body[:500])
            r.raise_for_status()


def feedback_adaptive_card(question_id: str) -> dict[str, Any]:
    """Adaptive Card 1.4 with helpful / not-helpful / escalate buttons.

    'value' fields are what the channel sends back on Action.Submit — the /api/messages
    handler recognizes them and posts an escalation notification when 'action' == 'escalate'.
    """
    card = {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "body": [
            {"type": "TextBlock", "size": "Small", "isSubtle": True,
             "text": "Was this answer helpful?"},
        ],
        "actions": [
            {"type": "Action.Submit", "title": "\U0001F44D Helpful",
             "data": {"action": "helpful", "questionId": question_id}},
            {"type": "Action.Submit", "title": "\U0001F44E Not helpful",
             "data": {"action": "not_helpful", "questionId": question_id}},
            {"type": "Action.Submit", "title": "\U0001F6A9 Escalate to owner",
             "data": {"action": "escalate", "questionId": question_id}},
        ],
    }
    return {
        "contentType": "application/vnd.microsoft.card.adaptive",
        "content": card,
    }
