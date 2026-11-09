import json
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
from sqlalchemy import select

from ..database import get_db
from ..deps import get_current_user
from .. import models as m

router = APIRouter(prefix="/settings", tags=["settings"])

DEFAULT_COMPANY_INFO = {
    "name": "NTJ — NAMUNA TOSH JILO",
    "business_type": "Tabiiy tosh va granit markazi",
    "address": "Namuna MFY, Sokin ko‘cha, 11-uy",
    "phones": [
        "+998 (90) 588-66-99",
        "+998 (50) 588-66-99",
        "+998 (50) 700-06-06",
    ],
}


class CompanyInfoIn(BaseModel):
    name: str = "NTJ — NAMUNA TOSH JILO"
    address: str = "Namuna MFY, Sokin ko‘cha, 11-uy"
    business_type: str = "Tabiiy tosh va granit markazi"
    phones: list[str] = [
        "+998 (90) 588-66-99",
        "+998 (50) 588-66-99",
        "+998 (50) 700-06-06",
    ]


@router.get("/company")
def get_company_info(db: Session = Depends(get_db)):
    """Korxona nomi, manzili va aloqa telefonlarini olish."""
    setting = db.scalar(select(m.AppSetting).where(m.AppSetting.key == "company_info"))
    if not setting or not setting.value:
        return DEFAULT_COMPANY_INFO
    try:
        return json.loads(setting.value)
    except Exception:
        return DEFAULT_COMPANY_INFO


@router.post("/company")
def update_company_info(
    data: CompanyInfoIn,
    db: Session = Depends(get_db),
    user: m.User = Depends(get_current_user),
):
    """Korxona rekvizitlari va telefon raqamlarini yangilash."""
    setting = db.scalar(select(m.AppSetting).where(m.AppSetting.key == "company_info"))
    payload = {
        "name": data.name.strip(),
        "address": data.address.strip(),
        "business_type": data.business_type.strip(),
        "phones": [p.strip() for p in data.phones if p.strip()],
    }
    val = json.dumps(payload, ensure_ascii=False)
    if not setting:
        setting = m.AppSetting(key="company_info", value=val)
        db.add(setting)
    else:
        setting.value = val
    db.commit()
    return {"status": "ok", "company": payload}


DEFAULT_ROLE_PERMISSIONS = {
    "admin": {
        "dashboard": True,
        "pos": True,
        "orders": True,
        "deliveries": True,
        "sales": True,
        "customers": True,
        "debts": True,
        "purchases": True,
        "finance": True,
        "products": True,
        "stock": True,
        "production": True,
        "users": True,
        "view_cost_price": True,
        "delete_products": True,
        "give_discount": True,
    },
    "kassir": {
        "dashboard": False,
        "pos": True,
        "orders": True,
        "deliveries": True,
        "sales": True,
        "customers": True,
        "debts": True,
        "purchases": True,
        "finance": True,
        "products": True,
        "stock": False,
        "production": False,
        "users": False,
        "view_cost_price": False,
        "delete_products": False,
        "give_discount": True,
    },
    "ish_boshqaruvchi": {
        "dashboard": False,
        "pos": False,
        "orders": False,
        "deliveries": False,
        "sales": False,
        "customers": False,
        "debts": False,
        "purchases": False,
        "finance": False,
        "products": False,
        "stock": True,
        "production": True,
        "users": False,
        "view_cost_price": False,
        "delete_products": False,
        "give_discount": False,
    },
    "haydovchi": {
        "dashboard": False,
        "pos": False,
        "orders": True,
        "deliveries": True,
        "sales": False,
        "customers": False,
        "debts": False,
        "purchases": False,
        "finance": False,
        "products": False,
        "stock": False,
        "production": False,
        "users": False,
        "view_cost_price": False,
        "delete_products": False,
        "give_discount": False,
    },
    "ishchi": {
        "dashboard": False,
        "pos": False,
        "orders": False,
        "deliveries": False,
        "sales": False,
        "customers": False,
        "debts": False,
        "purchases": False,
        "finance": False,
        "products": False,
        "stock": False,
        "production": True,
        "users": False,
        "view_cost_price": False,
        "delete_products": False,
        "give_discount": False,
    },
}


@router.get("/permissions")
def get_role_permissions(db: Session = Depends(get_db)):
    """Barcha rollar uchun ruxsatlar matritsasini olish."""
    setting = db.scalar(select(m.AppSetting).where(m.AppSetting.key == "role_permissions"))
    if not setting or not setting.value:
        return DEFAULT_ROLE_PERMISSIONS
    try:
        data = json.loads(setting.value)
        merged = {k: dict(v) for k, v in DEFAULT_ROLE_PERMISSIONS.items()}
        for r, perms in data.items():
            if r in merged:
                merged[r].update(perms)
            else:
                merged[r] = perms
        return merged
    except Exception:
        return DEFAULT_ROLE_PERMISSIONS


class PermissionsIn(BaseModel):
    permissions: dict


@router.post("/permissions")
def update_role_permissions(
    data: PermissionsIn,
    db: Session = Depends(get_db),
    user: m.User = Depends(get_current_user),
):
    """Rollar ruxsatlarini yangilash (faqat Master va Admin)."""
    setting = db.scalar(select(m.AppSetting).where(m.AppSetting.key == "role_permissions"))
    val = json.dumps(data.permissions, ensure_ascii=False)
    if not setting:
        setting = m.AppSetting(key="role_permissions", value=val)
        db.add(setting)
    else:
        setting.value = val
    db.commit()
    return {"status": "ok", "permissions": data.permissions}
