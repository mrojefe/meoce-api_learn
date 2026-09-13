"""Shared account-creation helper for every provider (email, Google,
WhatsApp).

Each provider's signup does the exact same three-row shape: an `accounts`
row (the root identity), one `user_identities` row (the provider-specific
login method), and an empty `user_profiles` row (display data, filled in
later). Only the `user_identities` INSERT differs between providers -- the
`accounts`/`user_profiles` rows are identical every time. Before this
module existed, `auth.py`, `google_auth.py`, and `whatsapp_auth.py` each
repeated the same three-statement transaction with only the identity
INSERT swapped out.
"""

from app.core.db.database import transaction


def create_account_with_identity(sql_identity: str, params_identity_rest: tuple) -> str:
    """Creates an accounts + user_identities + user_profiles row, atomically.

    All three inserts run in one transaction() block: a failure on the
    identity or profile insert (e.g. a duplicate provider_uid) rolls back
    the accounts insert too, instead of leaving an orphaned accounts row
    with no login method and no profile attached.

    Args:
        sql_identity (str): The INSERT INTO user_identities statement for
            this provider. Its first placeholder must be account_id (the
            column user_identities.account_id) -- this function supplies
            that value itself, from the accounts insert that runs
            immediately before it.
        params_identity_rest (tuple): Every value sql_identity needs
            *after* account_id, in placeholder order -- e.g. for the
            'email' provider, (email, hashed_password).

    Returns:
        str: The new account's id. Named user_id, not account_id, to
            match how every caller already refers to it -- account_id is
            the SQL column name (user_identities.account_id), not the
            convention this codebase uses for the Python variable holding
            it (user_id, used everywhere else: JWT payloads, watchlists,
            preferences, entitlements...).

    Examples:
        >>> sql_identity = (
        ...     "INSERT INTO user_identities "
        ...     "(account_id, provider, provider_uid, credential, verified) "
        ...     "VALUES (%s, 'email', %s, %s, false)"
        ... )
        >>> params_identity_rest = (email, hash_password(password))
        >>> user_id = create_account_with_identity(sql_identity, params_identity_rest)
    """
    sql_accounts = "INSERT INTO accounts DEFAULT VALUES RETURNING id"
    sql_profile = "INSERT INTO user_profiles (id) VALUES (%s)"

    with transaction() as conn:
        user_id = str(conn.execute(sql_accounts).fetchone()["id"])

        params_identity = (user_id, *params_identity_rest)
        conn.execute(sql_identity, params_identity)

        params_profile = (user_id,)
        conn.execute(sql_profile, params_profile)

    return user_id
