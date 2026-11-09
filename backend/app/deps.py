"""Autentifikatsiya va ruxsatlar. Rol HAR SAFAR bazadan olinadi — tokenga ishonilmaydi."""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from .config import settings
from .database import get_db
from .models import User
from .security import decode_token

_bearer = HTTPBearer(auto_error=False)


def get_current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: Session = Depends(get_db),
) -> User:
    unauth = HTTPException(status.HTTP_401_UNAUTHORIZED, "Kirish talab qilinadi")
    if creds is None:
        raise unauth
    sub = decode_token(creds.credentials, settings.secret_key)
    if sub is None:
        raise unauth
    user = db.get(User, int(sub))
    if user is None or not user.is_active:
        raise unauth
    return user


def require_roles(*allowed_roles: str):
    def checker(user: User = Depends(get_current_user)) -> User:
        if user.role != "master" and user.role not in allowed_roles:
            raise HTTPException(status.HTTP_403_FORBIDDEN, "Bu amal uchun ruxsat yo'q")
        return user

    return checker
