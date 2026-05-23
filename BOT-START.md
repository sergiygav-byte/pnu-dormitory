# Кнопка Start у боті @pnu_dorm_bot

Щоб бот **відповідав у чаті** на `/start`, потрібен маленький сервер (webhook). Сайт на GitHub Pages цього не вміє — використовуємо **Vercel** (безкоштовно).

---

## Крок 1. Токен бота

1. [@BotFather](https://t.me/BotFather) → `/mybots` → **@pnu_dorm_bot**
2. **API Token** → скопіюйте токен (вигляду `7123456789:AAH...`)
3. **Нікому не показуйте** токен у чатах і не викладайте в публічний GitHub.

---

## Крок 2. Vercel

1. [vercel.com](https://vercel.com) → увійти через **GitHub**
2. **Add New Project** → імпортувати репозиторій `pnu-dorm-miniapp`
3. **Environment Variables**:
   - `BOT_TOKEN` = ваш токен з BotFather
   - `WEBAPP_URL` = `https://sergiygav-byte.github.io/pnu-dorm-miniapp/index.html` (можна не додавати — є за замовчуванням)
4. **Deploy**

Після деплою буде URL, наприклад:
```
https://pnu-dorm-miniapp.vercel.app
```

Перевірка в браузері:
```
https://ВАШ-ПРОЄКТ.vercel.app/api/webhook
```
Має показати JSON з `"ok": true`.

---

## Крок 3. Підключити webhook до Telegram

У браузері відкрийте (підставте **СВІЙ** токен і **СВІЙ** Vercel-URL):

```
https://api.telegram.org/botВАШ_ТОКЕН/setWebhook?url=https://ВАШ-ПРОЄКТ.vercel.app/api/webhook
```

У відповіді має бути: `"ok":true`.

---

## Крок 4. Команди в BotFather

У BotFather надішліть:

```
/setcommands
```

→ оберіть **@pnu_dorm_bot** → вставте:

```
start - Відкрити додаток гуртожитку
help - Довідка
```

---

## Крок 5. Перевірка

1. Відкрийте [@pnu_dorm_bot](https://t.me/pnu_dorm_bot) на телефоні
2. Натисніть **Start** (або надішліть `/start`)
3. Має прийти вітання + кнопка **«Відкрити гуртожиток»**
4. Кнопка відкриває Mini App

---

## Якщо Start мовчить

| Проблема | Рішення |
|----------|---------|
| Немає відповіді | Перевірте `setWebhook` і `BOT_TOKEN` на Vercel |
| Помилка webhook | Vercel → Deployments → Logs → `api/webhook` |
| Кнопка не відкриває сайт | Перевірте `WEBAPP_URL` і Menu Button в BotFather |

Видалити webhook (якщо треба скинути):
```
https://api.telegram.org/botВАШ_ТОКЕН/deleteWebhook
```

---

## Файли в проєкті

- `api/webhook.js` — обробка `/start` і `/help`
- Mini App як і раніше на **GitHub Pages** + **Supabase**
