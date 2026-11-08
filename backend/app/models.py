"""stone_erp jadvallari.

Ombor qoldig'i alohida ustunda saqlanmaydi: u StockMovement yig'indisidan hisoblanadi.
Savdo, xarid, ishlab chiqarish, tuzatish — hammasi bitta harakatlar tizimi orqali o'tadi.
"""
from datetime import datetime, timezone, timedelta
from decimal import Decimal

from sqlalchemy import Boolean, Integer, DateTime, ForeignKey, Index, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base

MONEY = Numeric(14, 2)
QTY = Numeric(14, 3)

# Ombor harakati turlari
MV_OPENING = "opening"
MV_PURCHASE = "purchase"
MV_SALE = "sale"
MV_PRODUCTION = "production"
MV_RAW = "raw_consumption"
MV_WASTE = "waste"
MV_RETURN = "return"
MV_ADJUST = "adjustment"


# O'zbekiston (Toshkent, UTC+5) vaqti - server qayerda bo'lishidan qat'iy nazar to'g'ri soatni saqlaydi
UZB_TZ = timezone(timedelta(hours=5))


def get_server_now() -> datetime:
    """O'zbekiston / Server mahalliy vaqti (UTC+5)"""
    return datetime.now(UZB_TZ).replace(tzinfo=None)


def utcnow() -> datetime:
    """Tarixiy moslik uchun: 5 soat orqada qolmasligi uchun O'zbekiston vaqtini qaytaradi"""
    return get_server_now()


class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    username: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(128))
    password_hash: Mapped[str] = mapped_column(String(256))
    role: Mapped[str] = mapped_column(String(16))
    salary: Mapped[Decimal] = mapped_column(MONEY, default=Decimal(0))
    salary_type: Mapped[str] = mapped_column(String(16), default="monthly")  # monthly, daily, hourly, trip
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    can_login: Mapped[bool] = mapped_column(Boolean, default=True)
    is_on_shift: Mapped[bool] = mapped_column(Boolean, default=True)
    is_archived: Mapped[bool] = mapped_column(Boolean, default=False)
    archived_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    archived_by_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Attendance(Base):
    __tablename__ = "attendance"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    date: Mapped[str] = mapped_column(String(10), index=True)  # YYYY-MM-DD
    check_in: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    check_out: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    worked_hours: Mapped[Decimal] = mapped_column(QTY, default=Decimal(0))
    status: Mapped[str] = mapped_column(String(16), default="present")  # present, late, absent, half_day
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    user: Mapped["User"] = relationship(lazy="joined")


class Product(Base):
    __tablename__ = "products"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128), index=True)
    category: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)  # Granit, Kerama granit, Kafel, Marmar ...
    sku: Mapped[str | None] = mapped_column(String(64), unique=True, nullable=True)
    qr_code: Mapped[str | None] = mapped_column(String(128), unique=True, nullable=True)
    unit: Mapped[str] = mapped_column(String(16))  # m2, dona, kg, m ...
    dona_m2: Mapped[Decimal | None] = mapped_column(QTY, nullable=True)  # faqat toshlar: 0.25
    thickness: Mapped[Decimal | None] = mapped_column(QTY, nullable=True)  # tosh qalinligi (sm, masalan: 2.0)
    tile_length: Mapped[Decimal | None] = mapped_column(QTY, nullable=True)  # kafel bo'yi (sm)
    tile_width: Mapped[Decimal | None] = mapped_column(QTY, nullable=True)  # kafel eni (sm)
    box_pieces: Mapped[int | None] = mapped_column(nullable=True)  # 1 pachkadagi donalar soni
    box_m2: Mapped[Decimal | None] = mapped_column(QTY, nullable=True)  # 1 pachka kvadrati (m2)
    min_stock: Mapped[Decimal | None] = mapped_column(QTY, default=Decimal(15), nullable=True)  # minimal ombor qoldig'i (kam qolganlik chegarasi)
    price: Mapped[Decimal] = mapped_column(MONEY, default=0)  # bazaviy birlik uchun sotuv narxi
    cost_price: Mapped[Decimal] = mapped_column(MONEY, default=0)  # o'rtacha tannarx
    sort: Mapped[str | None] = mapped_column(String(16), nullable=True)  # 1, 1.5, 2, 3, oliy
    has_sorts: Mapped[bool] = mapped_column(Boolean, default=False)  # 1, 1.5, 2 sortlari mavjudmi
    color: Mapped[str | None] = mapped_column(String(64), nullable=True)  # rangi: ko'k, oq, qora ...
    price_sort1: Mapped[Decimal | None] = mapped_column(MONEY, nullable=True)  # 1-sort narxi
    price_sort1_5: Mapped[Decimal | None] = mapped_column(MONEY, nullable=True)  # 1.5-sort narxi
    price_sort2: Mapped[Decimal | None] = mapped_column(MONEY, nullable=True)  # 2-sort narxi
    reserved_qty: Mapped[Decimal] = mapped_column(QTY, default=Decimal(0))  # buyurtmalar uchun band qilingan zaxira
    raw_material_id: Mapped[int | None] = mapped_column(ForeignKey("products.id"), nullable=True)  # xomashyo (blok/plita)
    waste_ratio: Mapped[Decimal | None] = mapped_column(QTY, default=Decimal("1.15"), nullable=True)  # sarf koeffitsiyenti
    cutting_rate: Mapped[Decimal | None] = mapped_column(MONEY, default=Decimal(0), nullable=True)  # 1 m2 ishbay haq
    image_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    deleted_by_name: Mapped[str | None] = mapped_column(String(128), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class StockMovement(Base):
    __tablename__ = "stock_movements"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"), index=True)
    qty_delta: Mapped[Decimal] = mapped_column(QTY)  # kirim +, chiqim -
    kind: Mapped[str] = mapped_column(String(16))
    ref_type: Mapped[str | None] = mapped_column(String(16), nullable=True)
    ref_id: Mapped[int | None] = mapped_column(nullable=True)
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)

    product: Mapped["Product"] = relationship()
    user: Mapped["User | None"] = relationship()


class Customer(Base):
    __tablename__ = "customers"
    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(128), index=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    passport: Mapped[str | None] = mapped_column(String(64), nullable=True)
    photo_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    sales: Mapped[list["Sale"]] = relationship(back_populates="customer")


class Sale(Base):
    __tablename__ = "sales"
    id: Mapped[int] = mapped_column(primary_key=True)
    customer_id: Mapped[int | None] = mapped_column(ForeignKey("customers.id"), nullable=True)
    cashier_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    total: Mapped[Decimal] = mapped_column(MONEY)  # savdo summasi
    total_cost: Mapped[Decimal] = mapped_column(MONEY)  # tannarx (sotilgan paytdagi)
    paid: Mapped[Decimal] = mapped_column(MONEY, default=0)  # to'lovlar yig'indisi (kesh)
    currency_rate: Mapped[Decimal | None] = mapped_column(MONEY, nullable=True, default=1)  # AQSH dollari kursi (1 USD necha so'm)
    paid_uzs: Mapped[Decimal | None] = mapped_column(MONEY, nullable=True, default=0)  # So'mda to'langan qism
    paid_usd: Mapped[Decimal | None] = mapped_column(MONEY, nullable=True, default=0)  # Dollarda to'langan qism
    status: Mapped[str] = mapped_column(String(20), default="completed")  # completed | order | cancelled
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)  # buyurtma izohi / muddat
    received_by_name: Mapped[str | None] = mapped_column(String(128), nullable=True)  # Mahsulotni qabul qilib olgan shaxs
    received_by_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)  # Qabul qiluvchi telefoni
    delivery_type: Mapped[str | None] = mapped_column(String(32), nullable=True)  # pickup | delivery
    receiver_doc_or_car: Mapped[str | None] = mapped_column(String(128), nullable=True)  # Mashina raqami yoki pasport
    fulfilled_by_name: Mapped[str | None] = mapped_column(String(128), nullable=True)  # Topshirgan mas'ul xodim
    fulfilled_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)  # Topshirilgan vaqt
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)

    items: Mapped[list["SaleItem"]] = relationship(cascade="all, delete-orphan")
    payments: Mapped[list["Payment"]] = relationship(cascade="all, delete-orphan")
    customer: Mapped["Customer | None"] = relationship(back_populates="sales")
    cashier: Mapped["User"] = relationship()

    @property
    def debt(self) -> Decimal:
        return self.total - self.paid


class SaleItem(Base):
    __tablename__ = "sale_items"
    id: Mapped[int] = mapped_column(primary_key=True)
    sale_id: Mapped[int] = mapped_column(ForeignKey("sales.id"), index=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"))
    product_name: Mapped[str] = mapped_column(String(128))
    quantity: Mapped[Decimal] = mapped_column(QTY)  # bazaviy birlikda
    unit_price: Mapped[Decimal] = mapped_column(MONEY)
    unit_cost: Mapped[Decimal] = mapped_column(MONEY)
    line_total: Mapped[Decimal] = mapped_column(MONEY)


class Payment(Base):
    """Kassaga tushgan pul. Savdo summasi bilan aralashtirilmaydi."""
    __tablename__ = "payments"
    id: Mapped[int] = mapped_column(primary_key=True)
    sale_id: Mapped[int] = mapped_column(ForeignKey("sales.id"), index=True)
    amount: Mapped[Decimal] = mapped_column(MONEY)
    method: Mapped[str] = mapped_column(String(16), default="cash")
    received_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)


class Expense(Base):
    __tablename__ = "expenses"
    id: Mapped[int] = mapped_column(primary_key=True)
    type: Mapped[str] = mapped_column(String(16), default="expense")  # expense | income
    category: Mapped[str] = mapped_column(String(64))  # salary, rent, utilities, other ...
    amount: Mapped[Decimal] = mapped_column(MONEY)
    payment_method: Mapped[str] = mapped_column(String(16), default="cash")  # cash | card | bank
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)

    creator: Mapped["User"] = relationship(foreign_keys=[created_by], lazy="select")


class ProductionTask(Base):
    __tablename__ = "production_tasks"
    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("products.id"))
    assigned_to: Mapped[int] = mapped_column(ForeignKey("users.id"), index=True)
    planned_qty: Mapped[Decimal] = mapped_column(QTY)
    produced_qty: Mapped[Decimal] = mapped_column(QTY, default=0)
    waste_qty: Mapped[Decimal] = mapped_column(QTY, default=0)  # yaroqsiz / chiqindi tosh
    status: Mapped[str] = mapped_column(String(24), default="open")  # open | pending_approval | done
    approved_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    note: Mapped[str | None] = mapped_column(String(255), nullable=True)
    order_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cut_length: Mapped[Decimal | None] = mapped_column(QTY, nullable=True)
    cut_width: Mapped[Decimal | None] = mapped_column(QTY, nullable=True)
    cut_pieces: Mapped[int | None] = mapped_column(Integer, nullable=True)
    cut_spec: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)

    product: Mapped["Product"] = relationship()
    worker: Mapped["User"] = relationship(foreign_keys=[assigned_to])


class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(primary_key=True)
    title: Mapped[str] = mapped_column(String(128))
    message: Mapped[str] = mapped_column(Text)
    kind: Mapped[str] = mapped_column(String(32), default="system")  # warning, payment, sale, production, system
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)


class Delivery(Base):
    __tablename__ = "deliveries"
    __table_args__ = (
        Index("ix_deliveries_driver_status", "driver_id", "status"),
        Index("ix_deliveries_sale_status", "sale_id", "status"),
    )
    id: Mapped[int] = mapped_column(primary_key=True)
    sale_id: Mapped[int | None] = mapped_column(ForeignKey("sales.id"), nullable=True)
    driver_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), nullable=True, index=True)
    vehicle_number: Mapped[str] = mapped_column(String(32), index=True)
    vehicle_model: Mapped[str] = mapped_column(String(64), default="Labo")
    driver_name: Mapped[str] = mapped_column(String(128))
    driver_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    recipient_name: Mapped[str] = mapped_column(String(128))
    recipient_phone: Mapped[str | None] = mapped_column(String(32), nullable=True)
    destination_address: Mapped[str | None] = mapped_column(Text, nullable=True)
    delivery_fee: Mapped[Decimal] = mapped_column(MONEY, default=0)
    fee_payer: Mapped[str] = mapped_column(String(32), default="customer")  # customer | store | included
    status: Mapped[str] = mapped_column(String(32), default="loading", index=True)  # loading | on_the_way | delivered | cancelled
    dispatch_time: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    delivered_time: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_deleted: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)

    items: Mapped[list["DeliveryItem"]] = relationship(cascade="all, delete-orphan", back_populates="delivery")
    sale: Mapped["Sale | None"] = relationship()
    driver: Mapped["User | None"] = relationship(foreign_keys=[driver_id])


class DeliveryItem(Base):
    __tablename__ = "delivery_items"
    id: Mapped[int] = mapped_column(primary_key=True)
    delivery_id: Mapped[int] = mapped_column(ForeignKey("deliveries.id", ondelete="CASCADE"), index=True)
    product_id: Mapped[int | None] = mapped_column(ForeignKey("products.id"), nullable=True)
    product_name: Mapped[str] = mapped_column(String(128))
    quantity: Mapped[Decimal] = mapped_column(QTY)
    unit: Mapped[str] = mapped_column(String(16), default="dona")

    delivery: Mapped["Delivery"] = relationship(back_populates="items")


class AppSetting(Base):
    __tablename__ = "app_settings"
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)



