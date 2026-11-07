# 🔐 STONEX ERP (Namuna Tosh Jilo) — Dasturchi uchun qo‘llanma va barcha kirish ma’lumotlari

Ushbu hujjat loyihani davom ettiradigan yoki unga xizmat ko‘rsatadigan keyingi dasturchi uchun to‘liq yo‘riqnoma va barcha maxfiy parollarni o‘z ichiga oladi.

---

## 1. 👥 Foydalanuvchilar, Loginlar va Parollar

Ilovada (ham Mock, ham Real Backend rejimida) quyidagi rollar va hisoblar mavjud:

| № | To‘liq ismi (F.I.SH) | Rol (Role) | Login (Username) | Parol (Password) | PIN-kod | Tavsif / Ruxsatlar |
|---|---|---|---|---|---|---|
| **1** | **Xo‘jayin (Admin)** | `admin` | `admin` | `admin12345` *(yoki `admin123`)* | `1234` | Barcha huquqlar (moliya, narxlarni o‘zgartirish, oylik to‘lash, sozlamalar) |
| **2** | **Kassir Aziz** | `kassir` | `kassir` | `kassir123` | `1234` | Savdo (POS), toshga ishlov berish xizmatlari, chek chop etish, nasiya to‘lovlari |
| **3** | **Mansur Boshqaruvchi** | `boshqaruvchi` | `boshqaruvchi` | `boshqaruvchi123` | `1234` | Ish boshqaruvchi: ishlab chiqarish topshiriqlari yaratish, OTK tasdiqlash, ombor kirimi |
| **4** | **Ishchi Bobur** | `ishchi` | `ishchi` | `ishchi123` | `1234` | Sex ishchisi: biriktirilgan kesish va silliqlash vazifalarini bajarish |
| **5** | **Farhod Haydovchi** | `haydovchi` | `haydovchi` | `haydovchi123` | `1234` | Yetkazib berish, tovarlarni manzilga eltish |

> 💡 **Eslatma:** Ilova qulfi (PIN Lock) yoqilgan bo‘lsa, xodimlar uchun standart PIN kod: `1234` (yoki foydalanuvchining o‘zi sozlamalar orqali o‘zgartirishi mumkin).

---

## 2. 🚀 Loyihani ishga tushirish (Run & Development)

Loyiha ikki qismdan iborat:
* `backend/` — FastAPI + Python + SQLite / MySQL
* `app/` — Flutter (Desktop Windows, Android mobil va Web)

### A) Backendni ishga tushirish
```bash
cd backend

# Virtual muhit yaratish va faollashtirish:
python -m venv .venv
.venv\Scripts\activate      # Linux/Mac: source .venv/bin/activate

# Kutubxonalarni o'rnatish:
pip install -r requirements.txt

# Ma'lumotlar bazasini to'ldirish (seed):
python -m app.seed

# Serverni yoqish:
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```
* **Swagger API hujjatlari:** `http://127.0.0.1:8000/docs`
* **Ma'lumotlar bazasi fayli:** `backend/stonex.db` (SQLite) yoki MySQL `stone_erp`

### B) Flutter ilovasini ishga tushirish
```bash
cd app
flutter pub get

# 1. MOCK rejimida (Server yoqilmasdan ham to'liq ishlaydi):
flutter run -d windows
flutter run -d chrome

# 2. REAL BACKEND rejimida:
# Kompyuterda:
flutter run -d windows --dart-define=USE_MOCK=false --dart-define=API_URL=http://127.0.0.1:8000
# Android telefonda (Real qurilmada kompyuter lokal IP manzili beriladi):
flutter run -d android --dart-define=USE_MOCK=false --dart-define=API_URL=http://192.168.1.100:8000

# Barcha testlarni tekshirish (49/49 passing):
flutter test
```

---

## 3. ⚙️ Konfiguratsiya va Muhit o‘zgaruvchilari (Environment Variables)

Backend sozlamalari `backend/app/config.py` da joylashgan. Zarurat bo‘lsa `.env` orqali o‘zgartiriladi:

| O‘zgaruvchi | Standart qiymat (Default) | Tavsif |
|---|---|---|
| `DATABASE_URL` | `sqlite:///stonex.db` *(yoki MySQL)* | Asosiy ma'lumotlar bazasi havolasi |
| `SECRET_KEY` | `dev-only-change-me` | JWT tokenlarni imzolash kaliti |
| `ADMIN_USERNAME` | `admin` | Tizim bosh admini logini |
| `ADMIN_PASSWORD` | `admin12345` | Tizim bosh admini paroli |
| `PORT` | `8000` | FastAPI porti |

---

## 4. 🗂️ Loyiha arxitekturasi va Muhim fayllar xaritasi

### Flutter ilova (`app/lib/`)
* **`main.dart`** — Ilovaning kirish nuqtasi, `SystemChrome` (Status bar va Navigation bar ranglari va rejimlarini boshqarish), `Provider` sozlamalari.
* **`core/theme.dart`** — Vault / Stonex dizayn tizimi (Neon-Laym urg‘ular, Dark/Light rejim ranglari, `AppBarTheme.systemOverlayStyle`).
* **`domain/models.dart`** — Barcha ma’lumotlar modellari (`Product`, `Sale`, `Customer`, `ProductionTask`, `FinanceSummary`, `effectiveCategory` va toshlarni aniqlash qoidalari).
* **`ui/stone_services_dialog.dart`** — Tosh kesish (kvadrat metr kiritish, xizmat nomini toshga bog‘lash, silliqlash va faska hisoblash kalkulyatori).
* **`ui/pos_screen.dart`** — Kassa, savatcha, xizmatlarni qo‘shish, to‘lovni qabul qilish, QR chek chiqarish.
* **`ui/dashboard_screen.dart`** — Bosh sahifa (grafiklar, moliya ko‘rsatkichlari, eng ko‘p sotilgan toshlar, tezkor topshiriqlar).
* **`ui/production_screen.dart`** — Ishlab chiqarish sexi: topshiriq yaratish, ustaga biriktirish, OTK tekshiruvi.
* **`ui/finance_screen.dart`** — Kassa holati, tushum/chiqim, xodimlarga oylik to‘lash (barchasiga bir vaqtda yoki alohida).
* **`ui/debts_screen.dart`** — Mijozlar nasiyalari, qarzdorlikni so‘ndirish tarixi.
* **`data/local_security_store.dart`** — Xodimlarning PIN kodlari va ilova qulfi xotirasi.
* **`data/repository_factory.dart`** — `USE_MOCK` flagi orqali Mock va Real API o‘rtasida avtomatik almashish.

---

## 5. 🛠️ Toshga ishlov berish xizmatlari va Narxlar (Standart stavkalar)

Xizmatlar narxi `stone_services_dialog.dart` va bazadagi `products` jadvalida:
* **Eni va bo‘yiga kesish (`cut_m2`):** `25 000 so‘m / m²` *(Hisoblash kiritilgan kvadrat metr maydoniga ko‘paytiriladi)*
* **Faska ochish (`chamfer`):** `20 000 so‘m / pogon metr`
* **Granit silliqlash (`polish_granite`):** `30 000 so‘m / m²`
* **Keramogranit silliqlash (`polish_ceramics`):** `20 000 so‘m / m²`
* **Chizish / Yo‘l ochish (`groove`):** `10 000 so‘m / dona`

Narxlarni admin foydalanuvchi interfeysdagi **"Narxlarni sozlash"** tugmasi orqali to‘g‘ridan-to‘g‘ri o‘zgartirishi mumkin.

---

## 6. 📱 Mobil ekran (Status Bar) va Android sozlamalari

Ilovada telefonning yuqori paneli (soat, internet/Wi-Fi, batareya) doimiy ko‘rinishi uchun:
1. `app/lib/main.dart` da `SystemUiMode.manual` va `AnnotatedRegion<SystemUiOverlayStyle>` sozlangan.
2. `app/android/app/src/main/res/values/styles.xml` va `values-night/styles.xml` fayllarida `windowDrawsSystemBarBackgrounds=true` va `statusBarColor=@android:color/transparent` belgilangan.
3. Och rejimda piktogrammalar qora, qorong‘i rejimda oq rangda ravshan chiziladi.

---

*Hujjat yaratilgan sana: 2026-yil 7-noyabr*
*Muallif: Google Deepmind Antigravity Pair Programmer*
