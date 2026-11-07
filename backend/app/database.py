import ssl

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker

from .config import settings

_connect_args: dict = {}
if settings.database_url.startswith("sqlite"):
    _connect_args["check_same_thread"] = False
elif "mysql" in settings.database_url and ("aivencloud.com" in settings.database_url or "ssl" in settings.database_url.lower()):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    _connect_args["ssl"] = ctx

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,
    pool_recycle=300,
    connect_args=_connect_args,
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def ensure_migrations():
    """Jadvallarga yangi ustunlarni xavfsiz qo'shish."""
    from . import models  # Modellar metadatasini yuklash
    Base.metadata.create_all(engine)

    from sqlalchemy import inspect, text
    inspector = inspect(engine)
    table_names = inspector.get_table_names()
    if "products" in table_names:
        columns = [c["name"] for c in inspector.get_columns("products")]
        with engine.begin() as conn:
            if "image_url" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN image_url TEXT NULL"))
            if "has_sorts" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN has_sorts BOOLEAN DEFAULT FALSE"))
            if "sort" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN sort VARCHAR(16) NULL"))
            if "color" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN color VARCHAR(64) NULL"))
            if "category" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN category VARCHAR(64) NULL"))
            if "thickness" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN thickness DECIMAL(14, 3) NULL"))
            if "price_sort1" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN price_sort1 DECIMAL(14, 2) NULL"))
            if "price_sort1_5" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN price_sort1_5 DECIMAL(14, 2) NULL"))
            if "price_sort2" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN price_sort2 DECIMAL(14, 2) NULL"))
            if "tile_length" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN tile_length DECIMAL(14, 3) NULL"))
            if "tile_width" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN tile_width DECIMAL(14, 3) NULL"))
            if "box_pieces" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN box_pieces INTEGER NULL"))
            if "box_m2" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN box_m2 DECIMAL(14, 3) NULL"))
            if "min_stock" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN min_stock DECIMAL(14, 3) NULL DEFAULT 15"))
            if "reserved_qty" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN reserved_qty DECIMAL(14, 3) DEFAULT 0"))
            if "raw_material_id" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN raw_material_id INTEGER NULL REFERENCES products(id)"))
            if "waste_ratio" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN waste_ratio DECIMAL(14, 3) DEFAULT 1.15"))
            if "cutting_rate" not in columns:
                conn.execute(text("ALTER TABLE products ADD COLUMN cutting_rate DECIMAL(14, 2) DEFAULT 0.00"))
            # Baza mahsulotlari uchun kategoriyalarni to'g'rilash (Miramir, Angola va h.k.)
            conn.execute(text("UPDATE products SET category = 'Marmar', sort = 'sort 1' WHERE name IN ('Angola', 'Miramir', 'Tan Brown') AND (category IS NULL OR category = '')"))
            conn.execute(text("UPDATE products SET category = 'Kerama granit', sort = 'sort 1' WHERE name = 'Metalogranit' AND (category IS NULL OR category = '')"))
            conn.execute(text("UPDATE products SET category = 'Qo‘shimcha' WHERE name IN ('Kley', 'Disk', 'Charx') AND (category IS NULL OR category = '')"))
            conn.execute(text("UPDATE products SET category = 'Xomashyo' WHERE name = 'Sim' AND (category IS NULL OR category = '' OR category = 'Kafel')"))
            conn.execute(text("UPDATE products SET category = 'Marmar' WHERE category = 'Granit'"))
            # Kategoriya kelmay qolgan yoki bo'sh bo'lgan har qanday mahsulot avtomatik ravishda "Qo‘shimcha" bo'ladi
            conn.execute(text("UPDATE products SET category = 'Qo‘shimcha' WHERE category IS NULL OR category = ''"))
    if "customers" in table_names:
        c_columns = [c["name"] for c in inspector.get_columns("customers")]
        with engine.begin() as conn:
            if "passport" not in c_columns:
                conn.execute(text("ALTER TABLE customers ADD COLUMN passport VARCHAR(64) NULL"))
            if "photo_url" not in c_columns:
                conn.execute(text("ALTER TABLE customers ADD COLUMN photo_url MEDIUMTEXT NULL"))
    if "sales" in table_names:
        s_columns = [c["name"] for c in inspector.get_columns("sales")]
        with engine.begin() as conn:
            if "status" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN status VARCHAR(20) DEFAULT 'completed'"))
            if "note" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN note VARCHAR(255) NULL"))
            if "currency_rate" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN currency_rate DECIMAL(14, 2) NULL"))
            if "paid_uzs" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN paid_uzs DECIMAL(14, 2) NULL"))
            if "paid_usd" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN paid_usd DECIMAL(14, 2) NULL"))
            if "received_by_name" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN received_by_name VARCHAR(128) NULL"))
            if "received_by_phone" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN received_by_phone VARCHAR(32) NULL"))
            if "delivery_type" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN delivery_type VARCHAR(32) NULL"))
            if "receiver_doc_or_car" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN receiver_doc_or_car VARCHAR(128) NULL"))
            if "fulfilled_by_name" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN fulfilled_by_name VARCHAR(128) NULL"))
            if "fulfilled_at" not in s_columns:
                conn.execute(text("ALTER TABLE sales ADD COLUMN fulfilled_at TIMESTAMP NULL"))
    if "users" in table_names:
        u_columns = [c["name"] for c in inspector.get_columns("users")]
        with engine.begin() as conn:
            if "salary" not in u_columns:
                conn.execute(text("ALTER TABLE users ADD COLUMN salary DECIMAL(14, 2) DEFAULT 0.00"))
            if "salary_type" not in u_columns:
                conn.execute(text("ALTER TABLE users ADD COLUMN salary_type VARCHAR(16) DEFAULT 'monthly'"))
            if "can_login" not in u_columns:
                conn.execute(text("ALTER TABLE users ADD COLUMN can_login BOOLEAN DEFAULT TRUE"))
                conn.execute(text("UPDATE users SET can_login = TRUE WHERE can_login IS NULL"))
            if "is_on_shift" not in u_columns:
                conn.execute(text("ALTER TABLE users ADD COLUMN is_on_shift BOOLEAN DEFAULT TRUE"))
                conn.execute(text("UPDATE users SET is_on_shift = TRUE WHERE is_on_shift IS NULL"))
    if "attendance" in table_names:
        att_columns = [c["name"] for c in inspector.get_columns("attendance")]
        with engine.begin() as conn:
            if "status" not in att_columns:
                conn.execute(text("ALTER TABLE attendance ADD COLUMN status VARCHAR(16) DEFAULT 'present'"))
            if "note" not in att_columns:
                conn.execute(text("ALTER TABLE attendance ADD COLUMN note TEXT NULL"))
            if "worked_hours" not in att_columns:
                conn.execute(text("ALTER TABLE attendance ADD COLUMN worked_hours DECIMAL(14, 3) DEFAULT 0"))
    if "deliveries" in table_names:
        del_columns = [c["name"] for c in inspector.get_columns("deliveries")]
        with engine.begin() as conn:
            if "driver_id" not in del_columns:
                conn.execute(text("ALTER TABLE deliveries ADD COLUMN driver_id INTEGER NULL REFERENCES users(id)"))
            if "is_deleted" not in del_columns:
                conn.execute(text("ALTER TABLE deliveries ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE"))
            try:
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_deliveries_driver_status ON deliveries (driver_id, status)"))
                conn.execute(text("CREATE INDEX IF NOT EXISTS ix_deliveries_sale_status ON deliveries (sale_id, status)"))
            except Exception:
                pass
    if "production_tasks" in table_names:
        pt_columns = [c["name"] for c in inspector.get_columns("production_tasks")]
        with engine.begin() as conn:
            if "waste_qty" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN waste_qty DECIMAL(14, 3) DEFAULT 0"))
            if "approved_by" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN approved_by INTEGER NULL REFERENCES users(id)"))
            if "approved_at" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN approved_at TIMESTAMP NULL"))
            if "order_id" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN order_id INTEGER NULL"))
            if "cut_length" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN cut_length DECIMAL(14, 3) NULL"))
            if "cut_width" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN cut_width DECIMAL(14, 3) NULL"))
            if "cut_pieces" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN cut_pieces INTEGER NULL"))
            if "cut_spec" not in pt_columns:
                conn.execute(text("ALTER TABLE production_tasks ADD COLUMN cut_spec VARCHAR(255) NULL"))
    if "expenses" in table_names:
        exp_columns = [c["name"] for c in inspector.get_columns("expenses")]
        with engine.begin() as conn:
            if "type" not in exp_columns:
                conn.execute(text("ALTER TABLE expenses ADD COLUMN type VARCHAR(16) DEFAULT 'expense'"))
            if "payment_method" not in exp_columns:
                conn.execute(text("ALTER TABLE expenses ADD COLUMN payment_method VARCHAR(16) DEFAULT 'cash'"))
    # Base64 rasmlarni faylga o'tkazish (agar fayl yo'q bo'lsa kesh faylini yaratish)
    try:
        from pathlib import Path
        import base64
        from . import models as m
        upload_dir = Path(__file__).resolve().parent.parent / "uploads" / "products"
        upload_dir.mkdir(parents=True, exist_ok=True)
        with SessionLocal() as s_db:
            from sqlalchemy import select
            prods = s_db.scalars(select(m.Product).where(m.Product.image_url.isnot(None))).all()
            for p in prods:
                val = p.image_url or ""
                if val.startswith("data:image/") or len(val) > 500:
                    try:
                        b64_str = val.split(",", 1)[1] if "," in val else val
                        img_bytes = base64.b64decode(b64_str)
                        filename = f"prod_{p.id}.jpg"
                        filepath = upload_dir / filename
                        if not filepath.exists():
                            with open(filepath, "wb") as f_img:
                                f_img.write(img_bytes)
                    except Exception as e:
                        print(f"Rasm faylga yozishda xato: {e}")
    except Exception as e:
        print(f"Rasm migratsiya xabari: {e}")


