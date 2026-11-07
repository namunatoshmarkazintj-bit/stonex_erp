from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import models as m
from .. import roles
from ..database import get_db
from ..deps import require_roles
from ..schemas import TaskCreate, TaskOut, TaskReport, TaskReject
from ..services.stock import add_movement
from ..units import q3

router = APIRouter(prefix="/production", tags=["production"])
_prod = require_roles(roles.ADMIN, roles.WORKER, roles.FOREMAN)


def to_out(t: m.ProductionTask) -> TaskOut:
    return TaskOut(
        id=t.id,
        product_id=t.product_id,
        product_name=t.product.name,
        unit=t.product.unit,
        assigned_to=t.assigned_to,
        worker_name=t.worker.full_name,
        planned_qty=t.planned_qty,
        produced_qty=t.produced_qty,
        waste_qty=getattr(t, "waste_qty", Decimal(0)) or Decimal(0),
        status=t.status,
        approved_by=getattr(t, "approved_by", None),
        approved_at=getattr(t, "approved_at", None),
        note=t.note,
        order_id=getattr(t, "order_id", None),
        cut_length=getattr(t, "cut_length", None),
        cut_width=getattr(t, "cut_width", None),
        cut_pieces=getattr(t, "cut_pieces", None),
        cut_spec=getattr(t, "cut_spec", None),
    )


def _apply_production_and_bom(db: Session, t: m.ProductionTask, qty: Decimal, waste: Decimal, actor_id: int):
    """Xomashyoni ombordan hisobdan chiqarish (BOM) va tayyor toshni kirim qilish."""
    # 1. Xomashyo sarfi (BOM)
    if t.product.raw_material_id:
        ratio = t.product.waste_ratio or Decimal("1.15")
        raw_consumed = (qty + waste) * ratio
        add_movement(
            db,
            product_id=t.product.raw_material_id,
            qty_delta=-raw_consumed,
            kind=m.MV_RAW,
            ref_type="task",
            ref_id=t.id,
            note="Xomashyo sarfi (BOM)",
            user_id=actor_id,
        )

    # 2. Tayyor toshni omborga kirim qilish
    add_movement(
        db,
        product_id=t.product_id,
        qty_delta=qty,
        kind=m.MV_PRODUCTION,
        ref_type="task",
        ref_id=t.id,
        note="Ishlab chiqarish kirimi",
        user_id=actor_id,
    )

    # 3. Usta / Ishchiga ishbay haq hisoblash
    if t.product.cutting_rate and t.product.cutting_rate > Decimal(0):
        earned = qty * t.product.cutting_rate
        worker = db.get(m.User, t.assigned_to)
        if worker:
            worker.salary = (worker.salary or Decimal(0)) + earned


@router.get("", response_model=list[TaskOut])
def list_tasks(db: Session = Depends(get_db), user: m.User = Depends(_prod)):
    stmt = select(m.ProductionTask).order_by(m.ProductionTask.id.desc()).limit(300)
    if user.role == roles.WORKER:  # ishchi faqat o'z topshiriqlarini ko'radi
        stmt = stmt.where(m.ProductionTask.assigned_to == user.id)
    return [to_out(t) for t in db.scalars(stmt).all()]


@router.post("", response_model=TaskOut, status_code=201)
def create_task(data: TaskCreate, db: Session = Depends(get_db),
                _: m.User = Depends(require_roles(roles.ADMIN, roles.FOREMAN))):
    if db.get(m.Product, data.product_id) is None:
        raise HTTPException(404, "Mahsulot topilmadi")
    worker = db.get(m.User, data.assigned_to)
    if worker is None or worker.role != roles.WORKER or not worker.is_active:
        raise HTTPException(400, "Topshiriq faqat faol ishchiga beriladi")
    t = m.ProductionTask(product_id=data.product_id, assigned_to=data.assigned_to,
                         planned_qty=data.planned_qty, note=data.note,
                         order_id=data.order_id, cut_length=data.cut_length,
                         cut_width=data.cut_width, cut_pieces=data.cut_pieces,
                         cut_spec=data.cut_spec)
    db.add(t)

    # Bildirishnoma yaratish
    prod = db.get(m.Product, data.product_id)
    p_name = prod.name if prod else "Mahsulot"
    p_unit = prod.unit if prod else "m²"
    db.add(m.Notification(
        title="Yangi ishlab chiqarish topshirig‘i",
        message=f"{worker.full_name} ga {t.planned_qty} {p_unit} {p_name} topshirig‘i biriktirildi.",
        kind="production",
    ))

    db.commit()
    db.refresh(t)
    return to_out(t)


@router.post("/{task_id}/report", response_model=TaskOut)
def report(task_id: int, data: TaskReport, db: Session = Depends(get_db),
           user: m.User = Depends(_prod)):
    """Bajarilgan ishni qayd etadi."""
    t = db.get(m.ProductionTask, task_id, with_for_update=True)
    if t is None or (user.role == roles.WORKER and t.assigned_to != user.id):
        raise HTTPException(404, "Topshiriq topilmadi")
    if t.status == "done":
        raise HTTPException(400, "Topshiriq yopilgan")

    qty = q3(data.produced_qty)
    waste = q3(data.waste_qty or Decimal(0))
    t.produced_qty = t.produced_qty + qty
    t.waste_qty = (t.waste_qty or Decimal(0)) + waste

    # Agar admin / ish boshqaruvchi o'zi kiritayotgan bo'lsa, darhol tasdiqlanadi va omborga o'tadi
    if user.role in (roles.ADMIN, roles.FOREMAN):
        _apply_production_and_bom(db, t, qty, waste, user.id)
        if t.produced_qty >= t.planned_qty:
            t.status = "done"
            t.approved_by = user.id
            t.approved_at = m.get_server_now()
    else:
        # Ishchi kiritganda sifat tekshiruvi (OTK / Ish boshqaruvchi tasdig'i) kutiladi
        t.status = "pending_approval"
        db.add(m.Notification(
            title="OTK tekshiruvi: Ishlab chiqarish hisoboti",
            message=f"{user.full_name} tomonidan {qty} {t.product.unit} {t.product.name} topshirildi. Tasdiqlash kutilmoqda.",
            kind="production",
        ))

    db.commit()
    db.refresh(t)
    return to_out(t)


@router.post("/{task_id}/approve", response_model=TaskOut)
def approve_task(task_id: int, db: Session = Depends(get_db),
                 user: m.User = Depends(require_roles(roles.ADMIN, roles.FOREMAN))):
    """Ish boshqaruvchi / Admin sifat nazorati (OTK) dan o'tkazib topshiriqni tasdiqlaydi."""
    t = db.get(m.ProductionTask, task_id, with_for_update=True)
    if t is None:
        raise HTTPException(404, "Topshiriq topilmadi")
    if t.status == "done":
        raise HTTPException(400, "Ushbu topshiriq allaqachon yakunlangan")

    _apply_production_and_bom(db, t, t.produced_qty, t.waste_qty or Decimal(0), user.id)

    t.status = "done"
    t.approved_by = user.id
    t.approved_at = m.get_server_now()

    db.add(m.Notification(
        title="Ishlab chiqarish tasdiqlandi (OTK)",
        message=f"{t.worker.full_name} ning {t.produced_qty} {t.product.unit} {t.product.name} topshirig'i sifat nazoratidan o'tdi va omborga kirim qilindi.",
        kind="production",
    ))

    db.commit()
    db.refresh(t)
    return to_out(t)


@router.post("/{task_id}/reject", response_model=TaskOut)
def reject_task(task_id: int, data: TaskReject | None = None, db: Session = Depends(get_db),
                user: m.User = Depends(_prod)):
    """Ishchi topshiriqni qaytaradi (rad etadi). Topshiriq 'rejected' holatiga o'tadi."""
    t = db.get(m.ProductionTask, task_id, with_for_update=True)
    if t is None or (user.role == roles.WORKER and t.assigned_to != user.id):
        raise HTTPException(404, "Topshiriq topilmadi")
    if t.status == "done":
        raise HTTPException(400, "Yakunlangan topshiriqni qaytarib bo'lmaydi")
    if t.status == "rejected":
        raise HTTPException(400, "Topshiriq allaqachon qaytarilgan")

    t.status = "rejected"
    reason_txt = f": {data.reason}" if data and data.reason and data.reason.strip() else ""
    t.note = f"{t.note or ''} [Ishchi qaytardi{reason_txt}]".strip()

    prod_name = t.product.name if t.product else "Mahsulot"
    worker_name = t.worker.full_name if t.worker else "Ishchi"

    db.add(m.Notification(
        title="Topshiriq qaytarildi",
        message=f"{worker_name} #{t.id} topshiriqni ({prod_name}) qaytardi{reason_txt}.",
        kind="production",
    ))

    db.commit()
    db.refresh(t)
    return to_out(t)
