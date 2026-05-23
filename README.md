# Гуртожиток №1 ПНУ — Telegram Mini App

Цифровий додаток для мешканців: бюджет, оголошення, чергування, скарги з **фото**, контакти адміністрації.

**Дані зберігаються в хмарі (Supabase)** — працює 24/7, не залежить від увімкненого ПК.

## Безкоштовний стек

| Що | Сервіс | Безкоштовно |
|----|--------|-------------|
| База даних + API | [Supabase](https://supabase.com) | Так |
| Фото (сховище) | Supabase Storage | 1 GB |
| Сайт Mini App | [GitHub Pages](https://pages.github.com) або [Cloudflare Pages](https://pages.cloudflare.com) | Так |
| Telegram | [@BotFather](https://t.me/BotFather) | Так |

---

## 1. Supabase (база + фото)

1. Зареєструйтесь на [supabase.com](https://supabase.com) → **New project**.
2. Відкрийте **SQL Editor** → вставте весь файл `supabase/schema.sql` → **Run**.
3. **Storage** → переконайтесь, що є bucket `dorm-photos` (Public). Якщо SQL не створив — створіть вручну, Public = увімкнено.
4. **Project Settings → API** — скопіюйте:
   - Project URL
   - `anon` `public` key
5. У проєкті скопіюйте `config.example.js` → `config.js` і вставте URL та ключ.

### Змінити пароль адміна

У Supabase → **Table Editor** → `app_settings` → рядок `admin_password` → змініть `value` (за замовчуванням у SQL: `admin777`).

---

## 2. Публікація сайту (GitHub Pages)

```bash
cd c:\Users\User\Projects\pnu-dorm-miniapp
git init
git add .
git commit -m "PNU dorm mini app with Supabase"
```

Створіть репозиторій на GitHub, запуште. У репозиторії: **Settings → Pages → Source: main branch / root**.

URL буде: `https://ВАШ_ЛОГІН.github.io/НАЗВА_РЕПО/index.html`

> `config.js` у `.gitignore` — на GitHub Pages додайте ключі через окремий deploy (або тимчасово закомітьте config.js лише з anon-ключем; **не** публікуйте service_role key).

**Альтернатива:** Cloudflare Pages — підключіть репозиторій, build command порожній, output = `/`.

---

## 3. Telegram Mini App

1. `/mybots` → **Bot Settings** → **Menu Button** → URL GitHub Pages (`.../index.html`).
2. Відкрийте бота → кнопка меню внизу → додаток.

**Кнопка Start у чаті** (вітання + кнопка додатку): див. **`BOT-START.md`** (Vercel webhook, ~10 хв).

### Локальна перевірка

Відкрийте `index.html` через локальний сервер (CORS для Supabase):

```bash
npx serve .
```

Або розширення Live Server у VS Code.

---

## Структура проєкту

```
index.html          — UI (ваш оригінальний дизайн)
js/database.js      — робота з Supabase
config.js           — ключі (не комітити в git)
supabase/schema.sql — таблиці, RLS, RPC, початкові дані
```

## Що змінилось порівняно з localStorage

- Усі мешканці бачать **одні й ті самі** дані з хмари.
- Фото скарг і витрат — у **Storage** (посилання), не base64 у браузері.
- Адмін-дії перевіряються на сервері (RPC + пароль у `app_settings`).
- Сесія адміна в `localStorage` лише для зручності; пароль перевіряється в Supabase.

## Обмеження безкоштовного тарифу Supabase

- ~500 MB БД, ~1 GB файлів — для гуртожитку зазвичай достатньо.
- Проєкт «засинає» після неактивності — перше відкриття може бути на 1–2 с повільніше.

---

Питання / доопрацювання — пишіть у чат розробки.
