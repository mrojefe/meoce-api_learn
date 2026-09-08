"""Guards the email-verify token plumbing against the real Redis instance."""

from app.core.security.deps.email_verify import (
    consume_email_verify_token,
    generate_email_verify_token,
    store_email_verify_token,
)

USER_ID = "c028c759-5fee-402b-a09f-ef39f3c22f31"


def test_token_round_trips():
    """Store, then consume, gets the same user id back."""
    token = generate_email_verify_token()
    store_email_verify_token(token, USER_ID)

    assert consume_email_verify_token(token) == USER_ID


def test_token_is_single_use():
    """Consuming twice returns None the second time — same reasoning as a
    tombstone: a used token must never verify a second account.
    """
    token = generate_email_verify_token()
    store_email_verify_token(token, USER_ID)

    consume_email_verify_token(token)
    assert consume_email_verify_token(token) is None


def test_unknown_token_returns_none():
    assert consume_email_verify_token("this-token-was-never-stored") is None


def test_two_tokens_are_different():
    """Same reasoning as bcrypt's salt: no two tokens should ever collide."""
    assert generate_email_verify_token() != generate_email_verify_token()
