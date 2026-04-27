from pydantic_settings import BaseSettings


class Settings(BaseSettings):
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


settings = Settings()
