"""Sozlamalar. Barchasi muhit o'zgaruvchilaridan yoki .env faylidan olinadi."""
import os
from pathlib import Path

# .env fayli mavjud bo'lsa, avtomatik yuklash
env_file = Path(__file__).resolve().parent.parent / ".env"
if env_file.exists():
    with open(env_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())



class Settings:
    _raw_db: str = (os.getenv("DATABASE_URL") or "").strip().strip('"').strip("'")
    if not _raw_db:
        _raw_db = "mysql+pymysql://root:password@localhost:3306/stone_erp?charset=utf8mb4"

    if _raw_db.startswith("postgres://"):
        _raw_db = _raw_db.replace("postgres://", "postgresql+psycopg2://", 1)
    elif _raw_db.startswith("postgresql://") and "+psycopg2" not in _raw_db:
        _raw_db = _raw_db.replace("postgresql://", "postgresql+psycopg2://", 1)
    elif _raw_db.startswith("mysql://"):
        _raw_db = _raw_db.replace("mysql://", "mysql+pymysql://", 1)

    # Aiven va boshqa bulutli MySQL uchun ssl-mode parametrini tozalash (PyMySQL connect_args orqali oladi)
    _raw_db = _raw_db.replace("?ssl-mode=REQUIRED", "").replace("&ssl-mode=REQUIRED", "")
    _raw_db = _raw_db.replace("?ssl-mode=required", "").replace("&ssl-mode=required", "")

    database_url: str = _raw_db
    secret_key: str = os.getenv("SECRET_KEY", "dev-only-change-me")
    token_minutes: int = int(os.getenv("TOKEN_MINUTES", "720"))
    admin_username: str = os.getenv("ADMIN_USERNAME", "admin")
    admin_password: str = os.getenv("ADMIN_PASSWORD", "admin12345")
    cors_origins: list[str] = [
        o.strip() for o in os.getenv("CORS_ORIGINS", "*").split(",") if o.strip()
    ]


settings = Settings()
