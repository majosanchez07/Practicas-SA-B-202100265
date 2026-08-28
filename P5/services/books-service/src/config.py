from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Sensible: llega desde el Secret montado por Helm.
    DATABASE_URL: str

    # No sensibles: llegan desde el ConfigMap generado por el chart.
    DB_SCHEMA: str = 'books'
    CORS_ORIGINS: str = '*'
    LOG_LEVEL: str = 'info'
    ENVIRONMENT: str = 'development'
    DEBUG: bool = False

    class Config:
        env_file = '.env'


settings = Settings()
