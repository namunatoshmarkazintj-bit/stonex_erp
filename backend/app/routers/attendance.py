from datetime import datetime, timezone, time as dt_time
from decimal import Decimal
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import roles
from ..database import get_db
from ..deps import get_current_user, require_roles
from ..models import Attendance, User, Delivery, Expense
from ..schemas import (
    AttendanceBulkCheckIn,
    AttendanceCheckIn,
    AttendanceCheckOut,
    AttendanceOut,
    AttendanceRecordIn,
    SalaryReportItem,
)

router = APIRouter(prefix="/attendance", tags=["attendance"])

# Standart smena va ish vaqti parametrlari
_shift_config = {
    "start_time": "09:00",
    "end_time": "18:00",
    "daily_hours": 8,
    "grace_minutes": 10,
    "minute_penalty": True,
    "overtime_enabled": True,
    "auto_checkout": True,
}

# To'langan oyliklar to'plami va summalari (in-memory + expense sinxronizatsiyasi)
_paid_salaries: dict[str, Decimal] = {}  # "user_id:YYYY-MM" -> Decimal(amount)
_manual_bonuses: dict[str, Decimal] = {}  # "user_id:YYYY-MM" -> Decimal(amount)


def _today_str() -> str:
    return datetime.now().strftime("%Y-%m-%d")


def _calc_hours(check_in: datetime | None, check_out: datetime | None) -> Decimal:
    if not check_in or not check_out:
        return Decimal(0)
    cin = check_in.replace(tzinfo=None) if check_in.tzinfo else check_in
    cout = check_out.replace(tzinfo=None) if check_out.tzinfo else check_out
    diff = (cout - cin).total_seconds()
    hours = max(0.0, diff / 3600.0)
    return Decimal(str(round(hours, 2)))


def _apply_auto_checkout(db: Session, records: list[Attendance]) -> None:
    """Ketdi qilinmagan bo'lsa, ish vaqti tugaganidan so'ng (18:00) avtomatik ketdi qiladi."""
    if not _shift_config.get("auto_checkout", True):
        return

    now = datetime.now()
    today = _today_str()
    end_h, end_m = [int(x) for x in _shift_config["end_time"].split(":")]
    changed = False

    for r in records:
        if r.check_in and not r.check_out:
            rec_date = datetime.strptime(r.date, "%Y-%m-%d").date()
            shift_end = datetime.combine(rec_date, dt_time(end_h, end_m))
            # Agar o'tgan kun bo'lsa yoki bugun 18:00 dan o'tgan bo'lsa
            if r.date < today or (r.date == today and now >= shift_end):
                r.check_out = shift_end
                r.worked_hours = _calc_hours(r.check_in, shift_end)
                auto_tag = f"Avtomatik ketdi ({_shift_config['end_time']})"
                if not r.note:
                    r.note = auto_tag
                elif auto_tag not in r.note:
                    r.note = f"{r.note} · {auto_tag}"
                changed = True

    if changed:
        try:
            db.commit()
        except Exception:
            db.rollback()


@router.get("", response_model=list[AttendanceOut])
def list_attendance(
    date: str | None = None,
    month: str | None = None,
    user_id: int | None = None,
    db: Session = Depends(get_db),
    user: User = Depends(get_current_user),
):
    q = select(Attendance).order_by(Attendance.date.desc(), Attendance.id.desc())
    if date:
        q = q.where(Attendance.date == date)
    elif month:
        q = q.where(Attendance.date.startswith(month))

    if user_id:
        if user.role != roles.ADMIN and user.id != user_id:
            raise HTTPException(403, "Ruxsat berilmagan")
        q = q.where(Attendance.user_id == user_id)
    elif user.role != roles.ADMIN:
        q = q.where(Attendance.user_id == user.id)

    records = db.scalars(q).all()
    _apply_auto_checkout(db, records)
    out = []
    for r in records:
        u_name = r.user.full_name if r.user else None
        out.append(
            AttendanceOut(
                id=r.id,
                user_id=r.user_id,
                user_name=u_name,
                date=r.date,
                check_in=r.check_in,
                check_out=r.check_out,
                worked_hours=r.worked_hours,
                status=r.status,
                note=r.note,
            )
        )
    return out


@router.post("/check-in", response_model=AttendanceOut)
def check_in(
    data: AttendanceCheckIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != roles.ADMIN and current_user.id != data.user_id:
        raise HTTPException(403, "Boshqa xodim nomidan kirish belgilab bo'lmaydi")

    u = db.get(User, data.user_id)
    if not u or not u.is_active:
        raise HTTPException(404, "Xodim topilmadi")

    date_str = data.date or _today_str()
    record = db.scalar(
        select(Attendance).where(
            Attendance.user_id == data.user_id, Attendance.date == date_str
        )
    )

    now = data.check_in or datetime.now()
    # 09:15 dan kech kelsa late deb belgilaymiz
    is_late = now.hour > 9 or (now.hour == 9 and now.minute > 15)

    if record:
        record.check_in = now
        if record.check_out:
            record.worked_hours = _calc_hours(now, record.check_out)
        if is_late:
            record.status = "late"
        if data.note:
            record.note = data.note
    else:
        record = Attendance(
            user_id=data.user_id,
            date=date_str,
            check_in=now,
            status="late" if is_late else "present",
            note=data.note,
        )
        db.add(record)

    db.commit()
    db.refresh(record)
    return AttendanceOut(
        id=record.id,
        user_id=record.user_id,
        user_name=u.full_name,
        date=record.date,
        check_in=record.check_in,
        check_out=record.check_out,
        worked_hours=record.worked_hours,
        status=record.status,
        note=record.note,
    )


@router.post("/check-out", response_model=AttendanceOut)
def check_out(
    data: AttendanceCheckOut,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != roles.ADMIN and current_user.id != data.user_id:
        raise HTTPException(403, "Ruxsat berilmagan")

    u = db.get(User, data.user_id)
    if not u:
        raise HTTPException(404, "Xodim topilmadi")

    date_str = data.date or _today_str()
    record = db.scalar(
        select(Attendance).where(
            Attendance.user_id == data.user_id, Attendance.date == date_str
        )
    )

    now = data.check_out or datetime.now()
    if not record:
        record = Attendance(
            user_id=data.user_id,
            date=date_str,
            check_out=now,
            status="present",
            note=data.note,
        )
        db.add(record)
    else:
        record.check_out = now
        record.worked_hours = _calc_hours(record.check_in, now)
        if data.note:
            record.note = data.note

    db.commit()
    db.refresh(record)
    return AttendanceOut(
        id=record.id,
        user_id=record.user_id,
        user_name=u.full_name,
        date=record.date,
        check_in=record.check_in,
        check_out=record.check_out,
        worked_hours=record.worked_hours,
        status=record.status,
        note=record.note,
    )


@router.post("/bulk-check-in", response_model=list[AttendanceOut])
def bulk_check_in(
    data: AttendanceBulkCheckIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != roles.ADMIN:
        raise HTTPException(403, "Faqat admin barcha xodimlarni bir vaqtda keldi qila oladi")

    date_str = data.date or _today_str()
    now = data.check_in or datetime.now()
    if now.tzinfo:
        now = now.replace(tzinfo=None)
    is_late = now.hour > 9 or (now.hour == 9 and now.minute > 15)

    results = []
    for uid in data.user_ids:
        u = db.get(User, uid)
        if not u or not u.is_active:
            continue
        record = db.scalar(
            select(Attendance).where(
                Attendance.user_id == uid, Attendance.date == date_str
            )
        )
        if record:
            if not record.check_in:
                record.check_in = now
                record.status = "late" if is_late else "present"
            if record.check_out:
                record.worked_hours = _calc_hours(record.check_in, record.check_out)
        else:
            record = Attendance(
                user_id=uid,
                date=date_str,
                check_in=now,
                worked_hours=Decimal(0),
                status="late" if is_late else "present",
            )
            db.add(record)
        results.append((record, u.full_name))

    db.commit()
    out = []
    for rec, uname in results:
        db.refresh(rec)
        out.append(
            AttendanceOut(
                id=rec.id,
                user_id=rec.user_id,
                user_name=uname,
                date=rec.date,
                check_in=rec.check_in,
                check_out=rec.check_out,
                worked_hours=rec.worked_hours,
                status=rec.status,
                note=rec.note,
            )
        )
    return out


@router.post("/record", response_model=AttendanceOut)
def record_attendance(
    data: AttendanceRecordIn,
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(roles.ADMIN)),
):
    u = db.get(User, data.user_id)
    if not u:
        raise HTTPException(404, "Xodim topilmadi")

    if data.id:
        rec = db.get(Attendance, data.id)
        if not rec:
            raise HTTPException(404, "Davomat yozuvi topilmadi")
    else:
        rec = db.scalar(
            select(Attendance).where(
                Attendance.user_id == data.user_id, Attendance.date == data.date
            )
        )
        if not rec:
            rec = Attendance(user_id=data.user_id, date=data.date)
            db.add(rec)

    rec.check_in = data.check_in
    rec.check_out = data.check_out
    rec.status = data.status
    rec.note = data.note
    if data.worked_hours > 0:
        rec.worked_hours = data.worked_hours
    elif data.check_in and data.check_out:
        rec.worked_hours = _calc_hours(data.check_in, data.check_out)

    db.commit()
    db.refresh(rec)
    return AttendanceOut(
        id=rec.id,
        user_id=rec.user_id,
        user_name=u.full_name,
        date=rec.date,
        check_in=rec.check_in,
        check_out=rec.check_out,
        worked_hours=rec.worked_hours,
        status=rec.status,
        note=rec.note,
    )


class ShiftConfigIn(BaseModel):
    start_time: str | None = None  # HH:MM
    end_time: str | None = None    # HH:MM
    daily_hours: int | None = None
    grace_minutes: int | None = None
    minute_penalty: bool | None = None
    overtime_enabled: bool | None = None
    auto_checkout: bool | None = None


class SalaryPaymentIn(BaseModel):
    user_id: int
    month: str  # YYYY-MM
    amount: Decimal
    note: str | None = None


class BonusIn(BaseModel):
    user_id: int
    month: str  # YYYY-MM
    amount: Decimal
    reason: str | None = None


@router.post("/add-bonus")
def add_bonus(
    data: BonusIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(roles.ADMIN, roles.CASHIER)),
):
    """Xodimga mukofot (bonus / premiya) qo'shish."""
    u = db.get(User, data.user_id)
    if not u:
        raise HTTPException(404, "Xodim topilmadi")

    key = f"{data.user_id}:{data.month}"
    _manual_bonuses[key] = _manual_bonuses.get(key, Decimal(0)) + data.amount

    # Chiqimlar jurnaliga qayd etish
    exp = Expense(
        type="expense",
        category="Mukofot / Bonus",
        amount=data.amount,
        payment_method="cash",
        note=f"Mukofot: {u.full_name} ({data.month})" + (f" — {data.reason}" if data.reason else ""),
        created_by=current_user.id,
    )
    db.add(exp)
    db.commit()

    return {"ok": True, "user_id": data.user_id, "month": data.month, "amount": float(data.amount)}


@router.get("/shift-config")
def get_shift_config(_: User = Depends(get_current_user)):
    """Ish vaqti va davomat qoidalarini olish."""
    return _shift_config


@router.post("/shift-config")
def update_shift_config(
    data: ShiftConfigIn,
    _: User = Depends(require_roles(roles.ADMIN)),
):
    """Ish vaqti va davomat qoidalarini sozlash (faqat admin)."""
    if data.start_time is not None:
        _shift_config["start_time"] = data.start_time
    if data.end_time is not None:
        _shift_config["end_time"] = data.end_time
    if data.daily_hours is not None:
        _shift_config["daily_hours"] = data.daily_hours
    if data.grace_minutes is not None:
        _shift_config["grace_minutes"] = data.grace_minutes
    if data.minute_penalty is not None:
        _shift_config["minute_penalty"] = data.minute_penalty
    if data.overtime_enabled is not None:
        _shift_config["overtime_enabled"] = data.overtime_enabled
    if data.auto_checkout is not None:
        _shift_config["auto_checkout"] = data.auto_checkout
    return _shift_config


@router.post("/pay-salary")
def pay_salary(
    data: SalaryPaymentIn,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_roles(roles.ADMIN, roles.CASHIER)),
):
    """Xodimga maosh to'langanini belgilash va chiqimga yozish."""
    u = db.get(User, data.user_id)
    if not u:
        raise HTTPException(404, "Xodim topilmadi")

    key = f"{data.user_id}:{data.month}"
    _paid_salaries[key] = _paid_salaries.get(key, Decimal(0)) + data.amount

    # Chiqimlar jurnaliga qayd etish
    exp = Expense(
        type="expense",
        category="Ish haqi / Avans",
        amount=data.amount,
        payment_method="cash",
        note=data.note or f"Oylik / Avans to‘lovi: {u.full_name} ({data.month})",
        created_by=current_user.id,
    )
    db.add(exp)
    db.commit()

    return {"ok": True, "user_id": data.user_id, "month": data.month, "amount": float(data.amount)}


@router.get("/salary-report", response_model=list[SalaryReportItem])
def get_salary_report(
    month: str = Query(..., description="YYYY-MM formati"),
    total_working_days: int = Query(26, ge=1, le=31),
    db: Session = Depends(get_db),
    _: User = Depends(require_roles(roles.ADMIN, roles.HEAD)),
):
    # Xo'jayinga (admin) oylik to'lanmaydi - ro'yxatdan chiqariladi!
    users = db.scalars(
        select(User).where(User.is_active == True, User.role != roles.ADMIN).order_by(User.id)
    ).all()

    attendances = db.scalars(
        select(Attendance).where(Attendance.date.startswith(month))
    ).all()
    _apply_auto_checkout(db, attendances)

    user_att: dict[int, list[Attendance]] = {}
    for a in attendances:
        user_att.setdefault(a.user_id, []).append(a)

    start_h, start_m = [int(x) for x in _shift_config["start_time"].split(":")]
    grace_m = _shift_config.get("grace_minutes", 10)
    standard_daily_h = Decimal(str(_shift_config.get("daily_hours", 8)))

    report: list[SalaryReportItem] = []
    for u in users:
        atts = user_att.get(u.id, [])
        worked_atts = [a for a in atts if a.status != "absent"]
        days_worked = len(worked_atts)
        hours_worked = sum((a.worked_hours for a in worked_atts), Decimal(0))
        days_late = sum(1 for a in atts if a.status == "late")

        base_sal = u.salary or Decimal(0)
        sal_type = u.salary_type or "monthly"

        # Oylik to'langanligini tekshirish (jami to'langan summa)
        pay_key = f"{u.id}:{month}"
        paid_expenses = db.scalars(
            select(Expense).where(
                Expense.type == "expense",
                Expense.category.ilike("%ish haqi%"),
                Expense.note.ilike(f"%{u.full_name}%({month})%"),
            )
        ).all()
        expense_paid = sum((e.amount for e in paid_expenses), Decimal(0))
        mem_paid = _paid_salaries.get(pay_key, Decimal(0))
        paid_amount = max(expense_paid, mem_paid)

        # Mukofotlar (Bonus / Premiya)
        mem_bonus = _manual_bonuses.get(pay_key, Decimal(0))
        bonus_expenses = db.scalars(
            select(Expense).where(
                Expense.type == "expense",
                Expense.category.ilike("%mukofot%"),
                Expense.note.ilike(f"%{u.full_name}%({month})%"),
            )
        ).all()
        expense_bonus = sum((e.amount for e in bonus_expenses), Decimal(0))
        total_manual_bonus = max(mem_bonus, expense_bonus)

        # Stavka bo'yicha stavka koeffitsientlari
        if total_working_days > 0:
            day_rate = base_sal / Decimal(total_working_days)
        else:
            day_rate = Decimal(0)
        hourly_rate = (day_rate / standard_daily_h) if standard_daily_h > 0 else Decimal(0)
        minute_rate = hourly_rate / Decimal(60)

        # Minutbay kechikish jarimalari hisobi
        total_late_minutes = 0
        total_overtime_hours = Decimal(0)

        for a in worked_atts:
            if a.check_in:
                cin = a.check_in.replace(tzinfo=None) if a.check_in.tzinfo else a.check_in
                expected_start = datetime.combine(cin.date(), dt_time(start_h, start_m))
                diff_seconds = (cin - expected_start).total_seconds()
                if diff_seconds > (grace_m * 60):
                    total_late_minutes += int(diff_seconds // 60)

            # Ko'p ishlasa ish haqi qo'shiladi (Overtime)
            if _shift_config.get("overtime_enabled", True) and a.worked_hours > standard_daily_h:
                total_overtime_hours += (a.worked_hours - standard_daily_h)

        # Haydovchi reysbay hisobi
        if sal_type == "trip" or u.role == roles.DRIVER:
            completed_deliveries = db.scalars(
                select(Delivery).where(
                    Delivery.status == "delivered",
                    Delivery.driver_name.ilike(f"%{u.full_name}%"),
                )
            ).all()
            month_deliveries = [
                d for d in completed_deliveries
                if (d.delivered_time and d.delivered_time.strftime("%Y-%m") == month)
                or (not d.delivered_time and d.created_at and d.created_at.strftime("%Y-%m") == month)
            ]
            if base_sal > 0:
                calc_sal = base_sal * Decimal(len(month_deliveries))
            else:
                calc_sal = sum((d.delivery_fee or Decimal(0) for d in month_deliveries), Decimal(0))
            days_worked = len(month_deliveries) if month_deliveries else days_worked
            deduction = Decimal(0)
            bonus = total_manual_bonus
            net = calc_sal + bonus
        elif sal_type == "daily":
            calc_sal = base_sal * Decimal(days_worked)
            deduction = Decimal(str(round(float(total_late_minutes * float(minute_rate)), 2))) if _shift_config.get("minute_penalty", True) else Decimal(str(round(float(base_sal * Decimal(0.1) * Decimal(days_late)), 2)))
            bonus = Decimal(str(round(float(total_overtime_hours * hourly_rate), 2))) + total_manual_bonus
            net = max(Decimal(0), calc_sal + bonus - deduction)
        elif sal_type == "hourly":
            calc_sal = base_sal * hours_worked
            deduction = Decimal(str(round(float(total_late_minutes * float(minute_rate)), 2)))
            bonus = total_manual_bonus
            net = max(Decimal(0), calc_sal + bonus - deduction)
        else:  # monthly
            calc_sal = Decimal(str(round(float(day_rate * Decimal(days_worked)), 2)))
            if _shift_config.get("minute_penalty", True) and total_late_minutes > 0:
                deduction = Decimal(str(round(float(Decimal(total_late_minutes) * minute_rate), 2)))
            else:
                deduction = Decimal(str(round(float(day_rate * Decimal(0.1) * Decimal(days_late)), 2)))
            bonus = Decimal(str(round(float(total_overtime_hours * hourly_rate), 2))) + total_manual_bonus
            net = max(Decimal(0), calc_sal + bonus - deduction)

        remaining_salary = max(Decimal(0), net - paid_amount)
        is_paid = (paid_amount >= net and net > 0) or (paid_amount > 0 and remaining_salary == 0)

        report.append(
            SalaryReportItem(
                user_id=u.id,
                full_name=u.full_name,
                role=u.role,
                base_salary=base_sal,
                salary_type=sal_type,
                days_worked=days_worked,
                hours_worked=hours_worked,
                days_late=days_late,
                calculated_salary=calc_sal,
                bonus=bonus,
                deduction=deduction,
                net_salary=net,
                paid_amount=paid_amount,
                remaining_salary=remaining_salary,
                is_paid=is_paid,
            )
        )

    return report

