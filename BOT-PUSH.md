# Push-сповіщення в Telegram

## 1. Supabase

Виконайте `supabase/migration_v2.sql` у SQL Editor.

У таблиці `app_settings` змініть `notify_secret` на свій довгий пароль.

## 2. Vercel (змінні середовища)

| Змінна | Значення |
|--------|----------|
| `BOT_TOKEN` | з BotFather |
| `SUPABASE_URL` | ваш Project URL |
| `SUPABASE_ANON_KEY` | anon key |
| `NOTIFY_SECRET` | той самий, що в `app_settings.notify_secret` |
| `WEBAPP_URL` | GitHub Pages URL |

Після деплою URL notify: `https://ВАШ.vercel.app/api/notify`

## 3. config.js (на GitHub Pages)

```js
window.NOTIFY_API_URL = 'https://ВАШ.vercel.app/api/notify';
window.NOTIFY_SECRET = 'ваш_notify_secret';
```

## 4. Підписники

Кожен мешканець має натиснути **/start** у [@pnu_dorm_bot](https://t.me/pnu_dorm_bot) — тоді потрапляє в `bot_subscribers`.

## 5. Коли приходить push

Усім підписникам бота (після `/start`):

- Нова **скарга**
- **Відповідь адміна** на скаргу — окремо **автору** заявки (якщо подав з Mini App)
- Нове **опитування** / опитування **закрито**
- Нове **оголошення**
- Новий **фінансовий звіт** (витрата)
- Новий запис **внеску**
- Нова **ціль збору**
- Призначене **чергування**

> Потрібна міграція `supabase/migration_v3.sql` — див. `SETUP-MIGRATION-V3.md`

## 6. Перевірка

Відкрийте в браузері (підставте секрет):

```text
POST https://ВАШ.vercel.app/api/notify
Header: X-Notify-Secret: ваш_секрет
Body: {"title":"Тест","message":"Перевірка push"}
```

Або надішліть скаргу з додатку — підписники мають отримати повідомлення.
