from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .. import roles
from ..database import get_db
from ..deps import get_current_user, require_roles
from ..models import User
from ..schemas import UserCreate, UserOut, UserShiftUpdate, UserUpdate
from ..security import hash_password

router = APIRouter(prefix="/users", tags=["users"])


@router.get("", response_model=list[UserOut])
def list_users(role: str | None = None, db: Session = Depends(get_db),
               user: User = Depends(get_current_user)):
    if user.role not in (roles.ADMIN, roles.FOREMAN) and role != roles.WORKER:
        raise HTTPException(403, "Bu amal uchun ruxsat yo'q")
    q = select(User).order_by(User.id)
    if role:
        q = q.where(User.role == role)
    elif user.role not in (roles.ADMIN, roles.FOREMAN):
        q = q.where(User.role == roles.WORKER)
    return db.scalars(q).all()


@router.post("", response_model=UserOut, status_code=201)
def create_user(data: UserCreate, db: Session = Depends(get_db),
                _: User = Depends(require_roles(roles.ADMIN))):
    import uuid
    if data.role == roles.FOREMAN:
        existing = db.scalar(select(User).where(User.role == roles.FOREMAN, User.is_active == True))
        if existing:
            raise HTTPException(400, "Tizimda faqat 1 ta Ish boshqaruvchi akkaunti bo'lishi mumkin!")

    if data.can_login:
        if not data.username or len(data.username.strip()) < 3:
            raise HTTPException(400, "Dasturga kiruvchi xodim uchun login kiritilishi shart (kamida 3 belgi)")
        if not data.password or len(data.password) < 6:
            raise HTTPException(400, "Dasturga kiruvchi xodim uchun parol kiritilishi shart (kamida 6 belgi)")
        if db.scalar(select(User).where(User.username == data.username.strip())):
            raise HTTPException(409, "Bu login band")
        username = data.username.strip()
        pwd_hash = hash_password(data.password)
    else:
        username = data.username.strip() if (data.username and data.username.strip()) else f"worker_{uuid.uuid4().hex[:8]}"
        pwd_hash = "NO_LOGIN"

    u = User(
        username=username,
        full_name=data.full_name,
        role=data.role,
        salary=data.salary,
        salary_type=data.salary_type,
        can_login=data.can_login,
        password_hash=pwd_hash,
    )
    db.add(u)
    db.commit()
    return u


@router.patch("/{user_id}", response_model=UserOut)
def update_user(user_id: int, data: UserUpdate, db: Session = Depends(get_db),
                admin: User = Depends(require_roles(roles.ADMIN))):
    u = db.get(User, user_id)
    if u is None:
        raise HTTPException(404, "Foydalanuvchi topilmadi")
    if u.id == admin.id and (data.is_active is False or (data.role and data.role != roles.ADMIN)):
        raise HTTPException(400, "O'zingizni o'chira yoki rolingizni pasaytira olmaysiz")
    if data.full_name is not None:
        u.full_name = data.full_name
    if data.username is not None and data.username.strip():
        u.username = data.username.strip()
    if data.role is not None:
        if data.role == roles.FOREMAN and u.role != roles.FOREMAN:
            existing = db.scalar(select(User).where(User.role == roles.FOREMAN, User.is_active == True, User.id != u.id))
            if existing:
                raise HTTPException(400, "Tizimda faqat 1 ta Ish boshqaruvchi akkaunti bo'lishi mumkin!")
        u.role = data.role
    if data.can_login is not None:
        u.can_login = data.can_login
    if data.salary is not None:
        u.salary = data.salary
    if data.salary_type is not None:
        u.salary_type = data.salary_type
    if data.is_active is not None:
        u.is_active = data.is_active
    if data.is_on_shift is not None:
        u.is_on_shift = data.is_on_shift
    if data.password:
        u.password_hash = hash_password(data.password)
    db.commit()
    return u


@router.patch("/{user_id}/shift", response_model=UserOut)
def toggle_user_shift(
    user_id: int,
    data: UserShiftUpdate | None = None,
    on_shift: bool | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    u = db.get(User, user_id)
    if u is None:
        raise HTTPException(404, "Foydalanuvchi topilmadi")
    if current_user.role != roles.ADMIN and current_user.id != user_id:
        raise HTTPException(403, "O'zingizdan boshqa xodim smenasini o'zgartira olmaysiz")

    val = on_shift
    if data is not None and data.is_on_shift is not None:
        val = data.is_on_shift
    if val is None:
        val = not u.is_on_shift

    u.is_on_shift = val
    db.commit()
    db.refresh(u)
    return u


@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(roles.ADMIN)),
):
    if user_id == admin.id:
        raise HTTPException(400, "O'zingizni o'chira olmaysiz")
    u = db.get(User, user_id)
    if u is None:
        raise HTTPException(404, "Foydalanuvchi topilmadi")

    from ..models import Attendance, StockMovement, ProductionTask, Delivery
    # Clean up attendance
    db.query(Attendance).filter(Attendance.user_id == user_id).delete(synchronize_session=False)
    # Detach from stock movements
    db.query(StockMovement).filter(StockMovement.created_by == user_id).update({StockMovement.created_by: None}, synchronize_session=False)
    # Detach from deliveries
    db.query(Delivery).filter(Delivery.driver_id == user_id).update({Delivery.driver_id: None}, synchronize_session=False)

    db.delete(u)
    db.commit()
    return {"status": "ok", "message": f"{u.full_name} ({u.username}) muvaffaqiyatli o'chirildi"}


@router.post("/reset-workers")
def reset_workers(
    delete_all_non_admin: bool = False,
    db: Session = Depends(get_db),
    admin: User = Depends(require_roles(roles.ADMIN)),
):
    """Ishchilarni (yoki barcha admin bo'lmagan xodimlarni) o'chirish."""
    from sqlalchemy import text
    from ..models import Attendance, StockMovement, Delivery

    try:
        bind = db.get_bind()
        dialect = bind.dialect.name
        if dialect == "sqlite":
            db.execute(text("PRAGMA foreign_keys = OFF;"))
        elif dialect == "mysql":
            db.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))

        # Null out references
        db.query(StockMovement).update({StockMovement.created_by: None}, synchronize_session=False)
        db.query(Delivery).update({Delivery.driver_id: None}, synchronize_session=False)

        if delete_all_non_admin:
            db.query(Attendance).delete(synchronize_session=False)
            to_delete = db.query(User).filter(User.id != admin.id).all()
        else:
            # Delete role == 'ishchi' + any imported workers
            workers = db.query(User).filter((User.role == roles.WORKER) | (User.username.in_(["zoyirjon"]))).all()
            w_ids = [w.id for w in workers]
            if w_ids:
                db.query(Attendance).filter(Attendance.user_id.in_(w_ids)).delete(synchronize_session=False)
            to_delete = workers

        deleted_names = [f"{u.full_name} ({u.role})" for u in to_delete]
        for u in to_delete:
            db.delete(u)

        if dialect == "sqlite":
            db.execute(text("PRAGMA foreign_keys = ON;"))
        elif dialect == "mysql":
            db.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))

        db.commit()
        return {
            "status": "ok",
            "deleted_count": len(to_delete),
            "deleted_users": deleted_names,
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Ishchilarni o'chirishda xatolik: {e}")
