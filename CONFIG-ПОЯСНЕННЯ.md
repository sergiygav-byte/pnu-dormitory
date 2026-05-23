# config.js — пояснення для GitHub Pages (простими словами)

## Проблема одним реченням

Сайт на GitHub Pages — це файли з репозиторію.  
Файл `config.js` **не потрапляв** у репозиторій (він у `.gitignore`).  
Тому в Telegram додаток **не бачив** ключі Supabase → «помилка бази».

## Рішення (вже зроблено в коді)

| Файл | Куди | Навіщо |
|------|------|--------|
| **config.public.js** | ✅ заливається в GitHub | Ключі для сайту в інтернеті |
| **config.js** | ❌ лише на вашому ПК | Для локальних тестів (не обов’язковий) |

Сайт тепер підключає **`config.public.js`**, не `config.js`.

## Що зробити ВАМ (2 дії)

### 1. Залити на GitHub

У PowerShell:

```powershell
cd C:\Users\User\Projects\pnu-dorm-miniapp
git add config.public.js index.html CONFIG-ПОЯСНЕННЯ.md
git commit -m "Додано config.public.js для GitHub Pages"
git push
```

### 2. Зачекати 2–3 хвилини

Відкрити на телефоні (через бота):

https://sergiygav-byte.github.io/pnu-dorm-miniapp/index.html

Має завантажитись **без** «Помилка підключення до бази».

---

## Безпека

- **anon key** у `config.public.js` — нормально, він для браузера.
- **Ніколи** не публікуйте **service_role** key.
- `NOTIFY_SECRET` у браузері все одно видно тим, хто відкриє сайт; тримайте репозиторій **Private**, якщо хвилюєтесь.

---

## Якщо зміните ключі в Supabase або Vercel

Відредагуйте **config.public.js** → знову `git add` → `commit` → `push`.

Локальний `config.js` для GitHub Pages **більше не потрібен**.
