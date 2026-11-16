from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from .. import models as m
from .. import roles
from ..database import get_db
from ..deps import get_current_user, require_roles
from ..schemas import AdjustIn, MovementOut, PurchaseIn
from ..services.sales import to_base_qty
from ..services.stock import add_movement, get_stock
from ..units import q2

router = APIRouter(prefix="/stock", tags=["stock"])
_admin = require_roles(roles.ADMIN)
_stock_access = require_roles(roles.ADMIN, roles.FOREMAN)


def _mv_to_out(mv: m.StockMovement) -> MovementOut:
    return MovementOut(
        id=mv.id,
        product_id=mv.product_id,
        product_name=mv.product.name if mv.product else None,
        qty_delta=mv.qty_delta,
        kind=mv.kind,
        ref_type=mv.ref_type,
        ref_id=mv.ref_id,
        note=mv.note,
        created_by_name=mv.user.full_name if mv.user else None,
        created_at=mv.created_at,
    )


@router.get("/movements", response_model=list[MovementOut])
def movements(product_id: int | None = None, limit: int = 500, db: Session = Depends(get_db),
              _: m.User = Depends(get_current_user)):
    stmt = (
        select(m.StockMovement)
        .options(selectinload(m.StockMovement.product), selectinload(m.StockMovement.user))
        .order_by(m.StockMovement.id.desc())
        .limit(min(limit, 1000))
    )
    if product_id:
        stmt = stmt.where(m.StockMovement.product_id == product_id)
    return [_mv_to_out(mv) for mv in db.scalars(stmt).all()]


@router.post("/purchase", response_model=MovementOut, status_code=201)
def purchase(data: PurchaseIn, db: Session = Depends(get_db), admin: m.User = Depends(_stock_access)):
    """Xarid kirimi. Tannarx — o'rtacha tortilgan (weighted average) usulida yangilanadi."""
    p = db.get(m.Product, data.product_id, with_for_update=True)
    if p is None or not p.is_active:
        raise HTTPException(404, "Mahsulot topilmadi")
    qty = to_base_qty(p, data.quantity, data.unit)
    old_stock = max(get_stock(db, p.id), Decimal(0))
    new_stock = old_stock + qty
    p.cost_price = q2((old_stock * p.cost_price + qty * data.unit_cost) / new_stock)
    mv = add_movement(db, product_id=p.id, qty_delta=qty, kind=m.MV_PURCHASE, note=data.note,
                      user_id=admin.id)
    db.add(m.Notification(
        title="Omborga tovar kirimi",
        message=f"{p.name}: +{qty} {p.unit} qabul qilindi ({admin.full_name or admin.username})",
        kind="system",
        is_read=False,
    ))
    db.commit()
    db.refresh(mv)
    return _mv_to_out(mv)


@router.post("/adjust", response_model=MovementOut, status_code=201)
def adjust(data: AdjustIn, db: Session = Depends(get_db), admin: m.User = Depends(_stock_access)):
    p = db.get(m.Product, data.product_id, with_for_update=True)
    if p is None:
        raise HTTPException(404, "Mahsulot topilmadi")
    if data.delta == 0:
        raise HTTPException(400, "O'zgarish 0 bo'lmasligi kerak")
    if get_stock(db, p.id) + data.delta < 0:
        raise HTTPException(400, "Qoldiq manfiy bo'lib qoladi")
    mv = add_movement(db, product_id=p.id, qty_delta=data.delta, kind=m.MV_ADJUST,
                      note=data.note, user_id=admin.id)
    sign = "+" if data.delta > 0 else ""
    db.add(m.Notification(
        title="Ombor qoldig‘i tuzatildi",
        message=f"{p.name}: {sign}{data.delta} {p.unit} ({admin.full_name or admin.username})",
        kind="warning",
        is_read=False,
    ))
    db.commit()
    db.refresh(mv)
    return _mv_to_out(mv)


@router.post("/clean-purchases")
def clean_all_purchases(
    db: Session = Depends(get_db),
    admin: m.User = Depends(_stock_access),
):
    """Barcha xarid (purchase) yozuvlarini ombor harakatlaridan tozalash."""
    from sqlalchemy import text
    try:
        res = db.execute(text("DELETE FROM stock_movements WHERE kind = 'purchase';"))
        deleted_count = res.rowcount
        db.commit()
        return {
            "status": "ok",
            "message": f"{deleted_count} ta xarid yozuvi muvaffaqiyatli tozalandi.",
            "deleted_count": deleted_count,
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Xaridlarni tozalashda xatolik: {e}")


@router.delete("/movements/{movement_id}", status_code=204)
def delete_movement(
    movement_id: int,
    db: Session = Depends(get_db),
    admin: m.User = Depends(_stock_access),
):
    """Bitta ombor harakatini (masalan, noto'g'ri kiritilgan xaridni) o'chirish."""
    mv = db.get(m.StockMovement, movement_id)
    if mv is None:
        raise HTTPException(404, "Harakat topilmadi")
    db.delete(mv)
    db.commit()
    return None
