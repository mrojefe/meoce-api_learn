"""Rate limiting — how many times something happened in a time window.

`INCR` is atomic (concurrent requests never lose a count), and the window
resets itself: `EXPIRE` tells Redis to delete the key once the window ends,
so there's no cleanup code anywhere for this.
"""


from app.core.db.redis import get_redis
from app.core.errors import RateLimitError
from app.core.reference import StartRateLimitKeyTypes


def _thistypeofkeyexist(key) :
        valid_type = StartRateLimitKeyTypes
        is_match = any(key.startswith(e.value) for e in valid_type)
        if not is_match :
            raise ValueError(f"the key :  '{key}' is not a valid key for us")

    
def check_rate_limit(key: str, max_attempts: int,
                      window_seconds: int, message_error: str = "") -> None:
    """Raises once `key` has been hit more than `max_attempts` times within
    `window_seconds`.

    Args:
        key (str): What's being limited — e.g. f"login:{email}" or
            f"signup:{ip}". Two different keys never share a counter.
        max_attempts (int): How many attempts are allowed before refusing.
        window_seconds (int): How long the count lives before resetting.
        message_error (str): For logs/developers, not for branching on.

    Raises:
        RateLimitError: The limit was exceeded (429).
    """
    _thistypeofkeyexist(key)
    r = get_redis()
    count = r.incr(key) # store the key and place the value at 1 if it's the first 
                        # time it's encounter it otherwise increase by 1 

    if count == 1:
        # First hit for this key — start its window now. Only here, not
        # every call: re-setting the expiry on every increment would mean
        # a steady stream of requests never actually resets, since the
        # window keeps getting pushed back.
        r.expire(key, window_seconds)

    if count > max_attempts:
        raise RateLimitError(message_error)
