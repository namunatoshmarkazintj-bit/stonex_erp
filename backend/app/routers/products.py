from decimal import Decimal
import os
import shutil
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
import time

from .. import models as m
from .. import roles
from ..database import get_db
from ..deps import get_current_user, require_roles
from ..schemas import ProductIn, ProductOut, ProductUpdate
from ..services.stock import add_movement, get_stock, stock_map

router = APIRouter(prefix="/products", tags=["products"])

UPLOAD_DIR = Path(__file__).resolve().parent.parent.parent / "uploads" / "products"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


def to_out(p: m.Product, stock) -> ProductOut:
    return ProductOut(
        id=p.id,
        name=p.name,
        category=getattr(p, 'category', None),
        sku=p.sku,
        qr_code=p.qr_code,
        unit=p.unit,
        dona_m2=p.dona_m2,
        thickness=getattr(p, 'thickness', None),
        tile_length=getattr(p, 'tile_length', None),
        tile_width=getattr(p, 'tile_width', None),
        box_pieces=getattr(p, 'box_pieces', None),
        box_m2=getattr(p, 'box_m2', None),
        min_stock=getattr(p, 'min_stock', Decimal(15)) if getattr(p, 'min_stock', None) is not None else Decimal(15),
        price=p.price,
        cost_price=p.cost_price,
        sort=getattr(p, 'sort', None),
        has_sorts=getattr(p, 'has_sorts', False) or False,
        color=getattr(p, 'color', None),
        price_sort1=getattr(p, 'price_sort1', None),
        price_sort1_5=getattr(p, 'price_sort1_5', None),
        price_sort2=getattr(p, 'price_sort2', None),
        image_url=p.image_url,
        reserved_qty=getattr(p, 'reserved_qty', Decimal(0)) or Decimal(0),
        raw_material_id=getattr(p, 'raw_material_id', None),
        waste_ratio=getattr(p, 'waste_ratio', None),
        cutting_rate=getattr(p, 'cutting_rate', None),
        is_active=p.is_active,
        deleted_at=getattr(p, 'deleted_at', None),
        deleted_by_name=getattr(p, 'deleted_by_name', None),
        stock=stock,
    )


@router.get("", response_model=list[ProductOut])
@router.get("/", response_model=list[ProductOut])
def list_products(response: Response, q: str | None = None, category: str | None = None, db: Session = Depends(get_db),
                  _: m.User = Depends(get_current_user)):
    t0 = time.time()
    stmt = select(m.Product).where(m.Product.is_active.is_(True)).order_by(m.Product.name)
    if category:
        stmt = stmt.where(m.Product.category == category)
    if q:
        like = f"%{q.strip()}%"
        stmt = stmt.where(or_(m.Product.name.like(like), m.Product.sku.like(like),
                              m.Product.qr_code.like(like), m.Product.color.like(like)))
    prods = db.scalars(stmt).all()
    t1 = time.time()
    stocks = stock_map(db)
    t2 = time.time()
    res = [to_out(p, stocks.get(p.id, 0)) for p in prods]
    t3 = time.time()
    timing_str = f"prods={t1-t0:.3f}s, stocks={t2-t1:.3f}s, to_out={t3-t2:.3f}s"
    response.headers["X-Debug-Timing"] = timing_str
    print(f"DEBUG TIMING: {timing_str}")
    return res


@router.get("/by-code/{code}", response_model=ProductOut)
def by_code(code: str, db: Session = Depends(get_db), _: m.User = Depends(get_current_user)):
    p = db.scalar(select(m.Product).where(
        m.Product.is_active.is_(True), or_(m.Product.qr_code == code, m.Product.sku == code)))
    if p is None:
        raise HTTPException(404, "Mahsulot topilmadi")
    return to_out(p, get_stock(db, p.id))


@router.post("/upload-image")
def upload_image(file: UploadFile = File(...), _: m.User = Depends(require_roles(roles.ADMIN))):
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in [".jpg", ".jpeg", ".png", ".webp", ".gif"]:
        ext = ".jpg"
    filename = f"{uuid.uuid4().hex}{ext}"
    dest_path = UPLOAD_DIR / filename
    with open(dest_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"image_url": f"/uploads/products/{filename}"}


@router.post("/{product_id}/image", response_model=ProductOut)
def upload_product_image(product_id: int, file: UploadFile = File(...),
                         db: Session = Depends(get_db),
                         _: m.User = Depends(require_roles(roles.ADMIN))):
    p = db.get(m.Product, product_id)
    if p is None:
        raise HTTPException(404, "Mahsulot topilmadi")
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in [".jpg", ".jpeg", ".png", ".webp", ".gif"]:
        ext = ".jpg"
    filename = f"prod_{product_id}_{uuid.uuid4().hex[:8]}{ext}"
    dest_path = UPLOAD_DIR / filename
    with open(dest_path, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    p.image_url = f"/uploads/products/{filename}"
    db.commit()
    return to_out(p, get_stock(db, p.id))


@router.post("", response_model=ProductOut, status_code=201)
def create_product(data: ProductIn, db: Session = Depends(get_db),
                   admin: m.User = Depends(require_roles(roles.ADMIN))):
    p = m.Product(
        name=data.name.strip(),
        category=data.category or None,
        sku=data.sku or None,
        qr_code=data.qr_code or None,
        unit=data.unit,
        dona_m2=data.dona_m2,
        thickness=data.thickness,
        tile_length=data.tile_length,
        tile_width=data.tile_width,
        box_pieces=data.box_pieces,
        box_m2=data.box_m2,
        min_stock=data.min_stock if data.min_stock is not None else Decimal(15),
        price=data.price,
        cost_price=data.cost_price,
        sort=data.sort,
        has_sorts=data.has_sorts,
        color=data.color,
        price_sort1=data.price_sort1,
        price_sort1_5=data.price_sort1_5,
        price_sort2=data.price_sort2,
        raw_material_id=data.raw_material_id,
        waste_ratio=data.waste_ratio,
        cutting_rate=data.cutting_rate,
        image_url=data.image_url,
    )
    db.add(p)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "SKU yoki QR-kod allaqachon mavjud")
    if data.initial_stock > 0:
        add_movement(db, product_id=p.id, qty_delta=data.initial_stock, kind=m.MV_OPENING,
                     note="Boshlang'ich qoldiq", user_id=admin.id)
    db.commit()
    return to_out(p, get_stock(db, p.id))


@router.patch("/{product_id}", response_model=ProductOut)
def update_product(product_id: int, data: ProductUpdate, db: Session = Depends(get_db),
                   _: m.User = Depends(require_roles(roles.ADMIN))):
    p = db.get(m.Product, product_id)
    if p is None:
        raise HTTPException(404, "Mahsulot topilmadi")
    for field, value in data.model_dump(exclude_unset=True).items():
        setattr(p, field, value or None if field in ("sku", "qr_code") else value)
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "SKU yoki QR-kod allaqachon mavjud")
    return to_out(p, get_stock(db, p.id))


@router.get("/deleted", response_model=list[ProductOut])
def list_deleted_products(db: Session = Depends(get_db), _: m.User = Depends(require_roles(roles.ADMIN))):
    """O'chirilgan (arxivlangan) mahsulotlar ro'yxati."""
    stmt = select(m.Product).where(m.Product.is_active.is_(False)).order_by(m.Product.deleted_at.desc(), m.Product.name)
    prods = db.scalars(stmt).all()
    stocks = stock_map(db)
    return [to_out(p, stocks.get(p.id, 0)) for p in prods]


@router.post("/{product_id}/restore", response_model=ProductOut)
def restore_product(product_id: int, db: Session = Depends(get_db), _: m.User = Depends(require_roles(roles.ADMIN))):
    """O'chirilgan mahsulotni qayta tiklash."""
    p = db.get(m.Product, product_id)
    if p is None:
        raise HTTPException(404, "Mahsulot topilmadi")
    p.is_active = True
    p.deleted_at = None
    p.deleted_by_name = None
    db.commit()
    return to_out(p, get_stock(db, p.id))


@router.delete("/{product_id}")
def deactivate_product(product_id: int, db: Session = Depends(get_db),
                       user: m.User = Depends(require_roles(roles.ADMIN))):
    """Mahsulotni savatga / arxivga o'tkazish (kim va qachon o'chirgani saqlanadi)."""
    p = db.get(m.Product, product_id)
    if p is None:
        raise HTTPException(404, "Mahsulot topilmadi")
    p.is_active = False
    p.deleted_at = m.utcnow()
    p.deleted_by_name = user.full_name or user.username
    db.commit()
    return {"status": "ok", "message": f"{p.name} o'chirildi"}
