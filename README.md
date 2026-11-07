# STONEX ERP (Namuna Tosh Jilo)

> 🔐 **Dasturchilar uchun:** Barcha parollar, loginlar, PIN-kodlar, API sozlamalari va arxitektura yo‘riqnomasi to‘liq **[CREDENTIALS_AND_HANDOVER.md](file:///c:/Users/nout.plus/Desktop/stonex_erp/CREDENTIALS_AND_HANDOVER.md)** fayliga yozib qo‘yilgan.

Tosh ishlab chiqarish sexi uchun ERP: **Flutter** (Windows/mobil) → **FastAPI** → **MySQL / SQLite (`stonex.db`)**.

```
stonex_erp/
├─ backend/   FastAPI + SQLAlchemy (auth, rollar, ombor, savdo/nasiya, ishlab chiqarish, moliya)
└─ app/       Flutter ilovasi (Repository Pattern: Mock <-> API)
```

## Holat (halol hisobot)

| Modul | Backend | Flutter |
|---|---|---|
| Login, rollar (admin/kassir/ishchi), parol xeshlash, JWT | ✅ | ✅ |
| Mahsulotlar, QR/SKU qidiruv, 1 dona = 0,25 m² (faqat toshlarda) | ✅ | ✅ (CRUD) |
| Ombor harakatlari (xarid, tuzatish, o'rtacha tannarx) | ✅ | ✅ (`StockScreen` — xarid kirimi va tuzatish) |
| Kassa, savdo, qisman to'lov, nasiya, nasiya to'lovi | ✅ | ✅ (`PosScreen` va `DebtsScreen` — qarz yopish) |
| Ishlab chiqarish topshiriqlari → omborga kirim | ✅ | ✅ |
| Moliya: daromad, kassa, tannarx, yalpi/sof foyda, qarz | ✅ | ✅ (dashboard) |
| Xodimlar boshqaruvi | ✅ API (`/users`) | ✅ (`UsersScreen` — xodim qo‘shish, tahrirlash) |
| Davomat, ish haqi | ❌ | ❌ |
| AI tahlil, hisobotlar | ❌ | ❌ |
| Kameralar | ❌ | ❌ placeholder |

Placeholder ekranlar "hali ishlab chiqilmagan" deb yoziladi — soxta ma'lumot ko'rsatilmaydi.

## 1. Backend

```bash
# MySQL'da bir marta:
#   CREATE DATABASE stone_erp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
#   CREATE USER 'stone_user'@'localhost' IDENTIFIED BY 'PAROL';
#   GRANT ALL ON stone_erp.* TO 'stone_user'@'localhost';

cd backend
python -m venv .venv
.venv\Scripts\activate          # Linux/macOS: source .venv/bin/activate
pip install -r requirements.txt

# .env.example ni ko'chirib to'ldiring va muhit o'zgaruvchilariga yuklang
# (Windows PowerShell:  $env:DATABASE_URL="mysql+pymysql://..." ; $env:SECRET_KEY="..." ; $env:ADMIN_PASSWORD="...")

python -m app.seed                          # jadvallar + admin + namunaviy mahsulotlar
uvicorn app.main:app --reload --port 8000   # http://127.0.0.1:8000/docs
```

Testlar:
```bash
python -m unittest tests.test_units_security -v   # kutubxonasiz
python -m unittest tests.test_api -v              # requirements o'rnatilgach (SQLite'da ishlaydi)
```

## 2. Flutter

Bu arxivda faqat `lib/`, `test/`, `pubspec.yaml` bor. Platforma papkalarini bir marta yarating:

```bash
cd app
flutter create . --project-name stonex_erp --platforms=windows,android
flutter pub get
flutter test

flutter run -d windows                                   # MOCK rejimi (server kerak emas)
flutter run -d windows --dart-define=USE_MOCK=false --dart-define=API_URL=http://127.0.0.1:8000
```
Mock akkauntlar: `admin/admin123`, `kassir/kassir123`, `ishchi/ishchi123`.
Haqiqiy rejimda admin loginini `.env` dagi `ADMIN_USERNAME/ADMIN_PASSWORD` dan olasiz; kassir va ishchini admin `POST /users` (hozircha `/docs` orqali) bilan yaratadi.
Android emulyatorida `API_URL=http://10.0.2.2:8000`.

## Muhim qarorlar

- **Pul:** `Sale.total` (savdo summasi), `Payment` (kassaga tushgan pul), `Sale.total_cost` (tannarx) alohida. Bitta to'lov ikki marta sanalmaydi; `paid` faqat Payment qo'shilganda oshadi.
- **Ombor:** qoldiq alohida ustunda emas, `stock_movements` yig'indisi. Savdo/xarid/ishlab chiqarish/tuzatish bitta tizimda. Manfiy qoldiqqa sotish rad etiladi.
- **Birlik:** `dona_m2` faqat belgilangan toshlarda (0,25). Boshqa mahsulotni "dona" bilan sotishga urinish rad etiladi.
- **Tannarx:** xaridda o'rtacha tortilgan usulda yangilanadi; sotuvda sotilgan paytdagi tannarx saqlanadi.
- **Xavfsizlik:** PBKDF2 parol xeshi; rol har so'rovda bazadan olinadi; login ekranidagi rol tanlovi hech narsa bermaydi (mos kelmasa 403).
- **Mahsulotni o'chirish** — faolsizlantirish (tarix saqlanadi).
- Jadvallar `create_all` bilan yaratiladi. Ish jarayonida sxema o'zgarsa, **Alembic**ga o'tish kerak.

## Keyingi bosqichlar (tavsiya)
1. Flutter: ombor (xarid/tuzatish), nasiya to'lovi, xodimlar ekranlari.
2. Davomat va ish haqi (Expense `salary` bilan bog'lash), xarajatlar ekrani.
3. Alembic migratsiyalari, kamera orqali QR skaner (`mobile_scanner`), hisobotlar/AI tahlil.
