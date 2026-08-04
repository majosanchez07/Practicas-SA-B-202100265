from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    JWT_SECRET_KEY: str
    JWT_ALGORITHM: str = 'HS256'
    ENVIRONMENT: str = 'development'
    DEBUG: bool = True
    PORT: int = 8001

    class Config:
        env_file = '.env'

settings = Settings()
