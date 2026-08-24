"""Application settings. Real environment variables arrive in module 06."""


from functools import lru_cache
from pydantic import Field, SecretStr
from typing import Annotated
from pydantic_settings import BaseSettings, SettingsConfigDict




class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file = ".env", 
        env_file_encoding = "utf-8",
        extra="ignore"
        )
    env : Annotated[str, Field(alias="MEOCE_ENV" )] = "dev"
    api_version : Annotated[str, Field(alias="API_VERSION" )] = "0.2.0" 
    postgres_host : Annotated[str, Field(alias="POSTGRES_HOST")]
    postgres_port : Annotated[int, Field(alias="POSTGRES_PORT")] = 5432
    postgres_db : Annotated[str, Field(alias="POSTGRES_DB" )]
    postgres_user : Annotated[str, Field(alias="POSTGRES_USER" )]
    postgres_password : Annotated[SecretStr, Field(alias="POSTGRES_PASSWORD" )]
    

@lru_cache    
def get_settings() -> Settings:
    return Settings()
