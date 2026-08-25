"""Erreurs métier + handlers globaux.

Contrat (ARCHITECTURE_MEOCE_V1.md §2.2) :
    { "error": { "code": "...", "message": "...", "status": 404 } }

`code` est stable et machine-readable — le frontend traduit à partir du code,
jamais en parsant le message. Aucune stack trace ne sort.
"""

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.enums import ErrorCode, ErrorStatus
from app.schemas.common import ErrorEnvelope

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
        return _error_response( exc.message, exc.code, exc.status)

    @app.exception_handler(StarletteHTTPException)
    async def http_error_handler(
        request: Request,
        exc: StarletteHTTPException,
    ):  
        if exc.status_code == 405:
            code = ErrorCode.METHOD_NOT_ALLOWED
            status = ErrorStatus.METHOD_NOT_ALLOWED
            message = "HTTP method not allowed"
        elif exc.status_code == 404:
            code = ErrorCode.NOT_FOUND
            status = ErrorStatus.NOT_FOUND
            message = "this route doesn't exist"
        else:
            message = str(exc.detail)
            code = ErrorCode.HTTP_ERROR
            status = exc.status_code
            

        return _error_response(message, code, status)

    @app.exception_handler(RequestValidationError)
    async def validation_error_handler(request: Request, exc: RequestValidationError):
        first = exc.errors()[0] # exc.error() it's a list of dict, one dict by error find by pydantic
        field = ".".join(str(p) for p in first["loc"][1:])  # drop "query"/"body"
        message = f"{field}: {first['msg']}"  # nb: it's the first error message from pydantic
        
        details = [{"type": e["type"], "loc": [str(p) for p in e["loc"]], "msg": e["msg"]}
            for e in exc.errors()]
       
        return _error_response(message, ErrorCode.VALIDATION, ErrorStatus.UNPROCESSABLE_ENTITY ,details=details)

    @app.exception_handler(Exception)
    async def unhandled_error_handler(request: Request, exc: Exception):
        logger.exception("Unhandled error on %s %s", request.method, request.url.path)
        return _error_response("Erreur interne", ErrorCode.INTERNAL, ErrorStatus.INTERNAL_SERVER_ERROR )