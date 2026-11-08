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
