


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
        # email_verifed it's actually never trigge so in the db we must do it
        sql_stored_pass ="""
                        SELECT password_hash 
                        FROM users 
                        WHERE email = %s 
                        """

        parms_stored_pass = user_mail

        rows = query(sql_stored_pass, (parms_stored_pass,))

        if not rows : 
            raise UnauthorizedError("This email is not registered")
        else :
           sql_stored_pass += """ and email_verified = 'true' """   
           rows = query(sql_stored_pass, (parms_stored_pass,))

           if not rows : 
            raise UnauthorizedError("The password is likely not validate yet contact the support")
       
        stored_hashed_pass = rows[0]["password_hash"]

        # An account whose auth_provider was flipped to 'google' or
        # 'whatsapp' (see app/services/google_auth.py's linking policy)
        # has password_hash = NULL — there is no password to check
        # against. Same vague "passwords do not match" answer as an
        # actual wrong password, deliberately: telling the caller "this
        # account has no password" would reveal which auth method it
        # currently uses.
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

