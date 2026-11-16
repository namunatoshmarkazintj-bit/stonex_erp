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
                user: m.User = Depends(require_roles(roles.ADMIN, roles.CASHIER))):
    return to_out(svc.process_return(db, user, sale_id, data.items, data.reason, force=data.force))


@router.post("/clean-old-sales")
def clean_old_sales(
    db: Session = Depends(get_db),
    user: m.User = Depends(require_roles(roles.ADMIN)),
):
    """
    #44 chek va bugungi (2026-11-16) savdolardan tashqari barcha eski test savdolarni qaytarish va o'chirish.
    Tovarlar ombor zaxirasiga to'liq qaytariladi.
    """
    from sqlalchemy import text
    try:
        bind = db.get_bind()
        dialect = bind.dialect.name
        if dialect == "sqlite":
            db.execute(text("PRAGMA foreign_keys = OFF;"))
        elif dialect == "mysql":
            db.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))

        # 1. Saqlanishi kerak bo'lgan ID lar: 44 va 2026-11-16 (bugun) dagi barcha savdolar
        keep_ids_res = db.execute(text(
            "SELECT id FROM sales WHERE id = 44 OR created_at >= '2026-11-16 00:00:00';"
        )).scalars().all()
        keep_ids = set(keep_ids_res)
        keep_ids.add(44)

        # 2. O'chirilishi kerak bo'lgan ID lar
        all_ids_res = db.execute(text("SELECT id FROM sales;")).scalars().all()
        delete_ids = [sid for sid in all_ids_res if sid not in keep_ids]

        if not delete_ids:
            return {
                "status": "ok",
                "message": "O'chiriladigan eski savdolar topilmadi, barcha kerakli savdolar saqlangan",
                "kept_sale_ids": sorted(list(keep_ids)),
                "deleted_sale_ids": [],
            }

        del_ids_str = ",".join(str(i) for i in delete_ids)

        # 3. Tovarlarni omborga qaytarish (Vozvrat):
        # Ombordan ayirib olingan harakatlarni o'chirib, qoldiqni tiklaymiz
        db.execute(text(f"DELETE FROM stock_movements WHERE ref_type = 'sale' AND ref_id IN ({del_ids_str});"))
        db.execute(text(f"DELETE FROM delivery_items WHERE delivery_id IN (SELECT id FROM deliveries WHERE sale_id IN ({del_ids_str}));"))
        db.execute(text(f"DELETE FROM deliveries WHERE sale_id IN ({del_ids_str});"))
        db.execute(text(f"DELETE FROM payments WHERE sale_id IN ({del_ids_str});"))
        db.execute(text(f"DELETE FROM sale_items WHERE sale_id IN ({del_ids_str});"))
        db.execute(text(f"DELETE FROM sales WHERE id IN ({del_ids_str});"))

        # Xabarnomalarni tozalash (faqat o'chirilgan savdolar bo'yicha)
        for sid in delete_ids:
            db.execute(text(f"DELETE FROM notifications WHERE message LIKE '%Chek #{sid}%' OR message LIKE '%Buyurtma #{sid}%';"))

        if dialect == "sqlite":
            db.execute(text("PRAGMA foreign_keys = ON;"))
        elif dialect == "mysql":
            db.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))

        db.commit()
        return {
            "status": "ok",
            "message": f"{len(delete_ids)} ta eski savdo muvaffaqiyatli qaytarildi va bazadan to'liq o'chirildi. Tovarlar ombor qoldig'iga qaytdi.",
            "deleted_sale_ids": delete_ids,
            "kept_sale_ids": sorted(list(keep_ids)),
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Tozalashda xatolik: {e}")


@router.post("/restore-sale-49")
def restore_sale_49(db: Session = Depends(get_db)):
    """Sinov uchun bekor qilingan / qaytarilgan #49 chekni asl holatiga qaytarish."""
    from sqlalchemy import text
    try:
        # 1. 49-savdoni qayta tiklash
        db.execute(text("""
            UPDATE sales
            SET status = 'completed',
                total = 378000.00,
                paid = 378000.00,
                paid_uzs = 378000.00,
                paid_usd = 0.00,
                note = '[Qaytarish: 14 kun]'
            WHERE id = 49;
        """))

        # 2. Savdo mahsulotlarini tiklash
        db.execute(text("""
            UPDATE sale_items
            SET quantity = 3.600,
                line_total = 378000.00
            WHERE sale_id = 49;
        """))

        # 3. Omborga noto'g'ri qaytarilgan harakatni o'chirish
        res = db.execute(text("""
            DELETE FROM stock_movements
            WHERE ref_type = 'sale' AND ref_id = 49 AND kind = 'return';
        """))

        # 4. To'lov mavjudligini tekshirish, bo'lmasa yaratish
        p_count = db.execute(text("SELECT count(*) FROM payments WHERE sale_id = 49;")).scalar()
        if not p_count:
            db.execute(text("""
                INSERT INTO payments (sale_id, amount, method, created_at)
                VALUES (49, 378000.00, 'cash', NOW());
            """))

        db.commit()
        return {
            "status": "ok",
            "message": "Chek #49 muvaffaqiyatli asl holatiga qaytarildi!",
            "deleted_return_movements": res.rowcount
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Chekni qaytarishda xatolik: {e}")


@router.post("/reset-all-data")
def reset_all_sales_and_customers(
    db: Session = Depends(get_db),
    user: m.User = Depends(require_roles(roles.ADMIN)),
):
    """Barcha test savdolar va mijozlarni server bazasidan to'liq tozalash."""
    from sqlalchemy import text
    try:
        bind = db.get_bind()
        dialect = bind.dialect.name
        if dialect == "sqlite":
            db.execute(text("PRAGMA foreign_keys = OFF;"))
        elif dialect == "mysql":
            db.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))

        db.execute(text("DELETE FROM delivery_items;"))
        db.execute(text("DELETE FROM deliveries;"))
        db.execute(text("DELETE FROM payments;"))
        db.execute(text("DELETE FROM sale_items;"))
        db.execute(text("DELETE FROM sales;"))
        db.execute(text("DELETE FROM customers;"))
        db.execute(text("DELETE FROM expenses;"))
        db.execute(text("DELETE FROM production_tasks;"))
        db.execute(text("DELETE FROM stock_movements WHERE kind != 'opening';"))
        db.execute(text("DELETE FROM notifications;"))

        if dialect == "sqlite":
            db.execute(text("PRAGMA foreign_keys = ON;"))
        elif dialect == "mysql":
            db.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))

        db.commit()
        return {"status": "ok", "message": "Barcha savdolar, xaridlar, to'lovlar, topshiriqlar va mijozlar server bazasidan to'liq o'chirildi, faqat mahsulotlar qoldi"}
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Tozalashda xatolik: {e}")
