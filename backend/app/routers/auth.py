from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from ..config import settings
from ..database import get_db
from ..deps import get_current_user
from ..models import User
from ..schemas import LoginIn, LoginOut, UserOut
from ..security import create_token, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=LoginOut)
def login(data: LoginIn, db: Session = Depends(get_db)):
    import traceback
    try:
        user = db.scalar(select(User).where(User.username == data.username.strip()))
        if (
            user is None
            or not user.is_active
            or not getattr(user, 'can_login', True)
            or getattr(user, 'is_archived', False)
            or not verify_password(data.password, user.password_hash)
        ):
            raise HTTPException(401, "Login yoki parol noto'g'ri (yoki xodim arxivlangan/faol emas)")
        # Ekranda rol tanlash mosligi tekshiriladi
        if data.role and data.role != user.role:
            raise HTTPException(403, "Bu akkaunt tanlangan rol uchun emas")
        token = create_token(str(user.id), settings.secret_key, settings.token_minutes)
        return LoginOut(access_token=token, user=UserOut.model_validate(user))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(500, f"LOGIN_ERROR: {e}\n{traceback.format_exc()}")


@router.get("/me", response_model=UserOut)
def me(user: User = Depends(get_current_user)):
    return user
