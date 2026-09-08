"""Notification settings — phone, and whether it's been verified.

    Lives on `users`, not `user_profiles`: verification state is an identity
    fact, same table as email/password. Setting a new phone resets
    `phone_verified` to False — a changed number has not been proven yet,
    whatever the old one's state was.
"""

from app.core.db.database import query


def get_settings(user_id: str) -> dict:
    """Returns the caller's phone and whether it's verified, plus email.

        Args:
            user_id (str): The authenticated caller.

        Returns:
            dict: phone, phone_verified, email.
    """
    sql = "SELECT phone, phone_verified, email FROM users WHERE id = %s"
    rows = query(sql, (user_id,))

    return rows[0]


def update_phone(user_id: str, phone: str | None) -> dict:
    """Sets or clears the caller's phone, resetting verification.

        Args:
            user_id (str): The authenticated caller.
            phone (str | None): The new phone number, or None to clear it.

        Returns:
            dict: phone, phone_verified, email — as it now stands.
    """
    sql = """
        UPDATE users
        SET phone = %s, phone_verified = false, updated_at = now()
        WHERE id = %s
        """
    query(sql, (phone, user_id), nothing_return=True)

    return get_settings(user_id)
