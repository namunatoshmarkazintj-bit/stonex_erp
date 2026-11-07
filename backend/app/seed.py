"""Boshlang'ich ma'lumotlar:  python -m app.seed
Admin akkaunti (.env dagi ADMIN_*) va namunaviy mahsulotlar yaratiladi. Qayta ishga tushirsa
mavjudlarini o'zgartirmaydi."""
from decimal import Decimal
import json
from pathlib import Path
import re

from sqlalchemy import select

from . import models as m
from . import roles
from .config import settings
from .database import Base, SessionLocal, engine, ensure_migrations
from .security import hash_password
from .services.stock import add_movement

SAMPLE = [  # nomi, birlik, dona_m2, narx, tannarx, boshlang'ich qoldiq, kategoriya, sort
    ("Angola", "m2", "0.25", 180000, 120000, 200, "Marmar", "sort 1"),
    ("Miramir", "m2", "0.25", 170000, 110000, 150, "Marmar", "sort 1"),
    ("Tan Brown", "m2", "0.25", 190000, 130000, 120, "Marmar", "sort 1"),
    ("Metalogranit", "m2", None, 150000, 95000, 80, "Kerama granit", "sort 1"),
    ("Kley", "dona", None, 45000, 30000, 100, "Qo‘shimcha", None),
    ("Sim", "m", None, 12000, 7000, 500, "Xomashyo", None),
    ("Disk", "dona", None, 250000, 170000, 30, "Qo‘shimcha", None),
]


def main() -> None:
    Base.metadata.create_all(engine)
    ensure_migrations()
    with SessionLocal() as db:
        admin = db.scalar(select(m.User).where(m.User.username == settings.admin_username))
        if not admin:
            db.add(m.User(username=settings.admin_username, full_name="Xo'jayin",
                          role=roles.ADMIN, password_hash=hash_password(settings.admin_password)))
            print(f"Admin yaratildi: {settings.admin_username}")
        else:
            admin.password_hash = hash_password(settings.admin_password)
            db.commit()
            print(f"Admin paroli yangilandi: {settings.admin_username}")
        if not db.scalar(select(m.User).where(m.User.username == "kassir")):
            db.add(m.User(username="kassir", full_name="Kassir Aziz",
                          role=roles.CASHIER, password_hash=hash_password("kassir123")))
            print("Kassir yaratildi: kassir")
        if not db.scalar(select(m.User).where(m.User.username == "ishchi")):
            db.add(m.User(username="ishchi", full_name="Ishchi Bobur",
                          role=roles.WORKER, password_hash=hash_password("ishchi123")))
            print("Ishchi yaratildi: ishchi")
        if not db.scalar(select(m.User).where(m.User.username == "haydovchi")):
            db.add(m.User(username="haydovchi", full_name="Farhod Haydovchi",
                          role=roles.DRIVER, password_hash=hash_password("haydovchi123")))
            print("Haydovchi yaratildi: haydovchi")
        if not db.scalar(select(m.User).where(m.User.username == "boshqaruvchi")):
            db.add(m.User(username="boshqaruvchi", full_name="Mansur Ish boshqaruvchi",
                          role=roles.FOREMAN, password_hash=hash_password("boshqaruvchi123")))
            print("Ish boshqaruvchi yaratildi: boshqaruvchi")
        for name, unit, dona, price, cost, stock, cat, s_val in SAMPLE:
            existing = db.scalar(select(m.Product).where(m.Product.name == name))
            if existing:
                if cat and existing.category != cat:
                    existing.category = cat
                if s_val and existing.sort != s_val:
                    existing.sort = s_val
                continue
            p = m.Product(name=name, unit=unit, dona_m2=Decimal(dona) if dona else None,
                          price=price, cost_price=cost, qr_code=f"STX-{name.upper().replace(' ', '')}",
                          category=cat, sort=s_val)
            db.add(p)
            db.flush()
            add_movement(db, product_id=p.id, qty_delta=stock, kind=m.MV_OPENING,
                         note="Boshlang'ich qoldiq")

        seed_ntm_dataset(db)

        # Namunaviy bildirishnomalar
        SAMPLE_NOTIFICATIONS = [
            ("Ombor ogohlantirishi", "Metalogranit zaxirasi 80 m² qoldi. Yangi partiya xaridini rejalashtiring.", "warning"),
            ("Qarz to‘lovi qabul qilindi", "Mijoz Akmal aka 300 000 so‘m qarzini naqd to‘ladi.", "payment"),
            ("Yangi savdo amalga oshirildi", "Kassir Aziz tomonidan 1 850 000 so‘mlik savdo qilindi.", "sale"),
            ("Ishlab chiqarish topshirig‘i", "Ishchi Bobur 50 m² Angola toshini qayta ishlashni yakunladi.", "production"),
            ("Tizim ma’lumoti", "NTM — Namuna Tosh Markazi tizimi barcha xodimlar va modullar uchun faol holatda.", "system"),
        ]
        for title, msg, kind in SAMPLE_NOTIFICATIONS:
            if not db.scalar(select(m.Notification).where(m.Notification.title == title)):
                db.add(m.Notification(title=title, message=msg, kind=kind))

        # Namunaviy savdolar
        if not db.scalar(select(m.Sale).limit(1)):
            kassir = db.scalar(select(m.User).where(m.User.username == "kassir"))
            if kassir:
                from datetime import datetime, timedelta
                from .schemas import SaleIn, SaleItemIn
                from .services import sales as svc_sales
                now = datetime.utcnow()
                prods = {p.name: p for p in db.scalars(select(m.Product)).all()}
                sales_to_seed = [
                    (now - timedelta(days=6), [("Angola", 10)], 1800000, "Sardor Qodirov", "+998 90 999 11 22"),
                    (now - timedelta(days=4), [("Kley", 20)], 900000, "Farhod Usta", "+998 91 888 22 33"),
                    (now - timedelta(days=3), [("Metalogranit", 10)], 1000000, "Javohir Toshkent", "+998 93 777 33 44"),
                    (now - timedelta(days=2), [("Disk", 2), ("Sim", 1)], 512000, "Botir Qurilish", "+998 94 666 44 55"),
                    (now - timedelta(days=1), [("Miramir", 5)], 600000, "Akmal aka", "+998 90 123 45 67"),
                    (now, [("Tan Brown", 10)], 1900000, "Sobirjon", "+998 99 555 12 34"),
                ]
                for sale_time, items, paid_val, c_name, c_phone in sales_to_seed:
                    s_items = []
                    for p_name, qty in items:
                        if p_name in prods:
                            s_items.append(SaleItemIn(product_id=prods[p_name].id, quantity=Decimal(qty), unit="base"))
                    if s_items:
                        try:
                            s_obj = svc_sales.create_sale(db, kassir, SaleIn(
                                items=s_items, paid_amount=Decimal(paid_val),
                                customer_name=c_name, customer_phone=c_phone
                            ))
                            s_obj.created_at = sale_time
                            db.flush()
                        except Exception as e:
                            print(f"Sample sale error: {e}")

        db.commit()
    print("Seed tayyor.")


def seed_ntm_dataset(db) -> None:
    data_file = Path(__file__).resolve().parent / "ntm_data.json"
    if not data_file.exists():
        return
    try:
        with open(data_file, "r", encoding="utf-8") as f:
            data = json.load(f)
    except Exception as e:
        print(f"ntm_data.json o'qishda xatolik: {e}")
        return

    # 1. Xodimlar (employees)
    used_usernames = set(db.scalars(select(m.User.username)).all())
    for idx, emp in enumerate(data.get("employees", [])):
        full_name = (emp.get("name") or "").strip()
        if not full_name:
            continue
        role = emp.get("role", roles.WORKER)
        if role not in roles.ALL_ROLES:
            role = roles.WORKER
        salary = Decimal(str(emp.get("salary", 0)))
        phone = (emp.get("phone") or "").strip()
        parts = full_name.lower().split()
        cand_user = re.sub(r"[^a-z0-9]", "", parts[-1] if len(parts) > 1 else parts[0])
        if not cand_user:
            cand_user = f"user_{phone[-4:] if len(phone) >= 4 else idx + 1}"
        if cand_user in used_usernames:
            cand_user = f"{cand_user}_{idx + 1}"
        used_usernames.add(cand_user)

        existing = db.scalar(select(m.User).where((m.User.username == cand_user) | (m.User.full_name == full_name)))
        if not existing:
            pwd = f"{cand_user}123" if len(cand_user) >= 4 else "123456"
            try:
                with db.begin_nested():
                    db.add(m.User(
                        username=cand_user,
                        full_name=full_name,
                        role=role,
                        salary=salary,
                        salary_type="monthly",
                        password_hash=hash_password(pwd),
                        is_active=True,
                        can_login=True,
                    ))
                    db.flush()
                print(f"NTM xodim yaratildi: {full_name} ({cand_user})")
            except Exception as e:
                print(f"Xodim kiritishda xatolik ({full_name}): {e}")

    # 2. Mahsulotlar (products)
    used_skus = set(db.scalars(select(m.Product.sku).where(m.Product.sku.isnot(None))).all())
    for idx, prod in enumerate(data.get("products", [])):
        name = (prod.get("name") or "").strip()
        raw_sku = (prod.get("sku") or "").strip()
        if not name:
            continue

        sku = raw_sku
        if sku and sku in used_skus:
            sku = f"{raw_sku}_{idx + 1}"
        if sku:
            used_skus.add(sku)

        existing = None
        if sku:
            existing = db.scalar(select(m.Product).where(m.Product.sku == sku))
        if not existing:
            existing = db.scalar(select(m.Product).where(m.Product.name == name))

        if existing:
            if category and existing.category != category:
                existing.category = category
            continue

        unit = prod.get("unit", "m2")
        category = prod.get("category")
        price = Decimal(str(prod.get("price", 0)))
        cost_price = Decimal(str(prod.get("cost_price", 0)))
        initial_stock = Decimal(str(prod.get("initial_stock", 0)))
        sort_val = prod.get("sort")
        tile_length = Decimal(str(prod.get("tile_length"))) if prod.get("tile_length") is not None else None
        tile_width = Decimal(str(prod.get("tile_width"))) if prod.get("tile_width") is not None else None
        box_pieces = prod.get("box_pieces")
        box_m2 = None
        if tile_length and tile_width and box_pieces:
            box_m2 = (tile_length * tile_width * Decimal(box_pieces)) / Decimal(10000)

        dona_m2 = Decimal("0.25") if unit == "m2" and "granit" in (category or "").lower() else None

        try:
            with db.begin_nested():
                p = m.Product(
                    name=name,
                    category=category,
                    sku=sku,
                    qr_code=f"QR-{sku}" if sku else f"QR-{name[:8]}_{idx+1}",
                    unit=unit,
                    price=price,
                    cost_price=cost_price,
                    sort=sort_val,
                    tile_length=tile_length,
                    tile_width=tile_width,
                    box_pieces=box_pieces,
                    box_m2=box_m2,
                    dona_m2=dona_m2,
                )
                db.add(p)
                db.flush()
                if initial_stock > 0:
                    add_movement(db, product_id=p.id, qty_delta=initial_stock, kind=m.MV_OPENING,
                                 note="NTM boshlang'ich qoldiq")
            print(f"NTM mahsulot qo'shildi: {name} ({initial_stock} {unit})")
        except Exception as e:
            print(f"Mahsulot kiritishda xatolik ({name}): {e}")


if __name__ == "__main__":
    main()
