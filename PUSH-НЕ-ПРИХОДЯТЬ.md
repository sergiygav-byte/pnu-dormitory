# Сповіщення не приходять — перевірка

Додаток працює, push — **окремий ланцюжок**. Нижче 5 причин по порядку.

---

## 1. CORS (найчастіше) — виправлено в коді

Сайт на **GitHub Pages** викликає **Vercel** `/api/notify`. Браузер міг **блокувати** запит.

**Що зробити:** залити оновлений `api/notify.js` і **Redeploy** на Vercel:

```powershell
cd C:\Users\User\Projects\pnu-dorm-miniapp
git add api/notify.js database.js PUSH-НЕ-ПРИХОДЯТЬ.md
git commit -m "Fix push: CORS для notify API"
git push
```

Потім Vercel → Deployments → дочекатись зеленого статусу.

---

## 2. Секрет не збігається

| Де | Має бути однаково |
|----|-------------------|
| `config.public.js` → `NOTIFY_SECRET` | `admin1177` (у вас зараз) |
| Vercel → Environment → `NOTIFY_SECRET` | **той самий** текст |

Після зміни на Vercel — **Redeploy**.

---

## 3. Ніхто не підписаний на бота

Push йде **тільки** тим, хто натиснув **/start** у [@pnu_dorm_bot](https://t.me/pnu_dorm_bot).

**Перевірка в Supabase:** Table Editor → `bot_subscribers` — має бути хоча б 1 рядок з вашим `chat_id`.

Якщо порожньо — на телефоні відкрийте бота → **Start** ще раз.

---

## 4. Vercel — змінні середовища

На Vercel мають бути **всі 5**:

- `BOT_TOKEN`
- `SUPABASE_URL` = `https://lsoieljknndrtsyeolbd.supabase.co`
- `SUPABASE_ANON_KEY` = (anon з Supabase)
- `NOTIFY_SECRET` = як у `config.public.js`
- `WEBAPP_URL` = `https://sergiygav-byte.github.io/pnu-dorm-miniapp/index.html`

---

## 5. Тест вручну (1 хв)

У PowerShell (підставте свій секрет):

```powershell
$body = '{"title":"Тест","message":"Перевірка push"}'
Invoke-RestMethod -Uri "https://pnu-dorm-miniapp.vercel.app/api/notify" -Method POST -Headers @{"X-Notify-Secret"="admin1177"; "Content-Type"="application/json"} -Body $body
```

**Очікувана відповідь:**

```json
{ "ok": true, "sent": 1, "total": 1 }
```

| Відповідь | Що робити |
|-----------|-----------|
| `"total": 0` | Натисніть /start у боті |
| `Unauthorized` | Виправити NOTIFY_SECRET на Vercel |
| `BOT_TOKEN missing` | Додати BOT_TOKEN на Vercel |
| Помилка мережі | Redeploy Vercel після push CORS-fix |

Якщо тест у PowerShell **працює**, а з додатку ні — оновіть GitHub Pages (`git push` з `config.public.js`).

---

## ZIP (2) — чи все ок?

Архів `pnu-dorm-miniapp-main (2).zip` = той самий проєкт, є `config.public.js`.  
Працюйте в `C:\Users\User\Projects\pnu-dorm-miniapp`, ZIP не потрібен.

---

Після redeploy напишіть результат тесту PowerShell (`sent` і `total`).
