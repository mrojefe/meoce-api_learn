"""Transactional email — verification links, and later password-reset etc.

Best-effort by design: a failure here must never break signup itself. The
real app makes the same choice — the user can always ask for the link to be
resent, but a broken mail server should not turn account creation into a 500.
"""

import logging
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

from app.core.config import get_settings
from app.core.security.deps.email_verify import EMAIL_VERIFY_TTL_HOURS
from app.core.security.deps.password_reset import PASSWORD_RESET_TTL_HOURS

logger = logging.getLogger("meoce.email")


def send_verification_email(to: str, verify_url: str) -> bool:
    """Sends the "confirm your email" link. Returns whether it went out.

    Args:
        to (str): The recipient's address.
        verify_url (str): The full link — GET /auth/verify-email?token=...
            already built by the caller.

    Returns:
        bool: True if sent, False on any failure (logged, never raised).
    """
    settings = get_settings()

    message = MIMEMultipart("alternative")
    message["Subject"] = "MEOCE — Vérifiez votre adresse email"
    message["From"] = settings.smtp_from
    message["To"] = to

    expires_in_hours = EMAIL_VERIFY_TTL_HOURS


    html = f"""
    <div style="font-family:sans-serif;max-width:460px;margin:auto;color:#222">
      <h2 style="color:#2962ff">Confirmez votre adresse email</h2>
      <p>Bienvenue sur <strong>MEOCE</strong> ! Cliquez sur le bouton ci-dessous pour
         vérifier que cette adresse vous appartient.</p>
      <p style="text-align:center;margin:28px 0">
        <a href="{verify_url}" style="background:#2962ff;color:#fff;text-decoration:none;
           padding:12px 28px;border-radius:8px;font-weight:600;display:inline-block">
          Vérifier mon email
        </a>
      </p>
      <p style="color:#666;font-size:13px">Ou copiez ce lien dans votre navigateur :<br>
         <a href="{verify_url}" style="color:#2962ff;word-break:break-all">{verify_url}</a></p>
      <p style="color:#999;font-size:12px;border-top:1px solid #eee;padding-top:12px;margin-top:20px">
         Ce lien expire dans {expires_in_hours}h. Si vous n'êtes pas à l'origine de cette inscription,
         ignorez cet email.</p>
    </div>"""
    message.attach(MIMEText(html, "html"))

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
            if settings.smtp_secure:
                server.starttls()
            server.login(settings.smtp_user, settings.smtp_password.get_secret_value())
            server.sendmail(settings.smtp_from, to, message.as_string())
        return True
    except Exception:
        logger.exception("failed to send verification email to %s", to)
        return False


def send_password_reset_email(to: str, reset_url: str) -> bool:
    """Sends the "reset your password" link. Returns whether it went out.

    Same best-effort shape as `send_verification_email`, deliberately: a
    broken mail server here must not turn a routine password-reset request
    into a 500, and the caller (`request_password_reset`) already treats
    every email the same way regardless of whether it's actually registered
    — so this function failing quietly is exactly what keeps that behaviour
    consistent, not a shortcut.

    Args:
        to (str): The recipient's address.
        reset_url (str): The full link the user opens to submit a new
            password, already built by the caller.

    Returns:
        bool: True if sent, False on any failure (logged, never raised).
    """
    settings = get_settings()

    message = MIMEMultipart("alternative")
    message["Subject"] = "MEOCE — Réinitialisation de votre mot de passe"
    message["From"] = settings.smtp_from
    message["To"] = to

    expires_in_hours = PASSWORD_RESET_TTL_HOURS

    html = f"""
    <div style="font-family:sans-serif;max-width:460px;margin:auto;color:#222">
      <h2 style="color:#2962ff">Réinitialisez votre mot de passe</h2>
      <p>Une demande de réinitialisation a été faite pour votre compte <strong>MEOCE</strong>.
         Cliquez sur le bouton ci-dessous pour choisir un nouveau mot de passe.</p>
      <p style="text-align:center;margin:28px 0">
        <a href="{reset_url}" style="background:#2962ff;color:#fff;text-decoration:none;
           padding:12px 28px;border-radius:8px;font-weight:600;display:inline-block">
          Réinitialiser mon mot de passe
        </a>
      </p>
      <p style="color:#666;font-size:13px">Ou copiez ce lien dans votre navigateur :<br>
         <a href="{reset_url}" style="color:#2962ff;word-break:break-all">{reset_url}</a></p>
      <p style="color:#999;font-size:12px;border-top:1px solid #eee;padding-top:12px;margin-top:20px">
         Ce lien expire dans {expires_in_hours}h. Si vous n'êtes pas à l'origine de cette demande,
         ignorez cet email — votre mot de passe actuel reste valable.</p>
    </div>"""
    message.attach(MIMEText(html, "html"))

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port) as server:
            if settings.smtp_secure:
                server.starttls()
            server.login(settings.smtp_user, settings.smtp_password.get_secret_value())
            server.sendmail(settings.smtp_from, to, message.as_string())
        return True
    except Exception:
        logger.exception("failed to send password reset email to %s", to)
        return False
