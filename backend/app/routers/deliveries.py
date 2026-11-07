from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session, selectinload

from .. import models as m
from .. import roles
from ..database import get_db
from ..deps import get_current_user, require_roles
from ..schemas import DeliveryCreate, DeliveryOut, DeliveryStatusUpdate, DeliveryUpdate
from ..services.telegram import notify_new_delivery
from ..utils.phone import normalize_phone

router = APIRouter(prefix="/deliveries", tags=["deliveries"])

VALID_TRANSITIONS = {
    "loading": {"on_the_way", "cancelled"},
    "on_the_way": {"delivered", "cancelled"},
    "delivered": set(),
    "cancelled": set(),
}


@router.get("", response_model=list[DeliveryOut])
def list_deliveries(
    status: str | None = None,
    query: str | None = None,
    driver_id: int | None = None,
    limit: int = 100,
    db: Session = Depends(get_db),
    current_user: m.User = Depends(get_current_user),
):
    stmt = (
        select(m.Delivery)
        .options(selectinload(m.Delivery.items))
        .where(m.Delivery.is_deleted.is_(False))
        .order_by(m.Delivery.id.desc())
        .limit(min(limit, 200))
    )
    # Agar haydovchi kirgan bo'lsa:
    # 1) O'ziga biriktirilgan buyurtmalarni
    # 2) Barchaga ochiq (driver_id IS NULL va status == 'loading') buyurtmalarni ko'radi
    if current_user.role == "haydovchi":
        stmt = stmt.where(
            or_(
                m.Delivery.driver_id == current_user.id,
                and_(m.Delivery.driver_id.is_(None), m.Delivery.status == "loading"),
            )
        )
    elif driver_id:
        stmt = stmt.where(m.Delivery.driver_id == driver_id)

    if status and status != "all":
        stmt = stmt.where(m.Delivery.status == status)
    if query:
        q = f"%{query.strip()}%"
        stmt = stmt.where(
            or_(
                m.Delivery.vehicle_number.ilike(q),
                m.Delivery.driver_name.ilike(q),
                m.Delivery.recipient_name.ilike(q),
                m.Delivery.destination_address.ilike(q),
            )
        )
    return list(db.scalars(stmt).all())


@router.get("/{delivery_id}", response_model=DeliveryOut)
def get_delivery(
    delivery_id: int,
    db: Session = Depends(get_db),
    current_user: m.User = Depends(get_current_user),
):
    stmt = (
        select(m.Delivery)
        .options(selectinload(m.Delivery.items))
        .where(m.Delivery.id == delivery_id, m.Delivery.is_deleted.is_(False))
    )
    delivery = db.scalars(stmt).first()
    if delivery is None:
        raise HTTPException(404, "Yetkazib berish yozuvi topilmadi")
    if current_user.role == "haydovchi":
        if delivery.driver_id != current_user.id and not (delivery.driver_id is None and delivery.status == "loading"):
            raise HTTPException(403, "Ushbu buyurtmani ko'rishga ruxsat yo'q")
    return delivery


@router.post("", response_model=DeliveryOut, status_code=201)
def create_delivery(
    data: DeliveryCreate,
    db: Session = Depends(get_db),
    _: m.User = Depends(get_current_user),
):
    driver_id = data.driver_id
    if not driver_id and data.driver_name:
        matched_driver = db.scalar(
            select(m.User).where(
                m.User.role == "haydovchi",
                m.User.full_name.ilike(f"%{data.driver_name.strip()}%"),
            )
        )
        if matched_driver:
            driver_id = matched_driver.id

    delivery = m.Delivery(
        sale_id=data.sale_id,
        driver_id=driver_id,
        vehicle_number=data.vehicle_number.strip().upper(),
        vehicle_model=data.vehicle_model.strip(),
        driver_name=data.driver_name.strip(),
        driver_phone=normalize_phone(data.driver_phone) if data.driver_phone else None,
        recipient_name=data.recipient_name.strip(),
        recipient_phone=normalize_phone(data.recipient_phone) if data.recipient_phone else None,
        destination_address=data.destination_address.strip() if data.destination_address else None,
        delivery_fee=data.delivery_fee,
        fee_payer=data.fee_payer,
        status=data.status,
        dispatch_time=data.dispatch_time or (m.get_server_now() if data.status == "on_the_way" else None),
        delivered_time=data.delivered_time or (m.get_server_now() if data.status == "delivered" else None),
        note=data.note.strip() if data.note else None,
    )
    db.add(delivery)
    db.flush()

    for item in data.items:
        d_item = m.DeliveryItem(
            delivery_id=delivery.id,
            product_id=item.product_id,
            product_name=item.product_name.strip(),
            quantity=item.quantity,
            unit=item.unit.strip(),
        )
        db.add(d_item)

    db.commit()
    db.refresh(delivery)
    notify_new_delivery(
        delivery.id,
        delivery.driver_name,
        f"{delivery.vehicle_model} ({delivery.vehicle_number})",
        delivery.recipient_name,
        delivery.destination_address or "",
        float(delivery.delivery_fee or 0),
    )
    return delivery


@router.put("/{delivery_id}", response_model=DeliveryOut)
def update_delivery(
    delivery_id: int,
    data: DeliveryUpdate,
    db: Session = Depends(get_db),
    _: m.User = Depends(get_current_user),
):
    stmt = (
        select(m.Delivery)
        .options(selectinload(m.Delivery.items))
        .where(m.Delivery.id == delivery_id)
    )
    delivery = db.scalars(stmt).first()
    if delivery is None:
        raise HTTPException(404, "Yetkazib berish yozuvi topilmadi")

    if data.driver_id is not None:
        delivery.driver_id = data.driver_id
    if data.vehicle_number is not None:
        delivery.vehicle_number = data.vehicle_number.strip().upper()
    if data.vehicle_model is not None:
        delivery.vehicle_model = data.vehicle_model.strip()
    if data.driver_name is not None:
        delivery.driver_name = data.driver_name.strip()
    if data.driver_phone is not None:
        delivery.driver_phone = data.driver_phone.strip() or None
    if data.recipient_name is not None:
        delivery.recipient_name = data.recipient_name.strip()
    if data.recipient_phone is not None:
        delivery.recipient_phone = data.recipient_phone.strip() or None
    if data.destination_address is not None:
        delivery.destination_address = data.destination_address.strip() or None
    if data.delivery_fee is not None:
        delivery.delivery_fee = data.delivery_fee
    if data.fee_payer is not None:
        delivery.fee_payer = data.fee_payer
    if data.note is not None:
        delivery.note = data.note.strip() or None

    if data.status is not None and data.status != delivery.status:
        delivery.status = data.status
        if data.status == "on_the_way" and not delivery.dispatch_time:
            delivery.dispatch_time = m.get_server_now()
        elif data.status == "delivered" and not delivery.delivered_time:
            delivery.delivered_time = m.get_server_now()

    if data.dispatch_time is not None:
        delivery.dispatch_time = data.dispatch_time
    if data.delivered_time is not None:
        delivery.delivered_time = data.delivered_time

    if data.items is not None:
        # replace items
        delivery.items.clear()
        for item in data.items:
            d_item = m.DeliveryItem(
                delivery_id=delivery.id,
                product_id=item.product_id,
                product_name=item.product_name.strip(),
                quantity=item.quantity,
                unit=item.unit.strip(),
            )
            db.add(d_item)

    db.commit()
    db.refresh(delivery)
    return delivery


@router.patch("/{delivery_id}/status", response_model=DeliveryOut)
def update_delivery_status(
    delivery_id: int,
    data: DeliveryStatusUpdate,
    db: Session = Depends(get_db),
    current_user: m.User = Depends(get_current_user),
):
    stmt = (
        select(m.Delivery)
        .options(selectinload(m.Delivery.items))
        .where(m.Delivery.id == delivery_id, m.Delivery.is_deleted.is_(False))
    )
    delivery = db.scalars(stmt).first()
    if delivery is None:
        raise HTTPException(404, "Yetkazib berish yozuvi topilmadi")

    # IDOR xavfsizlik tekshiruvi:
    if current_user.role == "haydovchi":
        if delivery.driver_id != current_user.id:
            raise HTTPException(403, "Bu buyurtma sizga tegishli emas! Boshqa haydovchining reysini o'zgartira olmaysiz.")

    # Holatlar ketma-ketligi (State Machine validator)
    if delivery.status != data.status:
        allowed = VALID_TRANSITIONS.get(delivery.status, set())
        if data.status not in allowed:
            raise HTTPException(400, f"Noto'g'ri holat o'tishi: '{delivery.status}' -> '{data.status}' ruxsat etilmagan")

    delivery.status = data.status
    if data.status == "on_the_way" and not delivery.dispatch_time:
        delivery.dispatch_time = m.get_server_now()
    elif data.status == "delivered" and not delivery.delivered_time:
        delivery.delivered_time = m.get_server_now()

    # Audit jurnali
    ts = m.get_server_now().strftime("%Y-%m-%d %H:%M")
    audit_log = f"[{ts} | {current_user.full_name} -> {data.status}]"
    delivery.note = f"{delivery.note} {audit_log}".strip() if delivery.note else audit_log

    db.commit()
    db.refresh(delivery)
    return delivery


@router.delete("/{delivery_id}", status_code=204)
def delete_delivery(
    delivery_id: int,
    db: Session = Depends(get_db),
    _: m.User = Depends(require_roles(roles.ADMIN)),
):
    delivery = db.get(m.Delivery, delivery_id)
    if delivery is None or delivery.is_deleted:
        raise HTTPException(404, "Yetkazib berish yozuvi topilmadi")
    delivery.is_deleted = True
    db.commit()
    return None


@router.post("/{delivery_id}/accept", response_model=DeliveryOut)
def accept_delivery(
    delivery_id: int,
    db: Session = Depends(get_db),
    current_user: m.User = Depends(get_current_user),
):
    # Race condition'ni bartaraf etish uchun qatorni qulflash (Pessimistic Locking)
    stmt = (
        select(m.Delivery)
        .options(selectinload(m.Delivery.items))
        .where(m.Delivery.id == delivery_id)
        .with_for_update()
    )
    delivery = db.scalars(stmt).first()
    if delivery is None:
        raise HTTPException(404, "Yetkazib berish yozuvi topilmadi")

    if current_user.role == "haydovchi" and not current_user.is_on_shift:
        raise HTTPException(400, "Buyurtma qabul qilishdan oldin smenani oching (Ishlamoqda)")

    # Agar buyurtma allaqachon boshqa haydovchi tomonidan olingan bo'lsa
    if delivery.driver_id is not None and delivery.driver_id != current_user.id:
        raise HTTPException(400, "Bu buyurtma allaqachon boshqa haydovchi tomonidan qabul qilingan")

    # Buyurtma holati faqat 'loading' yoki o'ziniki bo'lgan 'on_the_way' bo'lishi mumkin
    if delivery.status not in ("loading", "on_the_way"):
        raise HTTPException(400, f"Ushbu buyurtmani qabul qilib bo'lmaydi (holati: {delivery.status})")

    delivery.driver_id = current_user.id
    delivery.driver_name = current_user.full_name
    if current_user.username and not current_user.username.startswith("worker_"):
        delivery.driver_phone = current_user.username
    delivery.status = "on_the_way"
    if not delivery.dispatch_time:
        delivery.dispatch_time = m.get_server_now()

    db.commit()
    db.refresh(delivery)
    return delivery


@router.post("/{delivery_id}/reject", response_model=DeliveryOut)
def reject_delivery(
    delivery_id: int,
    db: Session = Depends(get_db),
    current_user: m.User = Depends(get_current_user),
):
    # Race condition'ni bartaraf etish uchun qatorni qulflash (Pessimistic Locking)
    stmt = (
        select(m.Delivery)
        .options(selectinload(m.Delivery.items))
        .where(m.Delivery.id == delivery_id)
        .with_for_update()
    )
    delivery = db.scalars(stmt).first()
    if delivery is None:
        raise HTTPException(404, "Yetkazib berish yozuvi topilmadi")

    # Faqat buyurtma biriktirilgan haydovchi yoki admin/kassir rad eta oladi
    if current_user.role not in (roles.ADMIN, roles.CASHIER) and delivery.driver_id != current_user.id:
        raise HTTPException(403, "Sizga biriktirilmagan buyurtmani rad eta olmaysiz")

    # Buyurtmani umumiy ochiq hovuzga qaytarish
    delivery.driver_id = None
    delivery.driver_name = "Ochiq (barchaga)"
    delivery.driver_phone = None
    delivery.status = "loading"
    delivery.dispatch_time = None

    rejection_tag = f"[{current_user.full_name} rad etdi]"
    if delivery.note:
        if rejection_tag not in delivery.note:
            delivery.note = f"{delivery.note} | {rejection_tag}"
    else:
        delivery.note = rejection_tag

    db.commit()
    db.refresh(delivery)
    return delivery


