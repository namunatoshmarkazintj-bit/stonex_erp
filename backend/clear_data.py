"""Savdolar va mijozlar ma'lumotlarini to'liq tozalash skripti.
Barcha sotuvlar, to'lovlar, yetkazib berishlar va mijozlarni bazadan o'chiradi.
Mahsulotlar katalogi, xodimlar va boshlang'ich qoldiqlar saqlanib qoladi.
"""
import sys
import os
from sqlalchemy import text

sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from app.database import engine, Base
import sqlite3

def clean_database():
    print(f"Connecting to: {engine.url}")
    try:
        with engine.begin() as conn:
            # Foreign key tekshiruvini vaqtincha o'chirish (agar MySQL yoki Postgres bo'lsa)
            if "sqlite" in str(engine.url):
                conn.execute(text("PRAGMA foreign_keys = OFF;"))
            elif "mysql" in str(engine.url):
                conn.execute(text("SET FOREIGN_KEY_CHECKS = 0;"))

            tables = ["delivery_items", "deliveries", "payments", "sale_items", "sales", "customers", "expenses", "production_tasks"]
            for tbl in tables:
                try:
                    res = conn.execute(text(f"DELETE FROM {tbl};"))
                    print(f"Tozalandi [{tbl}]: {res.rowcount} ta qator")
                except Exception as ex:
                    print(f"Jadval [{tbl}] xatolik: {ex}")

            # Savdolar va xaridlar ombor harakatlarini tozalash (faqat boshlang'ich opening qoladi)
            try:
                res = conn.execute(text("DELETE FROM stock_movements WHERE kind != 'opening';"))
                print(f"Tozalandi [stock_movements (not opening)]: {res.rowcount} ta qator")
            except Exception as ex:
                print(f"stock_movements xatolik: {ex}")

            # Xabarnomalarni tozalash
            try:
                res = conn.execute(text("DELETE FROM notifications;"))
                print(f"Tozalandi [notifications]: {res.rowcount} ta qator")
            except Exception as ex:
                print(f"notifications xatolik: {ex}")

            # Ishchilar va davomatni tozalash (admin saqlanadi)
            try:
                conn.execute(text("DELETE FROM attendance;"))
                res = conn.execute(text("DELETE FROM users WHERE role = 'ishchi' OR username = 'zoyirjon';"))
                print(f"Tozalandi [ishchilar]: {res.rowcount} ta qator")
            except Exception as ex:
                print(f"ishchilar xatolik: {ex}")

            if "mysql" in str(engine.url):
                conn.execute(text("SET FOREIGN_KEY_CHECKS = 1;"))
            elif "sqlite" in str(engine.url):
                conn.execute(text("PRAGMA foreign_keys = ON;"))

        print("Asosiy baza to'liq tozalandi.")
    except Exception as e:
        print(f"Asosiy bazaga ulanishda xatolik: {e}")

    # Agar lokal stonex.db mavjud bo'lsa, uni ham alohida tozalaymiz
    sqlite_path = os.path.join(os.path.dirname(__file__), "stonex.db")
    if os.path.exists(sqlite_path):
        print(f"Lokal SQLite tozalanmoqda: {sqlite_path}")
        try:
            con = sqlite3.connect(sqlite_path)
            cur = con.cursor()
            cur.execute("PRAGMA foreign_keys = OFF;")
            for tbl in ["delivery_items", "deliveries", "payments", "sale_items", "sales", "customers", "expenses", "production_tasks"]:
                try:
                    cur.execute(f"DELETE FROM {tbl};")
                    print(f"SQLite [{tbl}]: {cur.rowcount} ta qator o'chirildi")
                except Exception as e:
                    print(f"SQLite [{tbl}]: {e}")
            try:
                cur.execute("DELETE FROM stock_movements WHERE kind != 'opening';")
                print(f"SQLite [stock_movements]: {cur.rowcount} ta qator o'chirildi")
            except Exception as e:
                pass
            try:
                cur.execute("DELETE FROM notifications;")
            except Exception as e:
                pass
            con.commit()
            con.close()
            print("Lokal SQLite bazasi tozalandi.")
        except Exception as e:
            print(f"SQLite tozalashda xatolik: {e}")

if __name__ == "__main__":
    clean_database()
