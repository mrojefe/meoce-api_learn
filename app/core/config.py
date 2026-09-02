"""Application settings. Real environment variables arrive in module 06."""


from functools import lru_cache
from typing import Annotated

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Every value the application reads from its environment.

    Values are resolved in this order: a real environment variable, then the
    .env file, then the default declared here. Fields with no default are
    required — the application refuses to start without them, naming the
    missing variable, instead of failing on the first request that needs it.

    `env` is deliberately required: with a default of "dev", a missing
    MEOCE_ENV in production would make the app believe it is in development
    and publish /docs to the world.

    Attributes:
        env (str): "dev" or "prod". Gates /docs and /redoc in main.py.
        api_version (str): Reported by /health and shown in /docs.
        postgres_host (str): Database host. 127.0.0.1 locally, through the
            port published by Coolify on the staging service.
        postgres_port (int): Converted from text by the annotation.
        postgres_db (str): Database name.
        postgres_user (str): Database user. The API connects as one user
            whoever the human caller is.
        postgres_password (SecretStr): Masked in logs and tracebacks. Read it
            with .get_secret_value(), which happens only in conninfo().

    Examples:
        >>> get_settings().postgres_port
        5433
    """
    model_config = SettingsConfigDict(
        env_file = ".env", 
        env_file_encoding = "utf-8",
        extra="ignore"
        )
    env : Annotated[str, Field(alias="MEOCE_ENV" )] 
    jwt_secret:Annotated[SecretStr, Field(alias="JWT_SECRET")]
    api_key : Annotated[SecretStr, Field(alias="API_KEY")]
    api_version : Annotated[str, Field(alias="API_VERSION" )] = "0.2.0" 

    postgres_host : Annotated[str, Field(alias="POSTGRES_HOST")]
    postgres_port : Annotated[int, Field(alias="POSTGRES_PORT")] = 5432
    postgres_db : Annotated[str, Field(alias="POSTGRES_DB" )]
    postgres_user : Annotated[str, Field(alias="POSTGRES_USER" )]
    postgres_password : Annotated[SecretStr, Field(alias="POSTGRES_PASSWORD" )]
    

@lru_cache    
def get_settings() -> Settings:
    """Returns the settings, building them at most once per process.

    @lru_cache remembers the result, so the .env file is read on the first call
    and never again. A function rather than a module-level object, so importing
    this file does not read the disk — a test that never touches a database
    should not fail because .env is absent.

    Returns:
        Settings: The validated settings.

    Raises:
        ValidationError: If a required variable is missing or has the wrong
            type. Raised at startup, naming the variable.

    Examples:
        >>> get_settings() is get_settings()
        True
    """
    return Settings()
