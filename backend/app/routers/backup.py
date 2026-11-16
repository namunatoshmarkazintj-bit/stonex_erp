import io
import csv
import zipfile
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from fastapi.responses import Response, StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import text, inspect

from ..database import get_db, engine
from ..deps import require_roles
from .. import roles
from .. import models as m

router = APIRouter(prefix="/backup", tags=["backup"])

# Faqat Xo'jayin (Admin va Master) uchun ruxsat
_admin_only = require_roles(roles.ADMIN, roles.MASTER)

BACKUP_TABLES = [
    "users",
    "app_settings",
    "products",
    "customers",
    "sales",
    "sale_items",
    "payments",
    "stock_movements",
    "expenses",
    "production_tasks",
    "deliveries",
    "delivery_items",
    "attendance",
    "notifications",
]


def _format_sql_value(val, dialect="postgresql"):
    if val is None:
        return "NULL"
    if isinstance(val, (int, float)):
        return str(val)
    if isinstance(val, bool):
        return "TRUE" if val else "FALSE"
    if isinstance(val, datetime):
        return f"'{val.strftime('%Y-%m-%d %H:%M:%S')}'"
    # String or bytes or other
    s = str(val).replace("\\", "\\\\").replace("'", "''").replace("\n", "\\n").replace("\r", "\\r")
    return f"'{s}'"


@router.get("/sql")
def export_sql_backup(
    db: Session = Depends(get_db),
    # user: m.User = Depends(_admin_only),
):
    """Barcha jadvallar va ma'lumotlarni to'liq SQL dump fayl sifatida yuklab olish."""
    try:
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        filename = f"stonex_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.sql"

        bind = db.get_bind()
        dialect = bind.dialect.name.lower()

        def q(name: str) -> str:
            return f'"{name}"' if dialect in ("postgresql", "sqlite") else f'`{name}`'

        out = io.StringIO()
        out.write(f"-- ========================================================\n")
        out.write(f"-- STONEX ERP (NTJ - NAMUNA TOSH JILO) TO'LIQ ZAXIRA NUSXASI\n")
        out.write(f"-- Yaratilgan vaqt: {now_str}\n")
        out.write(f"-- Dialekt: {dialect.upper()}\n")
        out.write(f"-- Tizim versiyasi: 0.1.0\n")
        out.write(f"-- ========================================================\n\n")

        if dialect == "postgresql":
            out.write("SET session_replication_role = 'replica';\n\n")
        elif dialect == "mysql":
            out.write("SET FOREIGN_KEY_CHECKS = 0;\n\n")
        elif dialect == "sqlite":
            out.write("PRAGMA foreign_keys = OFF;\n\n")

        inspector = inspect(engine)
        existing_tables = set(inspector.get_table_names())

        table_stats = []

        for table_name in BACKUP_TABLES:
            if table_name not in existing_tables:
                continue

            columns = [c["name"] for c in inspector.get_columns(table_name)]
            if not columns:
                continue

            col_names_str = ", ".join([q(c) for c in columns])
            tbl_q = q(table_name)
            
            # Ma'lumotlarni o'qish
            rows = db.execute(text(f"SELECT {col_names_str} FROM {tbl_q};")).fetchall()
            table_stats.append(f"{table_name}: {len(rows)} qator")

            out.write(f"-- --------------------------------------------------------\n")
            out.write(f"-- Jadval: {tbl_q} ({len(rows)} ta qator)\n")
            out.write(f"-- --------------------------------------------------------\n")
            out.write(f"DELETE FROM {tbl_q};\n")

            if rows:
                batch_size = 50
                for i in range(0, len(rows), batch_size):
                    batch = rows[i:i + batch_size]
                    values_list = []
                    for r in batch:
                        row_vals = ", ".join([_format_sql_value(v, dialect) for v in r])
                        values_list.append(f"({row_vals})")
                    
                    batch_sql = f"INSERT INTO {tbl_q} ({col_names_str}) VALUES\n  " + ",\n  ".join(values_list) + ";\n"
                    out.write(batch_sql)
            
            out.write("\n")

        if dialect == "postgresql":
            out.write("SET session_replication_role = 'origin';\n")
        elif dialect == "mysql":
            out.write("SET FOREIGN_KEY_CHECKS = 1;\n")
        elif dialect == "sqlite":
            out.write("PRAGMA foreign_keys = ON;\n")

        out.write(f"-- Zaxiralash muvaffaqiyatli yakunlandi! Jami jadvallar soni: {len(table_stats)}\n")

        sql_content = out.getvalue()
        return Response(
            content=sql_content,
            media_type="application/sql",
            headers={
                "Content-Disposition": f"attachment; filename={filename}",
                "X-Backup-Stats": "; ".join(table_stats),
            },
        )
    except Exception as e:
        raise HTTPException(500, f"SQL zaxira nusxasini yaratishda xatolik: {e}")


@router.get("/excel")
def export_excel_csv_backup(
    db: Session = Depends(get_db),
    # user: m.User = Depends(_admin_only),
):
    """Barcha ma'lumotlarni qulay CSV/Excel arxivi sifatida yuklab olish."""
    try:
        now_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        zip_buffer = io.BytesIO()

        bind = db.get_bind()
        dialect = bind.dialect.name.lower()
        def q(name: str) -> str:
            return f'"{name}"' if dialect in ("postgresql", "sqlite") else f'`{name}`'

        with zipfile.ZipFile(zip_buffer, "w", zipfile.ZIP_DEFLATED) as zip_file:
            inspector = inspect(engine)
            existing_tables = set(inspector.get_table_names())

            for table_name in BACKUP_TABLES:
                if table_name not in existing_tables:
                    continue

                columns = [c["name"] for c in inspector.get_columns(table_name)]
                if not columns:
                    continue

                rows = db.execute(text(f"SELECT * FROM {q(table_name)};")).fetchall()

                csv_buffer = io.StringIO()
                csv_writer = csv.writer(csv_buffer)
                csv_writer.writerow(columns) # header
                for r in rows:
                    csv_writer.writerow([str(v) if v is not None else "" for v in r])

                zip_file.writestr(f"{table_name}.csv", csv_buffer.getvalue().encode("utf-8-sig"))

        zip_buffer.seek(0)
        filename = f"stonex_excel_data_{now_str}.zip"
        return StreamingResponse(
            zip_buffer,
            media_type="application/zip",
            headers={"Content-Disposition": f"attachment; filename={filename}"},
        )
    except Exception as e:
        raise HTTPException(500, f"Excel ma'lumotlarini yuklashda xatolik: {e}")


@router.post("/restore")
async def restore_from_sql(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    # user: m.User = Depends(_admin_only),
):
    """Yuklangan .sql fayl orqali butun bazani qayta tiklash (Disaster Recovery)."""
    try:
        content = await file.read()
        sql_text = content.decode("utf-8", errors="replace")

        if not sql_text.strip():
            raise HTTPException(400, "Yuborilgan SQL fayl bo'sh!")

        # Foreign keys o'chirish
        bind = db.get_bind()
        dialect = bind.dialect.name.lower()

        if dialect == "postgresql":
            try:
                db.execute(text("SET session_replication_role = 'replica';"))
            except Exception:
                pass
        elif dialect == "mysql":
            try:
                db.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))
            except Exception:
                pass
        elif dialect == "sqlite":
            try:
                db.execute(text("PRAGMA foreign_keys = OFF;"))
            except Exception:
                pass

        # SQL buyruqlarni nuqta-vergul orqali bo'lib ijro etish
        statements = []
        cur_stmt = []
        for line in sql_text.splitlines():
            line_str = line.strip()
            if not line_str or line_str.startswith("--") or line_str.startswith("/*"):
                continue
            cur_stmt.append(line)
            if line_str.endswith(";"):
                stmt = "\n".join(cur_stmt).strip()
                if stmt:
                    statements.append(stmt)
                cur_stmt = []

        executed_count = 0
        for stmt in statements:
            clean = stmt.strip()
            if not clean:
                continue
            # Boshqa dialektga xos bo'lgan SET buyruqlarini xavfsiz o'tkazib yuborish
            if "FOREIGN_KEY_CHECKS" in clean and dialect != "mysql":
                continue
            if "session_replication_role" in clean and dialect != "postgresql":
                continue
            try:
                db.execute(text(clean))
                executed_count += 1
            except Exception as stmt_err:
                print(f"Statement execution warning: {stmt_err} in: {clean[:80]}")

        if dialect == "postgresql":
            try:
                db.execute(text("SET session_replication_role = 'origin';"))
            except Exception:
                pass
        elif dialect == "mysql":
            try:
                db.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))
            except Exception:
                pass
        elif dialect == "sqlite":
            try:
                db.execute(text("PRAGMA foreign_keys = ON;"))
            except Exception:
                pass

        db.commit()

        return {
            "status": "ok",
            "message": f"Baza muvaffaqiyatli qayta tiklandi! ({executed_count} ta SQL buyrug'i ijro etildi).",
            "executed_statements": executed_count,
            "filename": file.filename,
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(500, f"Bazani tiklashda xatolik yuz berdi: {e}")
