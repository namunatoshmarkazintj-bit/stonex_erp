import shutil
import uuid
from decimal import Decimal
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from .. import models as m
from .. import roles
from ..database import get_db
from ..deps import require_roles
from ..schemas import CustomerIn, CustomerOut

router = APIRouter(prefix="/customers", tags=["customers"])
_sellers = require_roles(roles.ADMIN, roles.HEAD, roles.CASHIER)

UPLOAD_DIR = Path(__file__).resolve().parent.parent.parent / "uploads" / "customers"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)


@router.get("", response_model=list[CustomerOut])
def list_customers(
    q: str | None = None,
    db: Session = Depends(get_db),
    _: m.User = Depends(_sellers),
):
    query = select(m.Customer)
    if q and q.strip():
        term = f"%{q.strip().lower()}%"
        query = query.where(
            or_(
                func.lower(m.Customer.name).like(term),
                func.lower(m.Customer.phone).like(term),
                func.lower(m.Customer.passport).like(term),
            )
        )
    customers = db.scalars(query.order_by(m.Customer.name)).all()

    # Xaridlar statistikasini hisoblash
    res: list[CustomerOut] = []
    for c in customers:
        total_spent = Decimal(0)
        total_paid = Decimal(0)
        sales_count = len(c.sales) if c.sales else 0
        if c.sales:
            for s in c.sales:
                total_spent += s.total or Decimal(0)
                total_paid += s.paid or Decimal(0)
        total_debt = total_spent - total_paid

        res.append(
            CustomerOut(
                id=c.id,
                name=c.name,
                phone=c.phone,
                passport=c.passport,
                photo_url=c.photo_url,
                created_at=c.created_at,
                total_spent=total_spent,
                total_debt=total_debt,
                sales_count=sales_count,
            )
        )
    return res


@router.get("/{id}", response_model=CustomerOut)
def get_customer(id: int, db: Session = Depends(get_db), _: m.User = Depends(_sellers)):
    c = db.get(m.Customer, id)
    if not c:
        raise HTTPException(404, "Mijoz topilmadi")
    total_spent = Decimal(0)
    total_paid = Decimal(0)
    sales_count = len(c.sales) if c.sales else 0
    if c.sales:
        for s in c.sales:
            total_spent += s.total or Decimal(0)
            total_paid += s.paid or Decimal(0)
    total_debt = total_spent - total_paid
    return CustomerOut(
        id=c.id,
        name=c.name,
        phone=c.phone,
        passport=c.passport,
        photo_url=c.photo_url,
        created_at=c.created_at,
        total_spent=total_spent,
        total_debt=total_debt,
        sales_count=sales_count,
    )


@router.post("", response_model=CustomerOut, status_code=201)
def create_customer(data: CustomerIn, db: Session = Depends(get_db), _: m.User = Depends(_sellers)):
    c = m.Customer(
        name=data.name.strip(),
        phone=data.phone.strip() if data.phone else None,
        passport=data.passport.strip() if data.passport else None,
        photo_url=data.photo_url.strip() if data.photo_url else None,
    )
    db.add(c)
    db.commit()
    db.refresh(c)
    return CustomerOut(
        id=c.id,
        name=c.name,
        phone=c.phone,
        passport=c.passport,
        photo_url=c.photo_url,
        created_at=c.created_at,
        total_spent=Decimal(0),
        total_debt=Decimal(0),
        sales_count=0,
    )


@router.put("/{id}", response_model=CustomerOut)
def update_customer(id: int, data: CustomerIn, db: Session = Depends(get_db), _: m.User = Depends(_sellers)):
    c = db.get(m.Customer, id)
    if not c:
        raise HTTPException(404, "Mijoz topilmadi")
    c.name = data.name.strip()
    c.phone = data.phone.strip() if data.phone else None
    c.passport = data.passport.strip() if data.passport else None
    if data.photo_url is not None:
        c.photo_url = data.photo_url.strip() if data.photo_url else None
    db.commit()
    db.refresh(c)
    total_spent = Decimal(0)
    total_paid = Decimal(0)
    sales_count = len(c.sales) if c.sales else 0
    if c.sales:
        for s in c.sales:
            total_spent += s.total or Decimal(0)
            total_paid += s.paid or Decimal(0)
    total_debt = total_spent - total_paid
    return CustomerOut(
        id=c.id,
        name=c.name,
        phone=c.phone,
        passport=c.passport,
        photo_url=c.photo_url,
        created_at=c.created_at,
        total_spent=total_spent,
        total_debt=total_debt,
        sales_count=sales_count,
    )


@router.post("/upload-image")
def upload_customer_image(file: UploadFile = File(...), _: m.User = Depends(_sellers)):
    ext = Path(file.filename or "").suffix.lower()
    if ext not in [".jpg", ".jpeg", ".png", ".webp"]:
        ext = ".jpg"
    filename = f"cust_{uuid.uuid4().hex}{ext}"
    dest_path = UPLOAD_DIR / filename
    with dest_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)
    return {"image_url": f"/uploads/customers/{filename}"}


@router.delete("/{id}", status_code=204)
def delete_customer(id: int, db: Session = Depends(get_db), _: m.User = Depends(require_roles(roles.ADMIN))):
    c = db.get(m.Customer, id)
    if not c:
        raise HTTPException(404, "Mijoz topilmadi")
    if c.sales:
        raise HTTPException(400, "Xaridlari mavjud mijozni o'chirib bo'lmaydi")
    db.delete(c)
    db.commit()
