from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from .. import models as m
from .. import roles
from ..database import get_db
from ..deps import require_roles
from ..schemas import PaymentIn, SaleIn, SaleOut, SaleReturnIn, SaleFulfillIn
from ..services import sales as svc

router = APIRouter(prefix="/sales", tags=["sales"])
_sellers = require_roles(roles.ADMIN, roles.CASHIER, roles.DRIVER, roles.FOREMAN)


def to_out(s: m.Sale) -> SaleOut:
    cashier_name = s.cashier.full_name if (hasattr(s, 'cashier') and s.cashier) else f"Kassir #{s.cashier_id}"
    method = s.payments[0].method if (hasattr(s, 'payments') and s.payments) else "cash"
    return SaleOut(
        id=s.id,
        customer=s.customer,
        cashier_id=s.cashier_id,
        cashier_name=cashier_name,
        total=s.total,
        paid=s.paid,
        debt=s.debt,
        currency_rate=getattr(s, 'currency_rate', None),
        paid_uzs=getattr(s, 'paid_uzs', None),
        paid_usd=getattr(s, 'paid_usd', None),
        status=getattr(s, 'status', 'completed') or 'completed',
        note=getattr(s, 'note', None),
        received_by_name=getattr(s, 'received_by_name', None),
        received_by_phone=getattr(s, 'received_by_phone', None),
        delivery_type=getattr(s, 'delivery_type', None),
        receiver_doc_or_car=getattr(s, 'receiver_doc_or_car', None),
        fulfilled_by_name=getattr(s, 'fulfilled_by_name', None),
        fulfilled_at=getattr(s, 'fulfilled_at', None),
        created_at=s.created_at,
        items=s.items,
        payment_method=method,
    )


@router.post("", response_model=SaleOut, status_code=201)
def create(data: SaleIn, db: Session = Depends(get_db), user: m.User = Depends(_sellers)):
    sale = svc.create_sale(db, user, data)
    db.refresh(sale)
    return to_out(sale)


@router.get("", response_model=list[SaleOut])
def list_sales(limit: int = 200, status: str | None = None, customer_id: int | None = None, db: Session = Depends(get_db), user: m.User = Depends(_sellers)):
    stmt = (
        select(m.Sale)
        .options(
            selectinload(m.Sale.items),
            selectinload(m.Sale.customer),
            selectinload(m.Sale.cashier),
            selectinload(m.Sale.payments),
        )
        .order_by(m.Sale.id.desc())
        .limit(min(limit, 500))
    )
    if status is not None:
        stmt = stmt.where(m.Sale.status == status)
    if customer_id is not None:
        stmt = stmt.where(m.Sale.customer_id == customer_id)
    elif user.role == roles.CASHIER:  # faqat kassir o'z savdolarini ko'radi (boshqaruvchi, haydovchi va admin buyurtmalarni ko'radi)
        stmt = stmt.where(m.Sale.cashier_id == user.id)
    return [to_out(s) for s in db.scalars(stmt).all()]


@router.get("/debts", response_model=list[SaleOut])
def debts(db: Session = Depends(get_db), _: m.User = Depends(_sellers)):
    stmt = (
        select(m.Sale)
        .options(
            selectinload(m.Sale.items),
            selectinload(m.Sale.customer),
            selectinload(m.Sale.cashier),
            selectinload(m.Sale.payments),
        )
        .where(m.Sale.paid < m.Sale.total)
        .order_by(m.Sale.id)
    )
    return [to_out(s) for s in db.scalars(stmt).all()]


@router.get("/{sale_id}", response_model=SaleOut)
def get_sale(sale_id: int, db: Session = Depends(get_db), user: m.User = Depends(_sellers)):
    stmt = (
        select(m.Sale)
        .options(
            selectinload(m.Sale.items),
            selectinload(m.Sale.customer),
            selectinload(m.Sale.cashier),
            selectinload(m.Sale.payments),
        )
        .where(m.Sale.id == sale_id)
    )
    s = db.scalar(stmt)
    if s is None or (user.role != roles.ADMIN and s.cashier_id != user.id):
        raise HTTPException(404, "Savdo topilmadi")
    return to_out(s)


@router.post("/{sale_id}/payments", response_model=SaleOut)
def pay(sale_id: int, data: PaymentIn, db: Session = Depends(get_db),
        user: m.User = Depends(_sellers)):
    return to_out(svc.add_payment(db, user, sale_id, data.amount, data.method))



@router.post("/{sale_id}/fulfill", response_model=SaleOut)
def fulfill(sale_id: int, data: SaleFulfillIn | None = None, db: Session = Depends(get_db), user: m.User = Depends(_sellers)):
    return to_out(svc.fulfill_order(db, user, sale_id, data))


@router.post("/{sale_id}/cancel", response_model=SaleOut)
def cancel(sale_id: int, db: Session = Depends(get_db), user: m.User = Depends(require_roles(roles.ADMIN))):
    return to_out(svc.cancel_order(db, user, sale_id))


@router.post("/{sale_id}/return", response_model=SaleOut)
def return_sale(sale_id: int, data: SaleReturnIn, db: Session = Depends(get_db),
                user: m.User = Depends(require_roles(roles.ADMIN))):
    return to_out(svc.process_return(db, user, sale_id, data.items, data.reason))
