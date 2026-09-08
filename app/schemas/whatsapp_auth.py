"""Schemas for the WhatsApp signup/attach flow.

`WhatsappStatusResponse` is deliberately reused for both `GET
/auth/whatsapp/status` (signup) and the attach flow's status checking —
attach simply never populates the token fields, since the caller already
holds a valid session and doesn't need a new one. Same reasoning as
`AccessToken` reusing shape across `/auth/refresh` rather than inventing a
near-identical model per route.
"""

from pydantic import BaseModel


class StartWhatsappSignupResponse(BaseModel):
    """The body returned by POST /auth/whatsapp/start.

    Everything a frontend needs to show the user what to do next: the code
    to send, the number to send it to, and how long they have before the
    code expires and a fresh one must be requested.
    """

    code: str
    whatsapp_number: str
    expires_in_seconds: int


class WhatsappStatusResponse(BaseModel):
    """The body returned by GET /auth/whatsapp/status and
    POST /users/me/whatsapp/attach's status check.

    `status` is one of "pending" (no matching message seen yet — the
    normal state while the frontend is polling, not an error) or
    "confirmed" (the code was matched against an inbound WhatsApp message).
    The token fields are only populated on the signup path — an attach
    confirmation returns `status="confirmed"` with no tokens, since the
    caller already has a session.
    """

    status: str
    access_token: str | None = None
    refresh_token: str | None = None
    token_type: str | None = None


class CheckWhatsappResponse(BaseModel):
    """The body returned by GET /auth/whatsapp/check.

    A yes/no answer only — this never touches the code flow, Redis, or the
    database. It exists so a client can validate a phone number is real
    (has WhatsApp at all) before offering the signup/attach flow for it.
    """

    exists: bool
