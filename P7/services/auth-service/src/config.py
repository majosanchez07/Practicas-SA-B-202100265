from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Sensibles: llegan desde el Secret montado por Helm, nunca con default.
    DATABASE_URL: str
    JWT_SECRET_KEY: str
    AES_SECRET_KEY: str

    # No sensibles: llegan desde el ConfigMap generado por el chart.
    JWT_ALGORITHM: str = 'HS256'
    JWT_EXPIRATION_MINUTES: int = 30
    JWT_GRACE_PERIOD_MINUTES: int = 5
    AUTHORIZATION_SERVICE_URL: str = 'http://localhost:8000'
    AUTHORIZATION_MAX_RETRIES: int = 3
    AUTHORIZATION_RETRY_BACKOFF: float = 1.5
    DB_SCHEMA: str = 'auth'
    CORS_ORIGINS: str = '*'
    LOG_LEVEL: str = 'info'
    ENVIRONMENT: str = 'development'
    DEBUG: bool = False

    class Config:
        env_file = '.env'


settings = Settings()
