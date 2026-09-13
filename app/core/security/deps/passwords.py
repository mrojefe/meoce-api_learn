


from bcrypt import checkpw, gensalt, hashpw
from pydantic import EmailStr

from app.core.db .database import query
from app.core.errors import UnauthorizedError
from app.schemas.common import HardPassword


def hash_password(user_pass : HardPassword) -> str :

    bytes_user_pass = user_pass.encode('utf-8')# the computer need to have a precise encodage
    salt = gensalt() 

    hashed = hashpw(bytes_user_pass, salt)

    return hashed.decode('utf-8')


def _current_user_storage_pass (user_mail: EmailStr):
        # NOTE: identity schema is user_identities (one row per login method,
        # keyed by provider+provider_uid), not a flat users.email column --
        # `credential` here is the stored password hash for the 'email' row.
        sql_stored_pass ="""
                        SELECT credential
                        FROM user_identities
                        WHERE provider = 'email' AND provider_uid = %s
                        """

        params_stored_pass = (user_mail,)

        rows = query(sql_stored_pass, params_stored_pass)

        if not rows :
            raise UnauthorizedError("This email is not registered")
        else :
           sql_stored_pass += """ and verified = true """
           rows = query(sql_stored_pass, params_stored_pass)

           if not rows :
            raise UnauthorizedError("The password is likely not validate yet contact the support")

        stored_hashed_pass = rows[0]["credential"]

        # An account whose Google identity superseded this email identity
        # (see app/services/google_auth.py's linking policy) has
        # credential = NULL -- there is no password to check against. Same
        # vague "passwords do not match" answer as an actual wrong
        # password, deliberately: telling the caller "this account has no
        # password" would reveal which auth method it currently uses.
        if stored_hashed_pass is None:
            raise UnauthorizedError("passwords do not match")

        return stored_hashed_pass

def verify_password_match(user_pass : HardPassword , user_mail : EmailStr ) -> bool:

    stored_hashed_pass = _current_user_storage_pass(user_mail)

    is_matched = checkpw(user_pass.encode('utf-8'),
                    stored_hashed_pass.encode('utf-8'))

    if not is_matched : 
        raise UnauthorizedError("passwords do not match")

    return is_matched # normally true

