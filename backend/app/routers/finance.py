from datetime import date, datetime, time, timedelta
from decimal import Decimal
import json
import time as time_mod
import urllib.request

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .. import models as m
from .. import roles
from ..database import get_db
from ..deps import require_roles
from ..schemas import (
    ExpenseIn,
    ExpenseOut,
    FinanceSummary,
    FinanceTransactionIn,
    FinanceTransactionOut,
    MonthlyComparisonOut,
    MonthStats,
    RevenueBreakdownItem,
)
from ..units import q2

def _utcnow():
    return m.get_server_now()

router = APIRouter(tags=["finance"])
_admin_or_cashier = require_roles(roles.ADMIN, roles.CASHIER)
_admin = require_roles(roles.ADMIN)


def _sum(db: Session, col, *conds) -> Decimal:
    return q2(db.scalar(select(func.coalesce(func.sum(col), 0)).where(*conds)) or 0)


@router.get("/finance/summary", response_model=FinanceSummary)
def summary(
    date_from: date | None = None,
    date_to: date | None = None,
    db: Session = Depends(get_db),
    _: m.User = Depends(_admin_or_cashier),
):
    def rng(col):
        c = []
        if date_from:
            c.append(col >= datetime.combine(date_from, time.min))
        if date_to:
            c.append(col <= datetime.combine(date_to, time.max))
        return c

    revenue = _sum(db, m.Sale.total, *rng(m.Sale.created_at))
    cogs = _sum(db, m.Sale.total_cost, *rng(m.Sale.created_at))
    cash = _sum(db, m.Payment.amount, *rng(m.Payment.created_at))
    expenses = _sum(db, m.Expense.amount, m.Expense.type == "expense", *rng(m.Expense.created_at))
    receivables = _sum(db, m.Sale.total - m.Sale.paid)  # umumiy, davrga bog'liq emas
    gross = revenue - cogs

    # Ombordagi tovarlar qiymati (sotuv narxida va tannarxda)
    from ..services.stock import stock_map
    stocks = stock_map(db)
    products = db.scalars(select(m.Product).where(m.Product.is_active.is_(True))).all()
    stock_value = Decimal(0)
    stock_cost_value = Decimal(0)
    for p in products:
        if p.category and p.category.lower() == "xizmat":
            continue
        stk = stocks.get(p.id, Decimal(0))
        if stk > 0:
            stock_value += (p.price or Decimal(0)) * stk
            stock_cost_value += (p.cost_price or Decimal(0)) * stk

    return FinanceSummary(
        revenue=revenue,
        cash_collected=cash,
        cogs=cogs,
        gross_profit=gross,
        expenses=expenses,
        net_profit=gross - expenses,
        receivables=receivables,
        stock_value=q2(stock_value),
        stock_cost_value=q2(stock_cost_value),
    )


@router.post("/expenses", response_model=ExpenseOut, status_code=201)
def add_expense(data: ExpenseIn, db: Session = Depends(get_db), user: m.User = Depends(_admin_or_cashier)):
    created_at = data.date or _utcnow()
    e = m.Expense(
        category=data.category,
        amount=q2(data.amount),
        note=data.note,
        type=data.type or "expense",
        payment_method=data.payment_method or "cash",
        created_by=user.id,
        created_at=created_at,
    )
    db.add(e)
    db.commit()
    db.refresh(e)
    return e


@router.get("/expenses", response_model=list[ExpenseOut])
def list_expenses(limit: int = 200, db: Session = Depends(get_db), _: m.User = Depends(_admin_or_cashier)):
    return db.scalars(select(m.Expense).order_by(m.Expense.id.desc()).limit(min(limit, 1000))).all()


@router.get("/finance/transactions", response_model=list[FinanceTransactionOut])
def list_transactions(
    type: str | None = Query(None, description="income | expense"),
    category: str | None = None,
    date_from: date | None = None,
    date_to: date | None = None,
    limit: int = 300,
    db: Session = Depends(get_db),
    _: m.User = Depends(_admin_or_cashier),
):
    """Barcha kirim va chiqim operatsiyalari jurnali."""
    real_type = type if isinstance(type, str) and type in ("income", "expense") else None
    real_cat = category if isinstance(category, str) and category != "Barchasi" else None
    items: list[FinanceTransactionOut] = []

    # 1. Chiqimlar va qo'shimcha kirimlar (Expense jadvalidan)
    stmt_exp = select(m.Expense)
    if date_from:
        stmt_exp = stmt_exp.where(m.Expense.created_at >= datetime.combine(date_from, time.min))
    if date_to:
        stmt_exp = stmt_exp.where(m.Expense.created_at <= datetime.combine(date_to, time.max))
    if real_type:
        stmt_exp = stmt_exp.where(m.Expense.type == real_type)
    if real_cat:
        stmt_exp = stmt_exp.where(m.Expense.category == real_cat)

    expenses = db.scalars(stmt_exp.order_by(m.Expense.created_at.desc()).limit(limit)).all()
    for e in expenses:
        user_name = e.creator.full_name if e.creator else "Boshqaruvchi"
        items.append(
            FinanceTransactionOut(
                id=e.id,
                type=e.type or "expense",
                category=e.category,
                amount=e.amount,
                payment_method=e.payment_method or "cash",
                note=e.note,
                date=e.created_at,
                created_by_name=user_name,
            )
        )

    # 2. Savdo tushumlari (Payment jadvalidan faqat income so'ralganda yoki barchasi olinganda)
    if not real_type or real_type == "income":
        stmt_pay = select(m.Payment, m.Sale).join(m.Sale, m.Payment.sale_id == m.Sale.id)
        if date_from:
            stmt_pay = stmt_pay.where(m.Payment.created_at >= datetime.combine(date_from, time.min))
        if date_to:
            stmt_pay = stmt_pay.where(m.Payment.created_at <= datetime.combine(date_to, time.max))

        payments = db.execute(stmt_pay.order_by(m.Payment.created_at.desc()).limit(limit)).all()
        for p, s in payments:
            cat = "Qarz to‘lovi" if s.note and "qarz" in s.note.lower() else "Savdo tushumi"
            if real_cat and real_cat != cat:
                continue
            cust_name = s.customer.name if s.customer else "Mijoz"
            items.append(
                FinanceTransactionOut(
                    id=100000 + p.id,
                    type="income",
                    category=cat,
                    amount=p.amount,
                    payment_method=p.method or "cash",
                    note=f"Buyurtma #{s.id} ({cust_name})" + (f": {s.note}" if s.note else ""),
                    date=p.created_at,
                    created_by_name="Kassa",
                )
            )

    # Tartiblash: sanasi bo'yicha kamayish tartibida
    items.sort(key=lambda x: x.date, reverse=True)
    return items[:limit]


@router.post("/finance/transactions", response_model=FinanceTransactionOut, status_code=201)
def add_transaction(
    data: FinanceTransactionIn,
    db: Session = Depends(get_db),
    user: m.User = Depends(_admin_or_cashier),
):
    """Yangi kirim yoki chiqim yozuvini kiritish."""
    created_at = data.date or _utcnow()
    e = m.Expense(
        category=data.category,
        amount=q2(data.amount),
        note=data.note,
        type=data.type,
        payment_method=data.payment_method,
        created_by=user.id,
        created_at=created_at,
    )
    db.add(e)
    db.commit()
    db.refresh(e)

    return FinanceTransactionOut(
        id=e.id,
        type=e.type,
        category=e.category,
        amount=e.amount,
        payment_method=e.payment_method,
        note=e.note,
        date=e.created_at,
        created_by_name=user.full_name,
    )


@router.get("/finance/monthly-comparison", response_model=MonthlyComparisonOut)
def monthly_comparison(
    cur_date_from: date | None = None,
    cur_date_to: date | None = None,
    prev_date_from: date | None = None,
    prev_date_to: date | None = None,
    cur_label: str | None = None,
    prev_label: str | None = None,
    db: Session = Depends(get_db),
    _: m.User = Depends(_admin_or_cashier),
):
    """Davrlarni (oylik yoki ixtiyoriy tanlangan davr) o'rtasida solishtirish."""
    today = date.today()
    month_names = {
        1: "Yanvar", 2: "Fevral", 3: "Mart", 4: "Aprel",
        5: "May", 6: "Iyun", 7: "Iyul", 8: "Avgust",
        9: "Sentyabr", 10: "Oktyabr", 11: "Noyabr", 12: "Dekabr"
    }

    if cur_date_from and cur_date_to and prev_date_from and prev_date_to:
        c_start, c_end = cur_date_from, cur_date_to
        p_start, p_end = prev_date_from, prev_date_to
        c_label = cur_label or f"{c_start.strftime('%d.%m')} - {c_end.strftime('%d.%m')}"
        p_label = prev_label or f"{p_start.strftime('%d.%m')} - {p_end.strftime('%d.%m')}"
        c_year = c_end.year
        p_year = p_end.year
    else:
        # Default: Joriy oy vs O'tgan oy
        c_start = date(today.year, today.month, 1)
        c_end = today
        c_label = cur_label or month_names[today.month]
        c_year = today.year

        if today.month == 1:
            p_start = date(today.year - 1, 12, 1)
            p_end = date(today.year - 1, 12, 31)
        else:
            p_start = date(today.year, today.month - 1, 1)
            next_month_start = date(today.year, today.month, 1)
            p_end = next_month_start - timedelta(days=1)
        p_label = prev_label or month_names[p_start.month]
        p_year = p_start.year

    def calc_period(s_date: date, e_date: date, m_name: str, yr: int) -> MonthStats:
        cond_sales = [
            m.Sale.created_at >= datetime.combine(s_date, time.min),
            m.Sale.created_at <= datetime.combine(e_date, time.max)
        ]
        cond_exp = [
            m.Expense.created_at >= datetime.combine(s_date, time.min),
            m.Expense.created_at <= datetime.combine(e_date, time.max),
            m.Expense.type == "expense"
        ]
        rev = _sum(db, m.Sale.total, *cond_sales)
        cogs = _sum(db, m.Sale.total_cost, *cond_sales)
        exp = _sum(db, m.Expense.amount, *cond_exp)
        sales_cnt = db.scalar(select(func.count(m.Sale.id)).where(*cond_sales)) or 0
        total_exp = cogs + exp
        net = rev - total_exp
        return MonthStats(
            month_name=m_name,
            year=yr,
            revenue=rev,
            expenses=total_exp,
            cogs=cogs,
            operational_expenses=exp,
            net_profit=net,
            sales_count=int(sales_cnt)
        )

    cur_stats = calc_period(c_start, c_end, c_label, c_year)
    prev_stats = calc_period(p_start, p_end, p_label, p_year)

    def calc_growth(cur: Decimal, prev: Decimal) -> float:
        if prev == 0:
            return 100.0 if cur > 0 else (0.0 if cur == 0 else -100.0)
        diff = float((cur - prev) / abs(prev) * 100)
        return round(diff, 1)

    rev_growth = calc_growth(cur_stats.revenue, prev_stats.revenue)
    exp_growth = calc_growth(cur_stats.expenses, prev_stats.expenses)
    profit_growth = calc_growth(cur_stats.net_profit, prev_stats.net_profit)

    return MonthlyComparisonOut(
        current=cur_stats,
        previous=prev_stats,
        revenue_growth_percent=rev_growth,
        expense_growth_percent=exp_growth,
        net_profit_growth_percent=profit_growth,
    )


@router.get("/finance/revenue-breakdown", response_model=list[RevenueBreakdownItem])
def revenue_breakdown(
    date_from: date | None = None,
    date_to: date | None = None,
    db: Session = Depends(get_db),
    _: m.User = Depends(_admin_or_cashier),
):
    """Nimadan ko'p pul tushdi (Mahsulotlar va xizmatlar bo'yicha daromad taqsimoti diagrammasi)."""
    conds = []
    if date_from:
        conds.append(m.Sale.created_at >= datetime.combine(date_from, time.min))
    if date_to:
        conds.append(m.Sale.created_at <= datetime.combine(date_to, time.max))

    stmt = (
        select(m.SaleItem, m.Product)
        .join(m.Sale, m.SaleItem.sale_id == m.Sale.id)
        .join(m.Product, m.SaleItem.product_id == m.Product.id)
    )
    if conds:
        stmt = stmt.where(*conds)

    rows = db.execute(stmt).all()

    categories_map: dict[str, dict] = {
        "Granit plitalar": {"amount": Decimal(0), "count": 0, "color": "#0284C7"},
        "Tosh kesish va ishlov xizmatlari": {"amount": Decimal(0), "count": 0, "color": "#10B981"},
        "Keramogranit": {"amount": Decimal(0), "count": 0, "color": "#8B5CF6"},
        "Metalogranit va marmar": {"amount": Decimal(0), "count": 0, "color": "#F59E0B"},
        "Yordamchi tovarlar va kley": {"amount": Decimal(0), "count": 0, "color": "#64748B"},
    }

    total_all = Decimal(0)

    for item, prod in rows:
        p_name = (item.product_name or prod.name or "").lower()
        cat = (prod.category or "").lower()
        item_total = item.line_total

        total_all += item_total

        if "kesish" in p_name or "silliqlash" in p_name or "faska" in p_name or "chizish" in p_name or "xizmat" in cat or "[" in p_name:
            key = "Tosh kesish va ishlov xizmatlari"
        elif "keram" in p_name or "keram" in cat or "kafel" in p_name:
            key = "Keramogranit"
        elif "metalo" in p_name or "marmar" in p_name:
            key = "Metalogranit va marmar"
        elif "kley" in p_name or "disk" in p_name or "profil" in p_name or "asbob" in cat:
            key = "Yordamchi tovarlar va kley"
        else:
            key = "Granit plitalar"

        categories_map[key]["amount"] += item_total
        categories_map[key]["count"] += 1

    result: list[RevenueBreakdownItem] = []
    for k, v in categories_map.items():
        amt = v["amount"]
        if amt > 0 or total_all == 0:
            pct = float((amt / total_all * 100)) if total_all > 0 else 0.0
            result.append(
                RevenueBreakdownItem(
                    category=k,
                    amount=amt,
                    percentage=round(pct, 1),
                    count=v["count"],
                    color_hex=v["color"],
                )
            )

    result.sort(key=lambda x: x.amount, reverse=True)
    return result


@router.get("/finance/export")
def export_transactions_csv(
    date_from: date | None = None,
    date_to: date | None = None,
    db: Session = Depends(get_db),
    user: m.User = Depends(_admin_or_cashier),
):
    """Excel formatidagi CSV hisobot fayli (UTF-8 BOM bilan)."""
    txs = list_transactions(date_from=date_from, date_to=date_to, limit=1000, db=db, _=user)

    lines = [
        "MOLIYA VA KIRIM-CHIQIM HISOBOTI (StoneX ERP)",
        f"Eksport vaqti: {datetime.now().strftime('%d.%m.%Y %H:%M')}",
        "",
        "#;Sana;Turi;Kategoriya;To'lov usuli;Summa (so'm);Izoh;Mas'ul",
    ]

    total_in = Decimal(0)
    total_out = Decimal(0)

    for i, t in enumerate(txs, 1):
        dt_str = t.date.strftime("%d.%m.%Y %H:%M")
        t_type = "Kirim" if t.type == "income" else "Chiqim"
        method_str = "Naqd" if t.payment_method == "cash" else ("Karta" if t.payment_method == "card" else "Bank")
        clean_note = (t.note or "").replace(";", " ")
        lines.append(f"{i};{dt_str};{t_type};{t.category};{method_str};{int(t.amount)};{clean_note};{t.created_by_name or ''}")

        if t.type == "income":
            total_in += t.amount
        else:
            total_out += t.amount

    lines.append("")
    lines.append("MOLIYAVIY XULOSA:")
    lines.append(f"Jami Kirim;{int(total_in)} so'm")
    lines.append(f"Jami Chiqim;{int(total_out)} so'm")
    lines.append(f"Sof Foyda;{int(total_in - total_out)} so'm")

    # UTF-8 with BOM (\ufeff) allows Microsoft Excel to open without UTF-8 encoding problems
    csv_content = "\ufeff" + "\r\n".join(lines)
    filename = f"Stonex_Moliya_{datetime.now().strftime('%Y_%m_%d')}.csv"

    return Response(
        content=csv_content,
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


_cbu_cache = {
    "rate": 12023.0,
    "diff": "0.00",
    "date": "",
    "updated_at": 0.0,
}


@router.get("/finance/currency-rate")
def get_currency_rate():
    """Markaziy bank (CBU) rasmiy AQSH dollari kursini olish (10 daqiqa keshlash bilan)"""
    now = time_mod.time()
    if now - _cbu_cache["updated_at"] < 600 and _cbu_cache["rate"] > 0:
        return _cbu_cache

    try:
        req = urllib.request.Request(
            "https://cbu.uz/uz/arkhiv-kursov-valyut/json/",
            headers={"User-Agent": "StonexERP/1.0"}
        )
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            for row in data:
                if row.get("Ccy") == "USD":
                    _cbu_cache["rate"] = float(row.get("Rate", 12023.0))
                    _cbu_cache["diff"] = str(row.get("Diff", "0.00"))
                    _cbu_cache["date"] = str(row.get("Date", ""))
                    _cbu_cache["updated_at"] = now
                    break
    except Exception:
        pass

    return _cbu_cache
