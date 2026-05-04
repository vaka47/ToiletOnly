from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    environment: str = "development"
    database_url: str = "postgresql+asyncpg://app:app@localhost:5432/toiletonly"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "dev-secret"
    jwt_issuer: str = "toiletonly"
    jwt_audience: str = "toiletonly-app"
    media_base_url: str = "https://cdn.example.com"
    ai_provider: str = "ollama"
    ollama_base_url: str = "http://localhost:11434"
    ollama_model: str = "mistral"
    apns_key_id: str = ""
    apns_team_id: str = ""
    apns_bundle_id: str = "com.toiletonly.app"
    apns_private_key: str = ""
    apns_use_sandbox: bool = True
    media_storage_path: str = "./uploads"
    media_public_url: str = "http://localhost:8000/media"
    apple_client_id: str = "com.toiletonly.app"
    allow_dev_apple_sub_tokens: bool = True
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_pool_timeout: int = 30
    db_pool_recycle_seconds: int = 1800


settings = Settings()
