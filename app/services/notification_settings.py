"""Notification settings — phone, and whether it's been verified.

    NOTE: identity schema is user_identities (one row per login method),
    not a flat users table -- phone/phone_verified live on the 'whatsapp'
    provider row (provider_uid/verified), email on the 'email' provider
    row (provider_uid). Setting a new phone resets verified to False on
    that row — a changed number has not been proven yet, whatever the old
    one's state was.
"""

from app.core.db.database import query


def get_settings(user_id: str) -> dict:
    """Returns the caller's phone and whether it's verified, plus email.

        Args:
            user_id (str): The authenticated caller.

        Returns:
            dict: phone, phone_verified, email.
    """
    sql = """
        SELECT
            (SELECT provider_uid FROM user_identities
                WHERE account_id = %s AND provider = 'whatsapp') AS phone,
            COALESCE((SELECT verified FROM user_identities
                WHERE account_id = %s AND provider = 'whatsapp'), false) AS phone_verified,
            (SELECT provider_uid FROM user_identities
                WHERE account_id = %s AND provider = 'email') AS email
        """
    rows = query(sql, (user_id, user_id, user_id))

    return rows[0]


def update_phone(user_id: str, phone: str | None) -> dict:
    """Sets or clears the caller's phone, resetting verification.

        Args:
            user_id (str): The authenticated caller.
            phone (str | None): The new phone number, or None to clear it.

        Returns:
            dict: phone, phone_verified, email — as it now stands.
    """
    if phone is None:
        query(
            "DELETE FROM user_identities WHERE account_id = %s AND provider = 'whatsapp'",
            (user_id,),
            nothing_return=True,
        )
    else:
        query(
            "INSERT INTO user_identities (account_id, provider, provider_uid, verified) "
            "VALUES (%s, 'whatsapp', %s, false) "
            "ON CONFLICT (account_id, provider) DO UPDATE SET "
            "provider_uid = EXCLUDED.provider_uid, verified = false, verified_at = NULL",
            (user_id, phone),
            nothing_return=True,
        )

    return get_settings(user_id)
