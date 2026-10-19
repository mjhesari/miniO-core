# Dev — MinIO محلی

جزئیات کامل و ترتیب مراحل: **[../README.md](../README.md)**  
این فایل فقط میان‌بر مراحل Dev است.

## مراحل به ترتیب

### ۱. Init پروژه (از ریشهٔ ریپو — یک‌بار)

```bash
cd ..
./scripts/init-project.sh example
# یا با هاست Prod از الان:
# ./scripts/init-project.sh example --host assets.example.com
```

این کار `dev/.env` و `policy/public-read.json` را می‌سازد/به‌روز می‌کند.

### ۲. بالا آوردن Compose

```bash
cd dev
docker compose --env-file .env up -d
```

- API: http://localhost:9000  
- Console: http://localhost:9001  
- Bucket: مقدار `MINIO_BUCKET` در `.env`  
- عمومی فقط: `<bucket>/public/*`

### ۳. env اپلیکیشن

```env
MINIO_INTERNAL_ENDPOINT=localhost
MINIO_INTERNAL_PORT=9000
MINIO_USE_SSL=false
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin123
MINIO_BUCKET=example
MINIO_PUBLIC_BASE_URL=http://localhost:9000/example
```

`ACCESS_KEY` / `SECRET_KEY` باید با `MINIO_ROOT_*` داخل `dev/.env` یکی باشند.

### ۴. در صورت نیاز — اعمال دستی policy

```bash
cd ..
MINIO_ENV_FILE=./dev/.env ./scripts/setup-public-policy.sh
```

### ۵. تست

```bash
curl -I "http://localhost:9000/$(grep MINIO_BUCKET dev/.env | cut -d= -f2)/public/..."
```

انتظار برای فایل موجود زیر `public/`: وضعیت `200`.
