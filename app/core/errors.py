"""Erreurs métier + handlers globaux.

Contrat (ARCHITECTURE_MEOCE_V1.md §2.2) :
    { "error": { "code": "...", "message": "...", "status": 404 } }

`code` est stable et machine-readable — le frontend traduit à partir du code,
jamais en parsant le message. Aucune stack trace ne sort.
"""

from fastapi.responses import JSONResponse
from fastapi import FastAPI, Request
from starlette.exceptions import  HTTPException as StarletteHTTPException
from fastapi.exceptions import RequestValidationError
from app.schemas.common import ErrorEnvelope
from app.core.enum import ErrorStatus ,ErrorCode
import logging
logger = logging.getLogger("meoce.api")




class ApiError(Exception):
    
    def __init__(self, code:ErrorCode, message:str, 
                status:ErrorStatus = ErrorStatus.BAD_REQUEST):

        self.code = code
        self.message = message
        self.status = status
        super().__init__(message)

class NotFoundError(ApiError):

    def __init__(self, message: str,code: ErrorCode=ErrorCode.NOT_FOUND, 
                status:ErrorStatus = ErrorStatus.NOT_FOUND ):
        super().__init__(code,message, status)

class ConflictError(ApiError):

    def __init__(self, message: str , code:ErrorCode=ErrorCode.CONFLICT , 
                status: ErrorStatus = ErrorStatus.CONFLICT):

        super().__init__(code,message,status)


def _error_response(message,code:ErrorCode,status:ErrorStatus,details=None) ->JSONResponse:

    body = {"code":code , "message": message, "status": status}
    if details  : 
        body["details"] = details

    content = ErrorEnvelope(error=body).model_dump()
    return JSONResponse(
        status_code=status,
        content= content,
    )

def register_error_handler(app: FastAPI) -> None : 

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

     #   
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
    