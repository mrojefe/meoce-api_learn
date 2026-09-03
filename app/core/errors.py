"""Erreurs métier + handlers globaux.

Contrat (ARCHITECTURE_MEOCE_V1.md §2.2) :
    { "error": { "code": "...", "message": "...", "status": 404 } }

`code` est stable et machine-readable — le frontend traduit à partir du code,
jamais en parsant le message. Aucune stack trace ne sort.
"""

import logging
from enum import IntEnum, StrEnum, unique

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.schemas.common import ErrorEnvelope


class ErrorStatus(IntEnum):
    """ All status code stay here """

    OK = 200                  # Read succeeded
    CREATED = 201             # Resource created
    NO_CONTENT = 204          # Done; nothing to return
    BAD_REQUEST = 400         # Malformed request
    UNAUTHORIZED = 401        # Not authenticated
    FORBIDDEN = 403           # Authenticated, but not allowed
    METHOD_NOT_ALLOWED = 405  # Method not autorized 
    NOT_FOUND = 404           # Resource does not exist
    CONFLICT = 409             # Conflict with current state
    UNPROCESSABLE_ENTITY = 422  # Data breaks a business rule
    TOO_MANY_REQUESTS = 429   # Too many requests
    INTERNAL_SERVER_ERROR = 500  # Unexpected server error

@unique
class ErrorCode(StrEnum):   
    """ All error code stay here """

    INTERNAL = "internal_error"
    VALIDATION = "validation_error"
    CONFLICT = "conflict_with_current_state"
    NOT_FOUND = "resource_does_not_exist"
    METHOD_NOT_ALLOWED = "resource_does_not_have_this_method"
    HTTP_ERROR = "http_error"
    # Security. All four are carried on a 401, and stay deliberately coarse:
    # a client needs to know it must re-authenticate, not which half of its
    # credential was wrong. REVOKED and TOKEN_EXPIRED belong to JWT (module 10)
    # and are declared here so the vocabulary exists in one place.
    UNAUTHORIZED = "unauthorized"
    FORBIDDEN = "forbidden"
    TOKEN_REVOKED = "token_revoked"
    TOKEN_EXPIRED = "token_expired"
    INVALID_TOKEN = "invalid_token"
    ACCOUNT_SUPENDED="account_suspended"
    ACCOUNT_BANNED="account_banned"


logger = logging.getLogger("meoce.api")




class ApiError(Exception):
    """Base class for every business error the API raises deliberately.

    Carries the three things the error contract needs. Services raise these
    instead of returning an error value, because an exception cannot be
    ignored by a caller who forgets to check.

    Handlers catch `ApiError`, which catches every subclass — so a new error
    type is handled the day it is written, without touching the handler.

    Args:
        code (ErrorCode): Stable, machine-readable. The frontend branches on
            this and never on the message.
        message (str): For humans reading logs. May be reworded freely.
        status (ErrorStatus): The HTTP status the handler will use.

    Examples:
        >>> raise ApiError(ErrorCode.VALIDATION, "bad input", ErrorStatus.UNPROCESSABLE_ENTITY)
    """
    
    def __init__(self, code:ErrorCode, message:str, 
                status:ErrorStatus = ErrorStatus.BAD_REQUEST):

        self.code = code
        self.message = message
        self.status = status
        super().__init__(message)


class NotFoundError(ApiError):
    """The requested resource does not exist. Always 404.

    The status is fixed here so a caller cannot raise a "not found" with the
    wrong code.

    Args:
        message (str): What was not found, for the log.

    Examples:
        >>> raise NotFoundError("this symbol doesn't exist")
    """

    def __init__(self, message: str,code: ErrorCode=ErrorCode.NOT_FOUND, 
                status:ErrorStatus = ErrorStatus.NOT_FOUND ):
        super().__init__(code,message, status)

class ConflictError(ApiError):
    """The request is valid but clashes with the current state. Always 409.

    Used when the input is well-formed and the operation still cannot proceed —
    creating an instrument whose symbol already exists, for example. Distinct
    from 400 (malformed) and 422 (breaks a rule).

    Args:
        message (str): What the conflict is, for the log.

    Examples:
        >>> raise ConflictError("This instrument already exist")
    """

    def __init__(self, message: str , code:ErrorCode=ErrorCode.CONFLICT , 
                status: ErrorStatus = ErrorStatus.CONFLICT):

        super().__init__(code,message,status)


class UnauthorizedError(ApiError):
    """The caller has not proved who or what it is. Always 401.

    401 and 403 are routinely confused, and the distinction is worth holding:

    * **401 Unauthorized** — *"I do not know who you are."* No credential, or a
      credential that does not check out. Presenting a valid one may change the
      answer.
    * **403 Forbidden** — *"I know exactly who you are, and you still may not."*
      Retrying with the same identity changes nothing; this is the plan or the
      role refusing, not the credential.

    So a missing API key is 401. A banned account holding a perfectly valid
    token is 403 — which is why the real API answers 403 there.

    The message is deliberately vague about *why* it failed. Distinguishing
    "unknown key" from "expired key" tells an attacker which half of their guess
    was right.

    Args:
        message (str): For logs and developers, not for branching on.

    Examples:
        >>> raise UnauthorizedError("X-API-KEY header required")
    """

    def __init__(self, message: str , code:ErrorCode=ErrorCode.UNAUTHORIZED , 
                status: ErrorStatus = ErrorStatus.UNAUTHORIZED):

        super().__init__(code,message,status)


class ForbiddenError(ApiError):
    """The caller is known, and still may not. Always 403.

    The counterpart to UnauthorizedError, and the distinction is the whole
    point: 401 means "I do not know who you are", so a valid credential may
    change the answer. 403 means "I know exactly who you are, and the answer is
    still no" — retrying with the same identity changes nothing.

    This is what a plan limit raises. The user is authenticated; their
    subscription simply does not include the feature.

    Args:
        message (str): What is not permitted. Safe to be specific — the caller
            is identified, so naming the missing feature helps rather than
            leaks.

    Examples:
        >>> raise ForbiddenError("Your plan does not include pro_chart_types")
    """

    def __init__(self, message: str, code: ErrorCode = ErrorCode.FORBIDDEN,
                 status: ErrorStatus = ErrorStatus.FORBIDDEN):
        super().__init__(code, message, status)


def _error_response(message, code: ErrorCode, status: ErrorStatus, details=None) -> JSONResponse:
    """Builds the one and only failure body: {"error": {code, message, status}}.

    The single place that knows the error shape, so it cannot drift between the
    four handlers. Built through ErrorEnvelope rather than as a raw dict, so a
    mistake raises here instead of shipping a malformed body.

    Returns a JSONResponse rather than a dict because exception handlers sit
    outside the route system: there is no declared status_code for FastAPI to
    apply, so the response must be constructed.

    Args:
        message (str): Human-readable, for logs and developers.
        code (ErrorCode): Stable machine-readable code.
        status (ErrorStatus): HTTP status, used both in the status line and
            mirrored inside the body.
        details (optional): Extra structured information. Safe for validation
            errors (the client's own input); never attach it to a 500.

    Returns:
        JSONResponse: The response, ready to return from a handler.

    Examples:
        >>> _error_response("No instrument NOPE", ErrorCode.NOT_FOUND, ErrorStatus.NOT_FOUND)
    """

    body = {"code":code , "message": message, "status": status}


    
    if details  : 
        body["details"] = details
    else:
        body.pop("details",None)

    content = ErrorEnvelope(error=body).model_dump()    

    return JSONResponse(
        status_code=status,
        content= content,
    )

def register_error_handler(app: FastAPI) -> None:
    """Attaches the four exception handlers to the application.

    Called once from main.py. Together they guarantee that every failure —
    ours, FastAPI's, or unexpected — leaves in the same shape:

    1. ApiError            our business errors, and every subclass
    2. StarletteHTTPException  FastAPI's own 404/405 and any HTTPException
    3. RequestValidationError  the 422s from body and query validation
    4. Exception           the catch-all: logs the traceback, leaks nothing

    Args:
        app (FastAPI): The application to attach the handlers to.

    Returns:
        None

    Examples:
        >>> register_error_handler(app)     # in main.py, once
    """

    @app.exception_handler(ApiError)
    async def api_error_handler(request: Request, exc: ApiError ):
        """Turns any ApiError raised by a service into the error contract.

        Registered on the base class, so NotFoundError, ConflictError and every
        future subclass are handled the day they are written. The service that
        raised it knows nothing about HTTP; this is where the status is applied.
        """
        return _error_response( exc.message, exc.code, exc.status)

    @app.exception_handler(StarletteHTTPException)
    async def http_error_handler(
        request: Request,
        exc: StarletteHTTPException,
    ):
        """Rewrites Starlette's own HTTP errors into the same contract.

        404 on an unknown route and 405 on a wrong method are raised by the
        framework, before any of our code runs. Without this handler they would
        return Starlette's `{"detail": ...}` — a second error shape a client
        would have to special-case.
        """
        match exc.status_code :
            case  405:
                code = ErrorCode.METHOD_NOT_ALLOWED
                status = ErrorStatus.METHOD_NOT_ALLOWED
                message = "HTTP method not allowed"
            case  404:
                code = ErrorCode.NOT_FOUND
                status = ErrorStatus.NOT_FOUND
                message = "this route doesn't exist"
            case _ : 
                message = str(exc.detail)
                code = ErrorCode.HTTP_ERROR
                status = exc.status_code
            

        return _error_response(message, code, status)

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError):
        """Turns Pydantic's 422 into one readable message plus full details.

        `message` carries the first problem only, phrased for a human. `details`
        carries every problem, structured, for a client that wants to highlight
        each bad field.

        Attaching details is safe here and only here: the content is the
        client's own input echoed back. A 500 never gets details, because there
        the content would be ours.
        """
        first = exc.errors()[0] # exc.error() it's a list of dict, one dict by error find by pydantic
        field = ".".join(str(p) for p in first["loc"][1:])  # drop "query"/"body"
        message = f"{field}: {first['msg']}"  # nb: it's the first error message from pydantic
        
        details = [{"type": e["type"], "loc": [str(p) for p in e["loc"]], "msg": e["msg"]}
            for e in exc.errors()]
       
        return _error_response(message, ErrorCode.VALIDATION, ErrorStatus.UNPROCESSABLE_ENTITY ,details=details)

    @app.exception_handler(Exception)
    async def unhandled_error_handler(request: Request, exc: Exception):
        """Last resort: log the full traceback, return a body that says nothing.

        Anything reaching here is a bug. The traceback goes to the logs, where
        it is needed; the response carries a generic message, because a stack
        trace tells an attacker the file layout, the library versions and often
        the SQL.
        """
        logger.exception("Unhandled error on %s %s", request.method, request.url.path)
        return _error_response("Erreur interne", ErrorCode.INTERNAL, ErrorStatus.INTERNAL_SERVER_ERROR )