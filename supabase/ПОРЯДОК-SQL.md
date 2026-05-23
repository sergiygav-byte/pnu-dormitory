# Який SQL файл запускати?

Відкрийте **Supabase → SQL Editor** і виконайте файли **з папки цього проєкту** (`supabase/`).

## Варіант А — база вже була (найчастіше у вас)

| Порядок | Файл | Коли |
|---------|------|------|
| 1 | `migration_v2.sql` | Якщо ще не запускали (опитування, push-підписники) |
| 2 | `migration_v3.sql` | Коментарі, кімната, журнал бота |
| 3 | `migration_v4.sql` | Вимкнення push, відвідувачі Mini App |
| 4 | `migration_v5.sql` | (якщо ще не було) |
| 5 | `migration_v6.sql` | Простий push, онлайн, санітарка |
| 6 | `migration_v7.sql` | Блокування користувачів, нагадування санітарки |
| 7 | `migration_v8.sql` | Фото контактів, опитування, коментарі санітарки |
| 8 | `migration_v9.sql` | **Завжди зараз** — коментарі для всіх, режим оновлення |

Якщо v8 вже був — лише **migration_v9.sql**.

## Варіант Б — повністю нова база

| Порядок | Файл |
|---------|------|
| 1 | `schema.sql` |
| 2 | `migration_v2.sql` |
| 3 | `migration_v3.sql` |
| 4 | `migration_v4.sql` |
| 5 | `migration_v5.sql` |
| 6 | `migration_v6.sql` |
| 7 | `migration_v7.sql` |
| 8 | `migration_v8.sql` |

## Після запуску

- Table Editor → є `complaint_comments`, `sanitary_comments`
- `leaders` → колонки `room`, `photo`
- `polls` → колонки `anonymous`, `ends_at`
- `app_settings` → змінити `admin_password`

Повна інструкція: **`ПОЧАТОК.md`** у корені проєкту.
