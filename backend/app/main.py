from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.gzip import GZipMiddleware
from fastapi.staticfiles import StaticFiles

from .config import settings
from .database import Base, engine, ensure_migrations
from .routers import (
    attendance,
    auth,
    customers,
    deliveries,
    finance,
    notifications,
    production,
    products,
    sales,
    stock,
    users,
)

uploads_dir = Path(__file__).resolve().parent.parent / "uploads"
uploads_dir.mkdir(parents=True, exist_ok=True)


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Jadvallarni yaratish va yangi ustunlarni migratsiya qilish
    Base.metadata.create_all(engine)
    try:
        ensure_migrations()
    except Exception as e:
        print(f"Migratsiya xabari: {e}")

    # Faqat baza bo'sh bo'lsa boshlang'ich seed qilinadi (har safar qayta yuklab serverni qotirmaydi)
    try:
        from .models import User
        from sqlalchemy import select, func
        with engine.connect() as conn:
            user_count = conn.scalar(select(func.count(User.id)))
            if not user_count:
                from .seed import main as seed_db
                seed_db()
    except Exception as e:
        print(f"Boshlang'ich seed xabari: {e}")
    yield


app = FastAPI(title="NTM ERP API", version="0.1.0", lifespan=lifespan)
app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
                   allow_methods=["*"], allow_headers=["*"])

app.mount("/uploads", StaticFiles(directory=str(uploads_dir)), name="uploads")

for r in (auth, users, products, stock, customers, sales, production, finance, notifications, attendance, deliveries):
    app.include_router(r.router)


@app.get("/")
def root():
    return {
        "title": "NTM ERP API (Namuna Tosh Markazi)",
        "status": "online",
        "docs": "/docs",
        "ping": "/ping",
        "version": "2.1-optimized",
    }


import os
import shutil
import platform

@app.get("/health")
def health():
    # Disk statistics
    try:
        total_d, used_d, free_d = shutil.disk_usage("/")
        disk_info = {
            "total_gb": round(total_d / (1024**3), 2),
            "used_gb": round(used_d / (1024**3), 2),
            "free_gb": round(free_d / (1024**3), 2),
            "free_percent": round((free_d / total_d) * 100, 1),
        }
    except Exception as e:
        disk_info = {"error": str(e)}

    # RAM statistics
    ram_info = {}
    try:
        # Cgroup limit (container memory limit)
        cg_limit = None
        cg_usage = None
        for p in ["/sys/fs/cgroup/memory/memory.limit_in_bytes", "/sys/fs/cgroup/memory.max"]:
            if os.path.exists(p):
                with open(p) as f:
                    v = f.read().strip()
                    if v and v != "max":
                        cg_limit = int(v)
                        break
        for p in ["/sys/fs/cgroup/memory/memory.usage_in_bytes", "/sys/fs/cgroup/memory.current"]:
            if os.path.exists(p):
                with open(p) as f:
                    v = f.read().strip()
                    if v:
                        cg_usage = int(v)
                        break

        if cg_limit and cg_limit < 10**12:
            ram_info["container_limit_mb"] = round(cg_limit / (1024 * 1024), 2)
            if cg_usage:
                ram_info["container_used_mb"] = round(cg_usage / (1024 * 1024), 2)
                ram_info["container_free_mb"] = round(max(0, cg_limit - cg_usage) / (1024 * 1024), 2)
                ram_info["container_free_percent"] = round((max(0, cg_limit - cg_usage) / cg_limit) * 100, 1)

        # Linux /proc/meminfo
        if os.path.exists("/proc/meminfo"):
            with open("/proc/meminfo") as f:
                for line in f:
                    if ":" in line:
                        k, v = line.split(":", 1)
                        k = k.strip()
                        val = v.strip().split()[0]
                        if k in ("MemTotal", "MemFree", "MemAvailable"):
                            ram_info[k] = f"{round(int(val) / 1024, 2)} MB"
    except Exception as e:
        ram_info["error"] = str(e)

    return {
        "status": "ok",
        "disk": disk_info,
        "ram": ram_info,
        "os": platform.system(),
        "python_version": platform.python_version(),
    }


@app.get("/ping")
def ping():
    return {"status": "awake"}


@app.get("/setup-db")
def setup_db():
    try:
        Base.metadata.create_all(engine)
        from .seed import main as seed_db
        seed_db()
        return {
            "status": "success",
            "message": "Baza va namunaviy foydalanuvchilar muvaffaqiyatli tayyorlandi!",
            "accounts": {
                "admin": settings.admin_password,
                "kassir": "kassir123",
                "ishchi": "ishchi123",
            },
        }
    except Exception as e:
        import traceback
        return {
            "status": "error",
            "error": str(e),
            "trace": traceback.format_exc(),
        }

