# miniO-core

هستهٔ قابل‌استفادهٔ مجدد MinIO. این ریپو را کنار هر پروژه‌ای قرار بده، اسم پروژه را بده، و bucket + policy عمومی فقط برای همان پروژه ساخته می‌شود.

---

## فهرست مراحل

| مرحله | کار |
|------|-----|
| [۰](#۰-پیش‌نیازها) | پیش‌نیازها |
| [۱](#۱-قرار-دادن-ریپو-کنار-پروژه) | قرار دادن ریپو کنار پروژه |
| [۲](#۲-اتصال-به-اسم-پروژه-init) | اتصال به اسم پروژه (`init`) |
| [۳](#۳-توسعه-محلی-dev) | راه‌اندازی Dev |
| [۴](#۴-اتصال-اپلیکیشن-به-minio-در-dev) | اتصال اپ به MinIO (Dev) |
| [۵](#۵-تولید-production) | راه‌اندازی Prod |
| [۶](#۶-اتصال-اپلیکیشن-به-minio-در-prod) | اتصال اپ به MinIO (Prod) |
| [۷](#۷-آپلود-و-تست) | آپلود و تست |
| [۸](#۸-نگهداری-و-دوباره‌اعمال-policy) | نگهداری و policy |

---

## ۰. پیش‌نیازها

قبل از شروع این‌ها را داشته باش:

1. **Docker** و **Docker Compose** نصب و در حال اجرا
2. برای Prod: **Traefik** روی همان سرور (یا شبکهٔ مشترک) با resolver به نام `letsencrypt`
3. برای Prod: یک دامنهٔ DNS مثل `assets.example.com` که به سرور اشاره کند
4. دسترسی به ترمینال در ریشهٔ همین ریپو (`miniO-core/`)

---

## ۱. قرار دادن ریپو کنار پروژه

ساختار پیشنهادی:

```text
Projects/
├── my-app/          # اپلیکیشن تو
└── miniO-core/      # این هسته (ریپوی جدا)
```

```bash
cd /path/to/Projects
git clone <url-of-miniO-core> miniO-core
cd miniO-core
```

می‌توانی برای هر دیپلوی یک clone جدا بگیری و با `PROJECT_NAME` متفاوت مقداردهی کنی.

---

## ۲. اتصال به اسم پروژه (init)

**یک‌بار برای هر پروژه** این اسکریپت را بزن. اسم پروژه به bucket، container، network و policy تبدیل می‌شود.

```bash
# قالب کلی
./scripts/init-project.sh <project-name> --host <public-assets-host>

# مثال
./scripts/init-project.sh example --host assets.example.com
```

### این اسکریپت چه می‌سازد؟

| خروجی | مقدار نمونه (`example`) |
|--------|----------------------------|
| `PROJECT_NAME` | `example` |
| `MINIO_BUCKET` | `example` |
| `MINIO_CONTAINER` | `example_minio` |
| `MINIO_NETWORK` | `example_network` |
| `MINIO_PUBLIC_HOST` | `assets.example.com` |
| فایل‌ها | `.env`, `dev/.env`, `prod/.env.example`, `policy/public-read.json` |

### Policy تولیدشده چه اجازه‌ای می‌دهد؟

فقط خواندن عمومی روی این مسیر:

```text
<bucket>/public/*
```

Action مجاز: `s3:GetObject`

هر چیز دیگری (مثلاً `<bucket>/private/videos/*`) **خصوصی** می‌ماند.

> **هشدار:** هرگز `mc anonymous set download local/<bucket>` نزن — کل bucket را عمومی می‌کند.

---

## ۳. توسعه محلی (Dev)

### ۳.۱ بالا آوردن MinIO

```bash
# از ریشهٔ miniO-core
cd dev
docker compose --env-file .env up -d
```

صبر کن تا کانتینرها بالا بیایند:

```bash
docker ps --filter "name=$(grep MINIO_CONTAINER .env | cut -d= -f2)"
```

### ۳.۲ آدرس‌های Dev

| سرویس | آدرس |
|--------|------|
| S3 API | http://localhost:9000 |
| Console | http://localhost:9001 |
| نمونهٔ فایل عمومی | `http://localhost:9000/<bucket>/public/...` |

ورود Console با همان `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` داخل `dev/.env`.

### ۳.۳ اگر policy اعمال نشد

سرویس `minio_init` معمولاً موقع `compose up` policy را می‌زند. اگر لازم شد دستی:

```bash
cd /path/to/miniO-core
MINIO_ENV_FILE=./dev/.env ./scripts/setup-public-policy.sh
```

---

## ۴. اتصال اپلیکیشن به MinIO در Dev

در `.env` (یا تنظیمات) **اپلیکیشن** این مقادیر را بگذار — با `dev/.env` هم‌خوان باشند:

```env
MINIO_INTERNAL_ENDPOINT=localhost
MINIO_INTERNAL_PORT=9000
MINIO_USE_SSL=false
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin123
MINIO_BUCKET=example
MINIO_PUBLIC_BASE_URL=http://localhost:9000/example
```

جایگزین کن:

- `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` ← همان `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
- `MINIO_BUCKET` ← همان `MINIO_BUCKET` پروژه
- `MINIO_PUBLIC_BASE_URL` ← `http://localhost:9000/<bucket>`

### قرارداد مسیرها در اپ

| نوع محتوا | کلید ذخیره‌سازی | عمومی؟ |
|-----------|-----------------|--------|
| کاور، اسلاید، تصویر عمومی | `public/...` | بله |
| ویدیو / فایل حساس | `private/...` | خیر |

URL عمومی نهایی در Dev:

```text
http://localhost:9000/<bucket>/public/<path>
```

---

## ۵. تولید (Production)

ترتیب را **دقیقاً** رعایت کن.

### ۵.۱ init روی سرور (اگر هنوز نزده‌ای)

```bash
cd /path/to/miniO-core
./scripts/init-project.sh example --host assets.example.com
```

### ۵.۲ ساخت `prod/.env`

```bash
cp prod/.env.example prod/.env
```

سپس `prod/.env` را ویرایش کن:

1. `MINIO_ROOT_PASSWORD` را با پسورد قوی عوض کن  
   - اگر در مقدار پسورد کاراکتر `$` داری، در Compose باید `$$` بنویسی (مثلاً `Pa$$word` → در فایل `Pa$$$$word` برای یک `$` واقعی در runtime؛ طبق کامنت داخل `.env.example`)
2. بقیهٔ فیلدها (`PROJECT_NAME`, `MINIO_BUCKET`, `MINIO_CONTAINER`, `MINIO_NETWORK`, `MINIO_PUBLIC_HOST`) معمولاً از init درست هستند

### ۵.۳ شبکهٔ Docker مشترک با Traefik / اپ

یک‌بار روی سرور:

```bash
# نام را از prod/.env بخوان (مثال: example_network)
docker network create example_network
```

Traefik و اپ باید روی **همین** network باشند تا:

- Traefik به MinIO برسد
- اپ با hostname سرویس `minio` (بدون `_`) به API وصل شود

### ۵.۴ DNS

رکورد A/AAAA برای `MINIO_PUBLIC_HOST` (مثلاً `assets.example.com`) را به IP سرور بده.

### ۵.۵ بالا آوردن Prod

```bash
cd /path/to/miniO-core/prod
docker compose --env-file .env up -d
```

بررسی:

```bash
docker compose --env-file .env ps
docker logs "$(grep MINIO_CONTAINER .env | cut -d= -f2)" --tail 50
```

### ۵.۶ مسیریابی Traefik (از قبل در Compose تعریف شده)

با labelهای Compose این قانون اعمال می‌شود:

```text
Host(<MINIO_PUBLIC_HOST>) && PathPrefix(/public)
  → MinIO :9000 /<bucket>/public/...
```

یعنی درخواست:

```text
https://assets.example.com/public/grades/grade-10.webp
```

داخل MinIO می‌شود:

```text
/example/public/grades/grade-10.webp
```

نیازی به تعریف دستی Traefik جدا نیست؛ فقط Traefik باید روی همان network باشد و certresolver به نام `letsencrypt` داشته باشد.

---

## ۶. اتصال اپلیکیشن به MinIO در Prod

در env اپلیکیشن (روی سرور / compose اپ):

```env
MINIO_INTERNAL_ENDPOINT=minio
MINIO_INTERNAL_PORT=9000
MINIO_USE_SSL=false
MINIO_ACCESS_KEY=<همان MINIO_ROOT_USER در prod/.env>
MINIO_SECRET_KEY=<همان MINIO_ROOT_PASSWORD در prod/.env>
MINIO_BUCKET=example
MINIO_PUBLIC_BASE_URL=https://assets.example.com
```

### نکات مهم

1. endpoint داخلی را **`minio`** بگذار (alias سرویس Compose)، نه `example_minio`  
   - کلاینت MinIO JS hostname با `_` را رد می‌کند
2. اپ باید روی همان `MINIO_NETWORK` باشد تا DNS نام `minio` را resolve کند
3. URL عمومی برای کاربر نهایی از `MINIO_PUBLIC_BASE_URL` ساخته شود، مثلاً:

```text
https://assets.example.com/public/covers/book.webp
```

(کلید آبجکت داخل bucket: `public/covers/book.webp`)

---

## ۷. آپلود و تست

### ۷.۱ آپلود نمونه (با mc یا اپ)

با Console روی پورت ۹۰۰۱ (Dev) یا از داخل کانتینر:

```bash
# مثال مفهومی: فایل باید زیر public/ باشد تا عمومی شود
# storage key: public/test/hello.txt
```

### ۷.۲ اعمال / تأیید policy

```bash
cd /path/to/miniO-core
./scripts/setup-public-policy.sh
```

خروجی باید policy با Resource شبیه این را نشان دهد:

```text
arn:aws:s3:::<bucket>/public/*
```

### ۷.۳ تست HTTP

**Dev:**

```bash
curl -I "http://localhost:9000/<bucket>/public/test/hello.txt"
```

**Prod:**

```bash
curl -I "https://assets.example.com/public/test/hello.txt"
```

انتظار برای فایل موجود: `HTTP/2 200` (یا `HTTP/1.1 200`).

فایل خارج از `public/` نباید بدون credential در دسترس باشد.

---

## ۸. نگهداری و دوباره‌اعمال policy

| کار | دستور |
|-----|--------|
| ساخت مجدد policy از اسم پروژه | `./scripts/generate-policy.sh` |
| اعمال policy روی MinIO در حال اجرا | `./scripts/setup-public-policy.sh` |
| Dev با env مشخص | `MINIO_ENV_FILE=./dev/.env ./scripts/setup-public-policy.sh` |
| Prod با env مشخص | `MINIO_ENV_FILE=./prod/.env ./scripts/setup-public-policy.sh` |
| عوض کردن پروژه روی همین clone | `./scripts/init-project.sh other --host assets.other.example.com` سپس envها را چک کن |

`minio_init` در Compose هم موقع recreate معمولاً همان policy را دوباره می‌زند؛ اگر شک داشتی `setup-public-policy.sh` را بزن.

---

## متغیرهای هویت پروژه

| متغیر | مثال | نقش |
|--------|------|-----|
| `PROJECT_NAME` | `example` | برچسب پروژه |
| `MINIO_BUCKET` | `example` | نام bucket |
| `MINIO_CONTAINER` | `example_minio` | نام کانتینر Docker |
| `MINIO_NETWORK` | `example_network` | شبکهٔ خارجی (Prod) |
| `MINIO_PUBLIC_HOST` | `assets.example.com` | هاست عمومی Traefik |
| `MINIO_ROOT_USER` | … | یوزر root MinIO |
| `MINIO_ROOT_PASSWORD` | … | پسورد root MinIO |

---

## ساختار ریپو

```text
miniO-core/
├── policy/
│   ├── public-read.json.template   # قالب (منبع حقیقت)
│   └── public-read.json            # تولیدشده (gitignored)
├── scripts/
│   ├── init-project.sh             # مرحلهٔ ۲: PROJECT_NAME → env + policy
│   ├── generate-policy.sh          # رندر policy از نام bucket
│   └── setup-public-policy.sh      # اعمال policy با mc
├── prod/
│   ├── docker-compose.yml
│   └── .env.example
├── dev/
│   ├── docker-compose.yml
│   ├── .env.example
│   └── README.md
└── README.md
```

---

## خلاصهٔ مسیر سریع

```bash
# 1) کلون / رفتن کنار اپ
cd miniO-core

# 2) bind به پروژه
./scripts/init-project.sh example --host assets.example.com

# 3) Dev
cd dev && docker compose --env-file .env up -d

# 4) env اپ را مطابق بخش ۴ پر کن

# ——— روی سرور Prod ———
# 5) cp prod/.env.example prod/.env  → پسورد قوی
# 6) docker network create <MINIO_NETWORK>
# 7) DNS برای MINIO_PUBLIC_HOST
# 8) cd prod && docker compose --env-file .env up -d
# 9) env اپ Prod مطابق بخش ۶
# 10) ./scripts/setup-public-policy.sh && curl -I https://...
```
