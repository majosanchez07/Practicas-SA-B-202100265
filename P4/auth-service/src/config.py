from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DATABASE_URL: str
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = 'HS256'
    JWT_EXPIRATION_MINUTES: int = 30
    JWT_GRACE_PERIOD_MINUTES: int = 5
    AES_SECRET_KEY: str
    AUTHORIZATION_SERVICE_URL: str
    AUTHORIZATION_MAX_RETRIES: int = 3
    AUTHORIZATION_RETRY_BACKOFF: float = 1.5
    ENVIRONMENT: str = 'development'
    DEBUG: bool = True

    class Config:
        env_file = '.env'

settings = Settings()
