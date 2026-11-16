from decimal import Decimal

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from ..models import StockMovement, Product
from ..units import q3


def get_stock(db: Session, product_id: int) -> Decimal:
    st = db.scalar(select(Product.stock).where(Product.id == product_id))
    if st is not None:
        return q3(st)
    total = db.scalar(
        select(func.coalesce(func.sum(StockMovement.qty_delta), 0)).where(
            StockMovement.product_id == product_id
        )
    )
    return q3(total or 0)


def stock_map(db: Session) -> dict[int, Decimal]:
    rows = db.execute(select(Product.id, Product.stock)).all()
    has_values = any(st is not None for _, st in rows)
    if has_values:
        return {pid: q3(st or 0) for pid, st in rows}
    rows = db.execute(
        select(StockMovement.product_id, func.sum(StockMovement.qty_delta)).group_by(
            StockMovement.product_id
        )
    ).all()
    return {pid: q3(total or 0) for pid, total in rows}


def add_movement(db: Session, *, product_id, qty_delta, kind, ref_type=None, ref_id=None,
                 note=None, user_id=None) -> StockMovement:
    delta = q3(qty_delta)
    mv = StockMovement(product_id=product_id, qty_delta=delta, kind=kind,
                       ref_type=ref_type, ref_id=ref_id, note=note, created_by=user_id)
    db.add(mv)
    db.execute(
        update(Product)
        .where(Product.id == product_id)
        .values(stock=func.coalesce(Product.stock, 0) + delta)
    )
    return mv
