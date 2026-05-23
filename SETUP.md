# Покроковий план (роби по одному кроку!)

Ти зараз на **Кроці 1**. Коли закінчиш — напиши в чат: **«Крок 1 готовий»**, і перейдемо до Кроку 2.

---

## Загальна карта (що буде в кінці)

```
Телефон (Telegram)
       ↓
  Mini App відкриває сайт на Render
       ↓
  Сайт (index.html) читає/пише дані в Supabase
       ↓
  Фото лежать у Supabase Storage (не в localStorage)
```

| Крок | Що робимо | Де |
|------|-----------|-----|
| 0 | ✅ Проєкт на комп'ютері | `Projects\pnu-dorm-miniapp` |
| **1** | **GitHub — залити код** | github.com |
| 2 | Supabase — база + фото | supabase.com |
| 3 | Підключити сайт до Supabase | код у Cursor |
| 4 | Render — опублікувати сайт | render.com |
| 5 | Telegram Bot + Mini App | @BotFather |
| 6 | Перевірка на телефоні | Telegram |

---

## Крок 1 — GitHub (зараз)

### 1.0. Встановити Git (якщо ще немає)

У PowerShell команда `git` не знайдена — спочатку встанови Git:

1. Відкрий https://git-scm.com/download/win  
2. Завантаж і встанови (усі кроки — **Next**, нічого не міняй).  
3. **Закрий і знову відкрий** Cursor / PowerShell.  
4. Перевір:

```powershell
git --version
```

Має показати щось на кшталт `git version 2.x.x`.

### 1.1. Акаунт GitHub

1. Відкрий https://github.com/signup  
2. Зареєструйся (email + пароль).  
3. Підтверди email, якщо попросить.

### 1.2. Новий репозиторій

1. Увійди на https://github.com  
2. Праворуч зверху **+** → **New repository**  
3. Заповни:
   - **Repository name:** `pnu-dorm-miniapp` (як у нас на диску)
   - **Description:** `Гуртожиток №1 ПНУ — Telegram Mini App`
   - **Public** — так (для Render безкоштовно простіше)
   - **НЕ** став галочку "Add a README" (у нас вже є файли)
4. Натисни **Create repository**.

### 1.3. Завантажити код з комп'ютера

На сторінці нового репо GitHub покаже команди. У **PowerShell** виконай (один раз підстав **свій** логін замість `ТВІЙ_ЛОГІН`):

```powershell
cd C:\Users\User\Projects\pnu-dorm-miniapp

git add .
git commit -m "Початкова версія: сайт гуртожитку (localStorage)"

git branch -M main
git remote add origin https://github.com/ТВІЙ_ЛОГІН/pnu-dorm-miniapp.git
git push -u origin main
```

**Якщо GitHub попросить логін/пароль:** пароль не підходить — потрібен **Personal Access Token**:
1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)  
2. Generate new token → права **repo**  
3. Скопіюй токен — встав як пароль при `git push`

### 1.4. Перевірка

1. Онови сторінку репозиторію на GitHub.  
2. Маєш бачити файли: `index.html`, `README.md`, `SETUP.md`, `.gitignore`.

### ✅ Крок 1 готовий, коли:

- Репозиторій відкривається в браузері  
- У ньому є `index.html`

---

## Крок 2 — Supabase (наступний, після «Крок 1 готовий»)

Створимо проєкт Supabase, таблиці під усі розділи сайту і bucket для фотографій. SQL-скрипт уже лежить у `supabase/schema.sql`.

---

## Крок 3 — Підключення сайту (після Supabase)

Замінимо `localStorage` на Supabase: усі бачать одні дані, фото — у Storage, не base64 у браузері.

---

## Крок 4 — Render

Static Site → підключити GitHub → URL типу `https://pnu-dorm-miniapp.onrender.com`

---

## Крок 5 — Telegram

1. @BotFather → `/newbot`  
2. `/newapp` або Menu Button → вставити URL з Render  
3. Відкрити бота на телефоні

---

## Допомога

Напиши в чат:
- **«Крок 1 готовий»** + посилання на репо  
- або **«застряг на …»** + скрін/текст помилки

Не поспішай — один крок = один раз усе зробив і перевірив.
