"""API integratsiya testi (SQLite). Kerak: pip install -r requirements.txt"""
import os
import tempfile
import unittest

_db = os.path.join(tempfile.mkdtemp(), "test.db")
os.environ["DATABASE_URL"] = f"sqlite:///{_db}"
os.environ["ADMIN_PASSWORD"] = "admin-test-123"

from fastapi.testclient import TestClient  # noqa: E402

from app import seed  # noqa: E402
from app.main import app  # noqa: E402


class ApiTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        seed.main()
        cls.c = TestClient(app)
        r = cls.c.post("/auth/login", json={"username": "admin", "password": "admin-test-123"})
        cls.h = {"Authorization": f"Bearer {r.json()['access_token']}"}
        for u, role, pw in (
            ("kassir1", "kassir", "parol12345"),
            ("ishchi1", "ishchi", "parol12345"),
            ("ishchi", "ishchi", "ishchi123"),
            ("boshqaruvchi", "ish_boshqaruvchi", "boshqaruvchi123"),
        ):
            cls.c.post("/users", headers=cls.h, json={
                "username": u, "full_name": u, "password": pw, "role": role})

    def login(self, u):
        r = self.c.post("/auth/login", json={"username": u, "password": "parol12345"})
        return {"Authorization": f"Bearer {r.json()['access_token']}"}

    def product(self, name):
        items = self.c.get("/products", headers=self.h).json()
        return next(p for p in items if p["name"] == name)

    def test_role_mismatch_rejected(self):
        r = self.c.post("/auth/login", json={"username": "kassir1", "password": "parol12345",
                                              "role": "admin"})
        self.assertEqual(r.status_code, 403)

    def test_cashier_cannot_manage_products(self):
        r = self.c.post("/products", headers=self.login("kassir1"),
                        json={"name": "X", "unit": "dona", "price": 1})
        self.assertEqual(r.status_code, 403)

    def test_sale_in_dona_reduces_stock_and_tracks_debt(self):
        before = self.product("Angola")
        k = self.login("kassir1")
        r = self.c.post("/sales", headers=k, json={
            "items": [{"product_id": before["id"], "quantity": 8, "unit": "dona"}],  # 2 m2
            "paid_amount": 100000, "customer_name": "Ali"})
        self.assertEqual(r.status_code, 201, r.text)
        s = r.json()
        self.assertEqual(float(s["total"]), 360000.0)
        self.assertEqual(float(s["debt"]), 260000.0)
        after = self.product("Angola")
        self.assertEqual(float(before["stock"]) - float(after["stock"]), 2.0)
        # nasiya to'lovi
        r = self.c.post(f"/sales/{s['id']}/payments", headers=k, json={"amount": 260000})
        self.assertEqual(float(r.json()["debt"]), 0.0)

    def test_cannot_oversell(self):
        p = self.product("Disk")
        r = self.c.post("/sales", headers=self.login("kassir1"), json={
            "items": [{"product_id": p["id"], "quantity": 9999}], "paid_amount": 0,
            "customer_name": "Vali"})
        self.assertEqual(r.status_code, 400)

    def test_debt_requires_customer(self):
        p = self.product("Kley")
        r = self.c.post("/sales", headers=self.login("kassir1"), json={
            "items": [{"product_id": p["id"], "quantity": 1}], "paid_amount": 0})
        self.assertEqual(r.status_code, 400)

    def test_dona_not_allowed_for_non_stone(self):
        p = self.product("Kley")
        r = self.c.post("/sales", headers=self.login("kassir1"), json={
            "items": [{"product_id": p["id"], "quantity": 1, "unit": "dona"}], "paid_amount": 0,
            "customer_name": "Z"})
        self.assertEqual(r.status_code, 400)

    def test_product_image_upload(self):
        # 1. Rasm faylini yuklash
        fake_image = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00`\x00`\x00\x00"
        r = self.c.post("/products/upload-image", headers=self.h,
                        files={"file": ("granit.jpg", fake_image, "image/jpeg")})
        self.assertEqual(r.status_code, 200)
        img_url = r.json()["image_url"]
        self.assertTrue(img_url.startswith("/uploads/products/"))

        # 2. Yangi mahsulotni ushbu rasm bilan yaratish
        r = self.c.post("/products", headers=self.h, json={
            "name": "Granit Plita", "unit": "m2", "price": 220000, "image_url": img_url
        })
        self.assertEqual(r.status_code, 201)
        created = r.json()
        self.assertEqual(created["image_url"], img_url)

        # 3. Mavjud mahsulotga to'g'ridan-to'g'ri rasm yuklash
        r = self.c.post(f"/products/{created['id']}/image", headers=self.h,
                        files={"file": ("granit_new.png", fake_image, "image/png")})
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.json()["image_url"].endswith(".png"))

    def test_attendance_and_salary_calculation(self):
        # 1. Yangi xodim maoshi bilan
        r = self.c.post("/users", headers=self.h, json={
            "username": "usta_davron",
            "full_name": "Davron Usta",
            "password": "parol12345",
            "role": "ishchi",
            "salary": 5200000,
            "salary_type": "monthly"
        })
        self.assertEqual(r.status_code, 201)
        uid = r.json()["id"]

        # 2. Check-in (keldi)
        r = self.c.post("/attendance/check-in", headers=self.h, json={
            "user_id": uid,
            "date": "2026-10-15",
            "check_in": "2026-10-15T08:30:00"
        })
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["status"], "present")

        # 3. Check-out (ketdi)
        r = self.c.post("/attendance/check-out", headers=self.h, json={
            "user_id": uid,
            "date": "2026-10-15",
            "check_out": "2026-10-15T18:00:00"
        })
        self.assertEqual(r.status_code, 200)
        self.assertEqual(float(r.json()["worked_hours"]), 9.5)

        # 4. Kechikkan kun (9:30 da kelgan)
        r = self.c.post("/attendance/check-in", headers=self.h, json={
            "user_id": uid,
            "date": "2026-10-16",
            "check_in": "2026-10-16T09:30:00"
        })
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.json()["status"], "late")

        # 5. Oylik hisoboti
        r = self.c.get("/attendance/salary-report?month=2026-10&total_working_days=26", headers=self.h)
        self.assertEqual(r.status_code, 200)
        rep = next(x for x in r.json() if x["user_id"] == uid)
        self.assertEqual(rep["days_worked"], 2)
        self.assertEqual(rep["days_late"], 1)
        self.assertGreater(float(rep["calculated_salary"]), 0)

    def test_sale_return_rules(self):
        # 1. Yangi mahsulot
        pr = self.c.post("/products", headers=self.h, json={
            "name": "Kafel Granit Oq", "unit": "m2", "price": 100000, "cost_price": 60000, "initial_stock": 50
        })
        self.assertEqual(pr.status_code, 201)
        pid = pr.json()["id"]

        # 2. Savdo qilish (3 m2 butun, 2 m2 kesilgan)
        sr = self.c.post("/sales", headers=self.h, json={
            "items": [
                {"product_id": pid, "quantity": 3, "unit": "base"},
                {"product_id": pid, "quantity": 2, "unit": "base", "custom_name": "Kafel Granit Oq [1.2x0.6m (4 dona)]"}
            ],
            "paid_amount": 500000
        })
        self.assertEqual(sr.status_code, 201)
        sale_id = sr.json()["id"]

        # 3. Kesilgan mahsulotni qaytarishga urinish (bloklanishi shart)
        ret_fail = self.c.post(f"/sales/{sale_id}/return", headers=self.h, json={
            "items": [{"product_id": pid, "quantity": 1}],
            "reason": "Kesilgan tosh"
        })
        self.assertEqual(ret_fail.status_code, 400)
        self.assertIn("kesilgan", ret_fail.json()["detail"].lower())

        # 4. Faqat butun mahsulotli yangi savdo
        pr2 = self.c.post("/products", headers=self.h, json={
            "name": "Butun Kafel 60x60", "unit": "dona", "price": 50000, "cost_price": 30000, "initial_stock": 100
        })
        pid2 = pr2.json()["id"]

        sr2 = self.c.post("/sales", headers=self.h, json={
            "items": [{"product_id": pid2, "quantity": 10, "unit": "base"}],
            "paid_amount": 500000
        })
        sale2_id = sr2.json()["id"]

        # 5. Butun mahsulotdan 3 dona qaytarish
        ret_ok = self.c.post(f"/sales/{sale2_id}/return", headers=self.h, json={
            "items": [{"product_id": pid2, "quantity": 3}],
            "reason": "Mijoz ortib qolgan butun kafelni qaytardi"
        })
        self.assertEqual(ret_ok.status_code, 200)
        # Ombordagi qoldiq tiklanishi kerak: 100 - 10 + 3 = 93
        prod_check = self.c.get("/products", headers=self.h)
        p_obj = next(x for x in prod_check.json() if x["id"] == pid2)
        self.assertEqual(float(p_obj["stock"]), 93.0)

    def test_currency_rate_and_dual_currency_sale(self):
        # 1. CBU Kursini olish
        res = self.c.get("/finance/currency-rate")
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertIn("rate", data)
        self.assertGreater(data["rate"], 10000)

        # 2. Mahsulot yaratish
        pr = self.c.post("/products", headers=self.h, json={
            "name": "Marmar Plita Dollar Test", "unit": "m2", "price": 120000, "cost_price": 80000, "initial_stock": 50
        })
        pid = pr.json()["id"]

        # 3. So'm va dollarda aralash to'lov (masalan $5 + 60 000 so'm, kurs 12 000 bo'lsa)
        rate = 12000.0
        sale_res = self.c.post("/sales", headers=self.h, json={
            "items": [{"product_id": pid, "quantity": 1, "unit": "base"}],
            "paid_amount": 120000,
            "currency_rate": rate,
            "paid_uzs": 60000,
            "paid_usd": 5.0,
        })
        self.assertEqual(sale_res.status_code, 201)
        s_data = sale_res.json()
        self.assertEqual(float(s_data["currency_rate"]), rate)
        self.assertEqual(float(s_data["paid_uzs"]), 60000.0)
        self.assertEqual(float(s_data["paid_usd"]), 5.0)

    def test_delivery_crud_and_status(self):
        # 1. Yetkazib berish (Delivery) yaratish
        payload = {
            "vehicle_number": "01 A 777 AA",
            "vehicle_model": "Labo",
            "driver_name": "Farhod Haydovchi",
            "driver_phone": "+998 90 123 45 67",
            "recipient_name": "Akmal aka",
            "recipient_phone": "+998 93 987 65 43",
            "destination_address": "Toshkent sh., Chilonzor 9",
            "delivery_fee": 150000,
            "fee_payer": "customer",
            "status": "loading",
            "note": "Ehtiyotkorlik bilan yetkazilsin",
            "items": [
                {"product_name": "Granit 60x60", "quantity": 40.0, "unit": "m2"},
                {"product_name": "Kafel yelimi", "quantity": 10.0, "unit": "qop"},
            ],
        }
        res = self.c.post("/deliveries", headers=self.h, json=payload)
        self.assertEqual(res.status_code, 201)
        d = res.json()
        self.assertEqual(d["vehicle_number"], "01 A 777 AA")
        self.assertEqual(d["driver_name"], "Farhod Haydovchi")
        self.assertEqual(len(d["items"]), 2)
        did = d["id"]

        # 2. Ro'yxatdan qidirish
        list_res = self.c.get(f"/deliveries?query=777", headers=self.h)
        self.assertEqual(list_res.status_code, 200)
        self.assertTrue(any(x["id"] == did for x in list_res.json()))

        # 3. Holatini o'zgartirish: loading -> on_the_way -> delivered
        status_res = self.c.patch(f"/deliveries/{did}/status", headers=self.h, json={"status": "on_the_way"})
        self.assertEqual(status_res.status_code, 200)
        self.assertEqual(status_res.json()["status"], "on_the_way")
        self.assertIsNotNone(status_res.json()["dispatch_time"])

        status_res2 = self.c.patch(f"/deliveries/{did}/status", headers=self.h, json={"status": "delivered"})
        self.assertEqual(status_res2.status_code, 200)
        self.assertEqual(status_res2.json()["status"], "delivered")
        self.assertIsNotNone(status_res2.json()["delivered_time"])

    def test_order_fulfill_with_receiver(self):
        p = self.product("Angola")
        # 1. Buyurtma yaratish
        sale_res = self.c.post("/sales", headers=self.h, json={
            "customer_name": "Azizbek Azimov",
            "items": [{"product_id": p["id"], "quantity": 1, "unit": "base"}],
            "status": "order",
            "paid_amount": 100000,
            "note": "Topshirish testi",
        })
        self.assertEqual(sale_res.status_code, 201, sale_res.text)
        sale_id = sale_res.json()["id"]

        # 2. Buyurtmani qabul qiluvchi shaxs va to'lov bilan topshirish
        fulfill_res = self.c.post(f"/sales/{sale_id}/fulfill", headers=self.h, json={
            "received_by_name": "Azizbek Azimov",
            "received_by_phone": "+998 90 123 45 67",
            "delivery_type": "delivery",
            "receiver_doc_or_car": "01 A 777 AA",
            "note": "Mijoz xursand bo'lib qabul qildi",
            "pay_amount": 80000,
            "pay_method": "cash",
        })
        self.assertEqual(fulfill_res.status_code, 200, fulfill_res.text)
        f_data = fulfill_res.json()
        self.assertEqual(f_data["status"], "completed")
        self.assertEqual(f_data["received_by_name"], "Azizbek Azimov")
        self.assertEqual(f_data["received_by_phone"], "+998 90 123 45 67")
        self.assertEqual(f_data["delivery_type"], "delivery")
        self.assertEqual(f_data["receiver_doc_or_car"], "01 A 777 AA")
        self.assertIsNotNone(f_data["fulfilled_at"])

    def test_order_reserved_qty_prevents_oversell(self):
        # 1. Mahsulot yaratish: 20 m2 mavjud
        pr = self.c.post("/products", headers=self.h, json={
            "name": "Marmar Travertin", "unit": "m2", "price": 200000, "cost_price": 120000, "initial_stock": 20
        })
        self.assertEqual(pr.status_code, 201)
        pid = pr.json()["id"]

        # 2. Buyurtmachi 15 m2 buyurtma beradi (avans bilan)
        ord_res = self.c.post("/sales", headers=self.h, json={
            "customer_name": "Sardor aka",
            "customer_phone": "+998901112233",
            "items": [{"product_id": pid, "quantity": 15, "unit": "base"}],
            "status": "order",
            "paid_amount": 500000,
        })
        self.assertEqual(ord_res.status_code, 201)
        ord_id = ord_res.json()["id"]

        # 3. Boshqa kassir kelib 10 m2 darhol sotmoqchi bo'ladi
        # 20 - 15 = 5 m2 qolgan, shuning uchun 10 m2 xato berishi shart!
        fail_sale = self.c.post("/sales", headers=self.h, json={
            "items": [{"product_id": pid, "quantity": 10, "unit": "base"}],
            "paid_amount": 2000000,
        })
        self.assertEqual(fail_sale.status_code, 400)
        self.assertIn("yetarli emas", fail_sale.json()["detail"].lower())

        # 4. 5 m2 esa muvaffaqiyatli sotiladi
        ok_sale = self.c.post("/sales", headers=self.h, json={
            "items": [{"product_id": pid, "quantity": 5, "unit": "base"}],
            "paid_amount": 1000000,
        })
        self.assertEqual(ok_sale.status_code, 201)

        # 5. Buyurtmani bekor qilish zaxirani qaytaradi
        cancel_res = self.c.post(f"/sales/{ord_id}/cancel", headers=self.h)
        self.assertEqual(cancel_res.status_code, 200)

        # Endi o'sha 15 m2 yana bo'shadi va sotilishi mumkin
        ok_sale2 = self.c.post("/sales", headers=self.h, json={
            "items": [{"product_id": pid, "quantity": 15, "unit": "base"}],
            "paid_amount": 3000000,
        })
        self.assertEqual(ok_sale2.status_code, 201)

    def test_production_bom_and_otk_approval(self):
        # 1. Xomashyo bloki yaratish: 100 m2
        raw_res = self.c.post("/products", headers=self.h, json={
            "name": "Qora Granit Bloki (Xomashyo)", "unit": "m2", "price": 100000, "cost_price": 50000, "initial_stock": 100
        })
        raw_id = raw_res.json()["id"]

        # 2. Tayyor tosh yaratish: BOM bog'langan (raw_material_id, waste_ratio=1.20, cutting_rate=10000)
        prod_res = self.c.post("/products", headers=self.h, json={
            "name": "Black Crystal 60x60 (Tayyor)", "unit": "m2", "price": 250000, "cost_price": 120000,
            "raw_material_id": raw_id, "waste_ratio": 1.20, "cutting_rate": 10000, "initial_stock": 0
        })
        prod_id = prod_res.json()["id"]

        # 3. Ishchini topish
        users_res = self.c.get("/users", headers=self.h)
        worker = next(u for u in users_res.json() if u["username"] == "ishchi")
        wid = worker["id"]

        # 4. Topshiriq yaratish
        task_res = self.c.post("/production", headers=self.h, json={
            "product_id": prod_id, "assigned_to": wid, "planned_qty": 50
        })
        self.assertEqual(task_res.status_code, 201)
        tid = task_res.json()["id"]

        # 5. Ishchi hisoboti topshiradi (20 m2 chiqqan, 2 m2 chiqindi)
        # Ishchi tokeni bilan kirish
        w_token_res = self.c.post("/auth/login", json={"username": "ishchi", "password": "ishchi123"})
        w_headers = {"Authorization": f"Bearer {w_token_res.json()['access_token']}"}

        rep_res = self.c.post(f"/production/{tid}/report", headers=w_headers, json={
            "produced_qty": 20, "waste_qty": 2
        })
        self.assertEqual(rep_res.status_code, 200)
        self.assertEqual(rep_res.json()["status"], "pending_approval")

        # 6. Brigadir / Admin OTK tasdig'ini o'tkazadi
        appr_res = self.c.post(f"/production/{tid}/approve", headers=self.h)
        self.assertEqual(appr_res.status_code, 200)
        self.assertEqual(appr_res.json()["status"], "done")

        # 7. Ombor tekshiruvi:
        # Tayyor tosh: 20 m2 kirim bo'lgan
        p_check = self.c.get(f"/products/by-code/{prod_res.json().get('sku') or prod_id}", headers=self.h)
        # Xomashyo: (20 + 2) * 1.2 = 26.4 m2 sarflangan (100 - 26.4 = 73.6 m2 qolgan)
        raw_check = self.c.get("/products", headers=self.h)
        raw_prod = next(p for p in raw_check.json() if p["id"] == raw_id)
        self.assertEqual(float(raw_prod["stock"]), 73.6)

    def test_foreman_role_permissions_and_single_account_limit(self):
        # 1. Ish boshqaruvchi login qilishi
        f_login = self.c.post("/auth/login", json={"username": "boshqaruvchi", "password": "boshqaruvchi123"})
        self.assertEqual(f_login.status_code, 200)
        f_token = f_login.json()["access_token"]
        f_headers = {"Authorization": f"Bearer {f_token}"}
        me = self.c.get("/auth/me", headers=f_headers)
        self.assertEqual(me.json()["role"], "ish_boshqaruvchi")

        # 2. Ish boshqaruvchi ishchilarni ko'ra olishi
        u_res = self.c.get("/users", headers=f_headers)
        self.assertEqual(u_res.status_code, 200)
        workers = [u for u in u_res.json() if u["username"] == "ishchi"]
        self.assertTrue(len(workers) > 0)
        wid = workers[0]["id"]

        # 2.1 Ish boshqaruvchi buyurtmalarni (sales) ko'ra olishi (kesish topshiriqlarini olish uchun)
        s_res = self.c.get("/sales", headers=f_headers)
        self.assertEqual(s_res.status_code, 200)

        # 3. Ish boshqaruvchi ishchini ishga biriktirishi (topshiriq yaratishi)
        prods = self.c.get("/products", headers=f_headers).json()
        pid = prods[0]["id"]
        t_res = self.c.post("/production", headers=f_headers, json={
            "product_id": pid, "assigned_to": wid, "planned_qty": 30, "note": "Foreman assigned"
        })
        self.assertEqual(t_res.status_code, 201)
        tid = t_res.json()["id"]

        # 4. Ishchi hisobot topshiradi
        w_login = self.c.post("/auth/login", json={"username": "ishchi", "password": "ishchi123"})
        w_headers = {"Authorization": f"Bearer {w_login.json()['access_token']}"}
        rep = self.c.post(f"/production/{tid}/report", headers=w_headers, json={"produced_qty": 30})
        self.assertEqual(rep.status_code, 200)
        self.assertEqual(rep.json()["status"], "pending_approval")

        # 5. Ish boshqaruvchi hisobotni tasdiqlaydi (OTK tasdig'i)
        appr = self.c.post(f"/production/{tid}/approve", headers=f_headers)
        self.assertEqual(appr.status_code, 200)
        self.assertEqual(appr.json()["status"], "done")

        # 6. Tizimda 2-ish boshqaruvchi akkauntini ochishga urinish (faqat 1 ta bo'lishi shart)
        dup_foreman = self.c.post("/users", headers=self.h, json={
            "username": "boshqaruvchi_2", "password": "password123", "full_name": "Ikkinchi Brigadir",
            "role": "ish_boshqaruvchi", "can_login": True, "salary": 7000000, "salary_type": "monthly"
        })
        self.assertEqual(dup_foreman.status_code, 400)
        self.assertIn("faqat 1 ta", dup_foreman.json()["detail"].lower())

        # 7. Ishchi topshiriqni bajara olmasdan qaytarishi (reject)
        t_res2 = self.c.post("/production", headers=f_headers, json={
            "product_id": pid, "assigned_to": wid, "planned_qty": 15, "note": "Buyurtma #55 kesish"
        })
        self.assertEqual(t_res2.status_code, 201)
        tid2 = t_res2.json()["id"]

        rej_res = self.c.post(f"/production/{tid2}/reject", headers=w_headers, json={"reason": "Stanok band"})
        self.assertEqual(rej_res.status_code, 200)
        self.assertEqual(rej_res.json()["status"], "rejected")
        self.assertIn("Stanok band", rej_res.json()["note"])

        # 7. Ish boshqaruvchi ombordagi harakatlarni va qoldiqlarni ko'ra olishi
        stk_res = self.c.get("/stock/movements", headers=f_headers)
        self.assertEqual(stk_res.status_code, 200)

        # 8. Ish boshqaruvchi ombor qoldig'ini tuzata olishi (inventarizatsiya)
        adj_res = self.c.post("/stock/adjust", headers=f_headers, json={
            "product_id": pid, "delta": 5, "note": "Inventarizatsiya boshqaruvchi tomonidan"
        })
        self.assertEqual(adj_res.status_code, 201)

    def test_finance_transactions_and_analytics(self):
        # 1. Chiqim kiritish (masalan: ish haqi / oylik)
        exp_res = self.c.post("/finance/transactions", headers=self.h, json={
            "type": "expense",
            "category": "Ish haqi / Oylik",
            "amount": 3500000,
            "payment_method": "cash",
            "note": "Usta Bobur oylik avansi"
        })
        self.assertEqual(exp_res.status_code, 201)
        exp_data = exp_res.json()
        self.assertEqual(exp_data["type"], "expense")
        self.assertEqual(exp_data["category"], "Ish haqi / Oylik")
        self.assertEqual(float(exp_data["amount"]), 3500000)

        # 2. Qo'shimcha kirim kiritish
        inc_res = self.c.post("/finance/transactions", headers=self.h, json={
            "type": "income",
            "category": "Qo'shimcha daromad",
            "amount": 1200000,
            "payment_method": "card",
            "note": "Tosh qoldiqlari sotildi"
        })
        self.assertEqual(inc_res.status_code, 201)

        # 3. Tranzaksiyalar ro'yxatini olish
        tx_res = self.c.get("/finance/transactions", headers=self.h)
        self.assertEqual(tx_res.status_code, 200)
        tx_list = tx_res.json()
        self.assertGreaterEqual(len(tx_list), 2)
        categories = [t["category"] for t in tx_list]
        self.assertIn("Ish haqi / Oylik", categories)
        self.assertIn("Qo'shimcha daromad", categories)

        # 4. Oylar bo'yicha taqqoslash (Monthly comparison)
        comp_res = self.c.get("/finance/monthly-comparison", headers=self.h)
        self.assertEqual(comp_res.status_code, 200)
        comp_data = comp_res.json()
        self.assertIn("current", comp_data)
        self.assertIn("previous", comp_data)
        self.assertIn("revenue_growth_percent", comp_data)
        self.assertIn("expense_growth_percent", comp_data)
        self.assertIn("net_profit_growth_percent", comp_data)

        # 5. Nimadan ko'p pul tushdi (Revenue breakdown)
        brk_res = self.c.get("/finance/revenue-breakdown", headers=self.h)
        self.assertEqual(brk_res.status_code, 200)
        brk_data = brk_res.json()
        self.assertIsInstance(brk_data, list)

        # 6. CSV eksport
        csv_res = self.c.get("/finance/export", headers=self.h)
        self.assertEqual(csv_res.status_code, 200)
        self.assertIn("text/csv", csv_res.headers.get("content-type", ""))
        self.assertIn("MOLIYA VA KIRIM-CHIQIM HISOBOTI", csv_res.text)


if __name__ == "__main__":
    unittest.main()
