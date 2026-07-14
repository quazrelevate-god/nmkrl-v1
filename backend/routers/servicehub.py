"""
routers/servicehub.py
---------------------
Gemini-backed assistant for the Service Hub page. A Tamil Nadu citizen can ask
free-form questions about any TN government portal and get a concise, factual
answer. When the frontend passes a ``portal`` context (name + tagline + url),
the assistant scopes its answer to that portal.

Endpoint:
  * POST /api/servicehub/chat   { message, history?, portal? } -> { reply }

Fails safe: if GEMINI_API_KEY is not set (or Gemini errors), returns a helpful
canned response so the UI never breaks during a demo.
"""

from __future__ import annotations

import os
import sys
from typing import Optional

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/api/servicehub", tags=["servicehub"])

GEMINI_MODEL = "gemini-2.5-flash"

SYSTEM_PROMPT = """You are a helpful assistant for Tamil Nadu citizens using the Namkural Service Hub.
Your job is to guide citizens to the correct Tamil Nadu government portal for their query and answer questions about:
  * how to apply for certificates, schemes, or services
  * what documents are required
  * how to track applications
  * eligibility, deadlines, and fees
  * how to navigate the portal step-by-step

Rules:
  * Answer in the language the user asks in (Tamil or English). Keep replies short — 3 to 6 lines.
  * Never invent portal URLs. If you don't know the exact URL, say so and direct the user to search on tn.gov.in.
  * Never ask for personal data like Aadhaar, ration card number, or passwords.
  * When you recommend an action, prefer numbered steps.
  * If a question is not about Tamil Nadu government services, politely redirect the user.
"""


class PortalContext(BaseModel):
    name: str
    tagline: Optional[str] = ""
    url: Optional[str] = ""
    description: Optional[str] = ""


class ChatTurn(BaseModel):
    role: str  # "user" | "assistant"
    text: str


class ChatRequest(BaseModel):
    message: str
    history: list[ChatTurn] = []
    portal: Optional[PortalContext] = None


def _mock_reply(message: str, portal: Optional[PortalContext]) -> str:
    """Fallback reply when Gemini is unavailable — keeps demos alive."""
    if portal:
        return (
            f"For questions about {portal.name}, you can visit {portal.url or 'the portal'} "
            f"directly. Live AI assistance is temporarily unavailable — please try again shortly."
        )
    return (
        "I can help you find the right Tamil Nadu government portal for your query. "
        "Live AI assistance is temporarily unavailable — please try again shortly, or "
        "browse the categorised portals on this page."
    )


def _build_prompt(req: ChatRequest) -> str:
    """Compose the full prompt: system + optional portal scope + history + user turn."""
    parts: list[str] = [SYSTEM_PROMPT.strip()]
    if req.portal:
        p = req.portal
        parts.append(
            f"\nThe citizen is currently viewing this portal:\n"
            f"  Name: {p.name}\n"
            f"  Tagline: {p.tagline or ''}\n"
            f"  URL: {p.url or ''}\n"
            f"  About: {p.description or ''}\n"
            f"Scope your reply to this portal unless the user changes topic."
        )
    if req.history:
        parts.append("\nConversation so far:")
        for turn in req.history[-8:]:
            who = "Citizen" if turn.role == "user" else "Assistant"
            parts.append(f"  {who}: {turn.text}")
    parts.append(f"\nCitizen: {req.message}\nAssistant:")
    return "\n".join(parts)


@router.post("/chat")
def chat(req: ChatRequest):
    """Return an assistant reply for the citizen's message."""
    if not req.message or not req.message.strip():
        return {"reply": "Please type a question — for example, 'How do I apply for a community certificate?'"}

    api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
    if not api_key:
        return {"reply": _mock_reply(req.message, req.portal), "mock": True}

    prompt = _build_prompt(req)

    try:
        from google import genai
        from google.genai import types

        client = genai.Client(api_key=api_key)
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[types.Content(role="user", parts=[types.Part(text=prompt)])],
        )
        text = (response.text or "").strip()
        if not text:
            return {"reply": _mock_reply(req.message, req.portal), "mock": True}
        return {"reply": text, "mock": False}
    except Exception as exc:
        print(f"[servicehub] Gemini error: {exc}", file=sys.stderr)
        return {"reply": _mock_reply(req.message, req.portal), "mock": True}
