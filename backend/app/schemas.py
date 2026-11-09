from datetime import datetime
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# ---------- auth / users ----------
class LoginIn(BaseModel):
    username: str
    password: str
    role: str | None = None  # kirish ekranida tanlangan rol; backend haqiqiy rolni tekshiradi


class UserOut(ORM):
    id: int
    username: str
    full_name: str
    role: str
    salary: Decimal = Decimal(0)
    salary_type: str = "monthly"
    is_active: bool
    can_login: bool = True
    is_on_shift: bool = True
    is_archived: bool = False
    archived_at: datetime | None = None
    archived_by_name: str | None = None


class LoginOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut


class UserCreate(BaseModel):
    username: str | None = Field(default=None, max_length=64)
    full_name: str = Field(min_length=1, max_length=128)
    password: str | None = Field(default=None, max_length=128)
    role: Literal["master", "admin", "kassir", "ishchi", "haydovchi", "ish_boshqaruvchi"]
    can_login: bool = True
    salary: Decimal = Field(default=Decimal(0), ge=0)
    salary_type: Literal["monthly", "daily", "hourly", "trip"] = "monthly"


class UserUpdate(BaseModel):
    full_name: str | None = None
    username: str | None = None
    password: str | None = Field(default=None, max_length=128)
    role: Literal["master", "admin", "kassir", "ishchi", "haydovchi", "ish_boshqaruvchi"] | None = None
    can_login: bool | None = None
    salary: Decimal | None = Field(default=None, ge=0)
    salary_type: Literal["monthly", "daily", "hourly", "trip"] | None = None
    is_active: bool | None = None
    is_on_shift: bool | None = None


class UserShiftUpdate(BaseModel):
    is_on_shift: bool = True


# ---------- attendance & payroll ----------
class AttendanceCheckIn(BaseModel):
    user_id: int
    date: str | None = None  # YYYY-MM-DD
    check_in: datetime | None = None
    note: str | None = None


class AttendanceCheckOut(BaseModel):
    user_id: int
    date: str | None = None  # YYYY-MM-DD
    check_out: datetime | None = None
    note: str | None = None


class AttendanceBulkCheckIn(BaseModel):
    user_ids: list[int]
    date: str | None = None  # YYYY-MM-DD
    check_in: datetime | None = None


class AttendanceRecordIn(BaseModel):
    id: int | None = None
    user_id: int
    date: str  # YYYY-MM-DD
    check_in: datetime | None = None
    check_out: datetime | None = None
    worked_hours: Decimal = Decimal(0)
    status: Literal["present", "late", "absent", "half_day"] = "present"
    note: str | None = None


class AttendanceOut(ORM):
    id: int
    user_id: int
    user_name: str | None = None
    date: str
    check_in: datetime | None = None
    check_out: datetime | None = None
    worked_hours: Decimal = Decimal(0)
    status: str
    note: str | None = None


class SalaryReportItem(BaseModel):
    user_id: int
    full_name: str
    role: str
    base_salary: Decimal
    salary_type: str
    days_worked: int
    hours_worked: Decimal
    days_late: int
    calculated_salary: Decimal
    bonus: Decimal = Decimal(0)
    deduction: Decimal = Decimal(0)
    net_salary: Decimal
    paid_amount: Decimal = Decimal(0)
    remaining_salary: Decimal = Decimal(0)
    is_paid: bool = False


# ---------- products ----------
class ProductIn(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    category: str | None = None
    sku: str | None = None
    qr_code: str | None = None
    unit: str = Field(min_length=1, max_length=16)
    dona_m2: Decimal | None = Field(default=None, gt=0)
    thickness: Decimal | None = Field(default=None, gt=0)
    tile_length: Decimal | None = Field(default=None, gt=0)
    tile_width: Decimal | None = Field(default=None, gt=0)
    box_pieces: int | None = Field(default=None, gt=0)
    box_m2: Decimal | None = Field(default=None, gt=0)
    min_stock: Decimal | None = Field(default=Decimal(15), ge=0)
    price: Decimal = Field(ge=0)
    cost_price: Decimal = Field(default=Decimal(0), ge=0)
    sort: str | None = None
    has_sorts: bool = False
    color: str | None = None
    price_sort1: Decimal | None = Field(default=None, ge=0)
    price_sort1_5: Decimal | None = Field(default=None, ge=0)
    price_sort2: Decimal | None = Field(default=None, ge=0)
    raw_material_id: int | None = None
    waste_ratio: Decimal | None = Field(default=Decimal("1.15"), ge=1)
    cutting_rate: Decimal | None = Field(default=Decimal(0), ge=0)
    image_url: str | None = None
    initial_stock: Decimal = Field(default=Decimal(0), ge=0)  # faqat yaratishda


class ProductUpdate(BaseModel):
    name: str | None = None
    category: str | None = None
    sku: str | None = None
    qr_code: str | None = None
    unit: str | None = None
    dona_m2: Decimal | None = Field(default=None, gt=0)
    thickness: Decimal | None = Field(default=None, gt=0)
    tile_length: Decimal | None = Field(default=None, gt=0)
    tile_width: Decimal | None = Field(default=None, gt=0)
    box_pieces: int | None = Field(default=None, gt=0)
    box_m2: Decimal | None = Field(default=None, gt=0)
    min_stock: Decimal | None = Field(default=None, ge=0)
    price: Decimal | None = Field(default=None, ge=0)
    cost_price: Decimal | None = Field(default=None, ge=0)
    sort: str | None = None
    has_sorts: bool | None = None
    color: str | None = None
    price_sort1: Decimal | None = Field(default=None, ge=0)
    price_sort1_5: Decimal | None = Field(default=None, ge=0)
    price_sort2: Decimal | None = Field(default=None, ge=0)
    raw_material_id: int | None = None
    waste_ratio: Decimal | None = Field(default=Decimal("1.15"), ge=1)
    cutting_rate: Decimal | None = Field(default=Decimal(0), ge=0)
    image_url: str | None = None


class ProductOut(BaseModel):
    id: int
    name: str
    category: str | None = None
    sku: str | None
    qr_code: str | None
    unit: str
    dona_m2: Decimal | None
    thickness: Decimal | None = None
    tile_length: Decimal | None = None
    tile_width: Decimal | None = None
    box_pieces: int | None = None
    box_m2: Decimal | None = None
    min_stock: Decimal | None = Decimal(15)
    price: Decimal
    cost_price: Decimal
    sort: str | None = None
    has_sorts: bool = False
    color: str | None = None
    price_sort1: Decimal | None = None
    price_sort1_5: Decimal | None = None
    price_sort2: Decimal | None = None
    image_url: str | None = None
    reserved_qty: Decimal | None = Decimal(0)
    raw_material_id: int | None = None
    waste_ratio: Decimal | None = None
    cutting_rate: Decimal | None = None
    is_active: bool
    deleted_at: datetime | None = None
    deleted_by_name: str | None = None
    stock: Decimal


# ---------- stock ----------
class PurchaseIn(BaseModel):
    product_id: int
    quantity: Decimal = Field(gt=0)
    unit: Literal["base", "dona"] = "base"
    unit_cost: Decimal = Field(ge=0)  # bazaviy birlik uchun xarid narxi
    note: str | None = None


class AdjustIn(BaseModel):
    product_id: int
    delta: Decimal  # +/- (bazaviy birlikda)
    note: str = Field(min_length=1)


class MovementOut(ORM):
    id: int
    product_id: int
    product_name: str | None = None
    qty_delta: Decimal
    kind: str
    ref_type: str | None = None
    ref_id: int | None = None
    note: str | None = None
    created_by_name: str | None = None
    created_at: datetime


# ---------- customers ----------
class CustomerIn(BaseModel):
    name: str = Field(min_length=1, max_length=128)
    phone: str | None = None
    passport: str | None = None
    photo_url: str | None = None


class CustomerOut(ORM):
    id: int
    name: str
    phone: str | None = None
    passport: str | None = None
    photo_url: str | None = None
    created_at: datetime | None = None
    total_spent: Decimal | None = None
    total_debt: Decimal | None = None
    sales_count: int | None = None


# ---------- sales ----------
class SaleItemIn(BaseModel):
    product_id: int
    quantity: Decimal = Field(gt=0)
    unit: Literal["base", "dona"] = "base"
    custom_name: str | None = None
    price: Decimal | None = None
    sort: str | None = None
    color: str | None = None


class SaleIn(BaseModel):
    items: list[SaleItemIn] = Field(min_length=1)
    paid_amount: Decimal = Field(ge=0)
    currency_rate: Decimal | None = None
    paid_uzs: Decimal | None = None
    paid_usd: Decimal | None = None
    customer_id: int | None = None
    customer_name: str | None = None
    customer_phone: str | None = None
    customer_passport: str | None = None
    customer_photo_url: str | None = None
    status: str = "completed"  # completed | order
    note: str | None = None


class SaleReturnItemIn(BaseModel):
    product_id: int
    quantity: Decimal = Field(gt=0)


class SaleReturnIn(BaseModel):
    items: list[SaleReturnItemIn] = Field(min_length=1)
    reason: str | None = None


class SaleItemOut(ORM):
    product_id: int
    product_name: str
    quantity: Decimal
    unit_price: Decimal
    line_total: Decimal


class SaleFulfillIn(BaseModel):
    received_by_name: str | None = None
    received_by_phone: str | None = None
    delivery_type: str | None = "pickup"  # 'pickup', 'delivery'
    receiver_doc_or_car: str | None = None
    note: str | None = None
    pay_amount: Decimal | None = None
    pay_method: str | None = "cash"


class SaleOut(BaseModel):
    id: int
    customer: CustomerOut | None
    cashier_id: int
    cashier_name: str | None = None
    total: Decimal
    paid: Decimal
    debt: Decimal
    currency_rate: Decimal | None = None
    paid_uzs: Decimal | None = None
    paid_usd: Decimal | None = None
    status: str = "completed"
    note: str | None = None
    received_by_name: str | None = None
    received_by_phone: str | None = None
    delivery_type: str | None = None
    receiver_doc_or_car: str | None = None
    fulfilled_by_name: str | None = None
    fulfilled_at: datetime | None = None
    created_at: datetime
    items: list[SaleItemOut]
    payment_method: str | None = None


class PaymentIn(BaseModel):
    amount: Decimal = Field(gt=0)
    method: str = "cash"


# ---------- production ----------
class TaskCreate(BaseModel):
    product_id: int
    assigned_to: int
    planned_qty: Decimal = Field(gt=0)
    note: str | None = None
    order_id: int | None = None
    cut_length: Decimal | None = None
    cut_width: Decimal | None = None
    cut_pieces: int | None = None
    cut_spec: str | None = None


class TaskReject(BaseModel):
    reason: str | None = None


class TaskReport(BaseModel):
    produced_qty: Decimal = Field(gt=0)  # shu hisobotda qo'shilgan miqdor
    waste_qty: Decimal | None = Field(default=Decimal(0), ge=0)  # yaroqsiz / chiqindi
    note: str | None = None


class TaskOut(BaseModel):
    id: int
    product_id: int
    product_name: str
    unit: str
    assigned_to: int
    worker_name: str
    planned_qty: Decimal
    produced_qty: Decimal
    waste_qty: Decimal | None = Decimal(0)
    status: str
    approved_by: int | None = None
    approved_at: datetime | None = None
    note: str | None = None
    order_id: int | None = None
    cut_length: Decimal | None = None
    cut_width: Decimal | None = None
    cut_pieces: int | None = None
    cut_spec: str | None = None


# ---------- finance ----------
class ExpenseIn(BaseModel):
    category: str = Field(min_length=1, max_length=64)
    amount: Decimal = Field(gt=0)
    note: str | None = None
    type: str = "expense"  # expense | income
    payment_method: str = "cash"  # cash | card | bank
    date: datetime | None = None


class ExpenseOut(ORM):
    id: int
    category: str
    amount: Decimal
    note: str | None
    created_at: datetime
    type: str = "expense"
    payment_method: str = "cash"


class FinanceTransactionIn(BaseModel):
    type: str = "expense"  # expense | income
    category: str = Field(min_length=1, max_length=64)
    amount: Decimal = Field(gt=0)
    payment_method: str = "cash"  # cash | card | bank
    note: str | None = None
    date: datetime | None = None


class FinanceTransactionOut(BaseModel):
    id: int
    type: str  # income | expense
    category: str
    amount: Decimal
    payment_method: str  # cash | card | bank
    note: str | None = None
    date: datetime
    created_by_name: str | None = None


class MonthStats(BaseModel):
    month_name: str
    year: int
    revenue: Decimal
    expenses: Decimal
    cogs: Decimal = Decimal(0)
    operational_expenses: Decimal = Decimal(0)
    net_profit: Decimal
    sales_count: int


class MonthlyComparisonOut(BaseModel):
    current: MonthStats
    previous: MonthStats
    revenue_growth_percent: float
    expense_growth_percent: float
    net_profit_growth_percent: float


class RevenueBreakdownItem(BaseModel):
    category: str
    amount: Decimal
    percentage: float
    count: int
    color_hex: str = "#10B981"


class FinanceSummary(BaseModel):
    revenue: Decimal  # savdo summasi
    cash_collected: Decimal  # kassaga tushgan haqiqiy pul
    cogs: Decimal  # sotilgan tovar tannarxi
    gross_profit: Decimal
    expenses: Decimal
    net_profit: Decimal
    receivables: Decimal  # umumiy qarzdorlik (nasiya)
    stock_value: Decimal = Decimal(0)  # ombordagi tovarlar qiymati (sotuv narxida)
    stock_cost_value: Decimal = Decimal(0)  # ombordagi tovarlar qiymati (tannarxda)


# ---------- notifications ----------
class NotificationIn(BaseModel):
    title: str = Field(min_length=1, max_length=128)
    message: str = Field(min_length=1)
    kind: str = Field(default="system")  # warning | payment | sale | production | system


class NotificationOut(ORM):
    id: int
    title: str
    message: str
    kind: str
    is_read: bool
    created_at: datetime


# ---------- deliveries ----------
class DeliveryItemIn(BaseModel):
    product_id: int | None = None
    product_name: str = Field(min_length=1, max_length=128)
    quantity: Decimal = Field(gt=0)
    unit: str = "dona"


class DeliveryItemOut(ORM):
    id: int
    delivery_id: int
    product_id: int | None = None
    product_name: str
    quantity: Decimal
    unit: str


class DeliveryCreate(BaseModel):
    sale_id: int | None = None
    driver_id: int | None = None
    vehicle_number: str = Field(min_length=1, max_length=32)
    vehicle_model: str = Field(default="Labo", max_length=64)
    driver_name: str = Field(min_length=1, max_length=128)
    driver_phone: str | None = None
    recipient_name: str = Field(min_length=1, max_length=128)
    recipient_phone: str | None = None
    destination_address: str | None = None
    delivery_fee: Decimal = Decimal("0")
    fee_payer: str = "customer"  # customer | store | included
    status: str = "loading"  # loading | on_the_way | delivered | cancelled
    dispatch_time: datetime | None = None
    delivered_time: datetime | None = None
    note: str | None = None
    items: list[DeliveryItemIn] = []


class DeliveryUpdate(BaseModel):
    driver_id: int | None = None
    vehicle_number: str | None = None
    vehicle_model: str | None = None
    driver_name: str | None = None
    driver_phone: str | None = None
    recipient_name: str | None = None
    recipient_phone: str | None = None
    destination_address: str | None = None
    delivery_fee: Decimal | None = None
    fee_payer: str | None = None
    status: str | None = None
    dispatch_time: datetime | None = None
    delivered_time: datetime | None = None
    note: str | None = None
    items: list[DeliveryItemIn] | None = None


class DeliveryStatusUpdate(BaseModel):
    status: str  # loading | on_the_way | delivered | cancelled


class DeliveryOut(ORM):
    id: int
    sale_id: int | None = None
    driver_id: int | None = None
    vehicle_number: str
    vehicle_model: str
    driver_name: str
    driver_phone: str | None = None
    recipient_name: str
    recipient_phone: str | None = None
    destination_address: str | None = None
    delivery_fee: Decimal
    fee_payer: str
    status: str
    dispatch_time: datetime | None = None
    delivered_time: datetime | None = None
    note: str | None = None
    created_at: datetime
    items: list[DeliveryItemOut] = []


