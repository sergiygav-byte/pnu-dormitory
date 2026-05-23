# Міграція v5 — тестовий push, статистика, санітарка

## Нові можливості

| Функція | Опис |
|---------|------|
| **Тестовий push** | Режим `test` — сповіщення лише на Telegram ID адміна |
| **Виключення адміна** | У режимі `all` адмін не отримує масові push |
| **Статистика** | Унікальні користувачі та відкриття Mini App за 7 днів |
| **Санітарка** | Щодня о ~09:00 (Kyiv) push про чергування **на завтра** |

## 1. Supabase

SQL Editor → весь файл **`supabase/migration_v5.sql`** → **Run**.

## 2. Vercel

**Environment Variables** — додайте:

| Змінна | Опис |
|--------|------|
| `CRON_SECRET` | Довгий випадковий пароль (наприклад `openssl rand -hex 32`) |

Існуючі: `BOT_TOKEN`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `NOTIFY_SECRET`, `WEBAPP_URL`.

**Deployments → Redeploy** (оновлені `api/notify.js`, `api/cron-duty-reminder.js`, `vercel.json`).

Cron: `0 7 * * *` UTC ≈ 09:00 за Києвом (літо).

## 3. GitHub Pages

```powershell
cd C:\Users\User\Projects\pnu-dorm-miniapp
git add index.html database.js api/ supabase/migration_v5.sql vercel.json SETUP-MIGRATION-V5.md
git commit -m "v5: тестовий push, статистика, нагадування санітарки"
git push
```

## 4. Налаштування в додатку

**Інфо** → вхід адміном → блок **«Користувачі бота»**:

1. **Режим push:** `Тест — лише адміну` → **Мій ID** → **Зберегти**.
2. Додайте тестове оголошення — push має прийти **лише вам**.
3. Увімкніть **Не надсилати push мені** + режим `Усім` — масові push вам не підуть.
4. **Автонагадування санітарка** — увімкнено; у розкладі має бути запис на **завтрашню** дату.

## 5. Ручна перевірка cron (опційно)

```powershell
$secret = "ВАШ_CRON_SECRET"
Invoke-RestMethod -Uri "https://pnu-dorm-miniapp.vercel.app/api/cron-duty-reminder" -Headers @{ Authorization = "Bearer $secret" }
```

Поверне `skipped` або надішле нагадування, якщо завтра є чергування.
