-- Міграція v3: коментарі до скарг, журнал відвідувань бота, кімната в контактах
-- Supabase → SQL Editor → Run (після schema.sql та migration_v2.sql)

-- 1. Коментарі (тікет / чат під скаргою)
CREATE TABLE IF NOT EXISTS complaint_comments (
  id TEXT PRIMARY KEY,
  complaint_id TEXT NOT NULL REFERENCES complaints(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  author_type TEXT NOT NULL DEFAULT 'admin',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_complaint_comments_complaint ON complaint_comments(complaint_id, created_at);

-- 2. Контакти: № кімнати
ALTER TABLE leaders ADD COLUMN IF NOT EXISTS room TEXT NOT NULL DEFAULT '';

-- 3. Журнал відвідувань бота (лише для адміна через RPC)
ALTER TABLE bot_subscribers ADD COLUMN IF NOT EXISTS last_name TEXT;
ALTER TABLE bot_subscribers ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;
ALTER TABLE bot_subscribers ADD COLUMN IF NOT EXISTS last_webapp_at TIMESTAMPTZ;
ALTER TABLE bot_subscribers ADD COLUMN IF NOT EXISTS visit_count INT NOT NULL DEFAULT 0;

-- Оновити реєстрацію /start
CREATE OR REPLACE FUNCTION register_bot_subscriber(
  p_chat_id BIGINT,
  p_tg_id TEXT,
  p_username TEXT,
  p_first_name TEXT,
  p_last_name TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO bot_subscribers (chat_id, telegram_user_id, username, first_name, last_name, last_seen_at, visit_count)
  VALUES (p_chat_id, p_tg_id, p_username, p_first_name, COALESCE(p_last_name, ''), NOW(), 1)
  ON CONFLICT (chat_id) DO UPDATE SET
    telegram_user_id = EXCLUDED.telegram_user_id,
    username = EXCLUDED.username,
    first_name = EXCLUDED.first_name,
    last_name = COALESCE(NULLIF(EXCLUDED.last_name, ''), bot_subscribers.last_name),
    last_seen_at = NOW(),
    visit_count = COALESCE(bot_subscribers.visit_count, 0) + 1,
    subscribed_at = COALESCE(bot_subscribers.subscribed_at, NOW());
END;
$$;

-- Відкриття Mini App (трекінг ніка в Telegram)
CREATE OR REPLACE FUNCTION track_webapp_visit(
  p_tg_id TEXT,
  p_username TEXT,
  p_first_name TEXT,
  p_last_name TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_tg_id IS NULL OR p_tg_id = '' THEN
    RETURN;
  END IF;
  UPDATE bot_subscribers SET
    username = COALESCE(NULLIF(p_username, ''), username),
    first_name = COALESCE(NULLIF(p_first_name, ''), first_name),
    last_name = COALESCE(NULLIF(p_last_name, ''), last_name),
    last_webapp_at = NOW()
  WHERE telegram_user_id = p_tg_id;
END;
$$;

-- Список відвідувачів — тільки адмін
CREATE OR REPLACE FUNCTION admin_list_bot_visitors(p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;

  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.last_activity DESC NULLS LAST), '[]'::json)
    FROM (
      SELECT
        chat_id,
        telegram_user_id,
        username,
        first_name,
        last_name,
        subscribed_at,
        last_seen_at,
        last_webapp_at,
        visit_count,
        GREATEST(COALESCE(last_seen_at, '1970-01-01'::timestamptz), COALESCE(last_webapp_at, '1970-01-01'::timestamptz)) AS last_activity
      FROM bot_subscribers
      WHERE telegram_user_id IS NOT NULL AND telegram_user_id <> ''
    ) t
  );
END;
$$;

-- Коментар адміна під скаргою
CREATE OR REPLACE FUNCTION admin_add_complaint_comment(
  p_password TEXT,
  p_complaint_id TEXT,
  p_body TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id TEXT;
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;
  IF p_body IS NULL OR trim(p_body) = '' THEN
    RAISE EXCEPTION 'Текст коментаря порожній';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM complaints WHERE id = p_complaint_id) THEN
    RAISE EXCEPTION 'Звернення не знайдено';
  END IF;

  v_id := 'cc_' || floor(extract(epoch from now()) * 1000)::text;
  INSERT INTO complaint_comments (id, complaint_id, body, author_type)
  VALUES (v_id, p_complaint_id, trim(p_body), 'admin');

  RETURN v_id;
END;
$$;

-- Контакт з кімнатою (прибрати стару сигнатуру без room)
DROP FUNCTION IF EXISTS admin_upsert_leader(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION admin_upsert_leader(
  p_password TEXT,
  p_id TEXT,
  p_role TEXT,
  p_name TEXT,
  p_phone TEXT,
  p_tg TEXT,
  p_room TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO leaders (id, role, name, phone, tg, room)
  VALUES (p_id, p_role, p_name, COALESCE(p_phone, ''), COALESCE(p_tg, ''), COALESCE(p_room, ''))
  ON CONFLICT (id) DO UPDATE SET
    role = p_role,
    name = p_name,
    phone = p_phone,
    tg = p_tg,
    room = COALESCE(p_room, '');
END;
$$;

-- RLS для коментарів
ALTER TABLE complaint_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_complaint_comments" ON complaint_comments;
CREATE POLICY "public_read_complaint_comments" ON complaint_comments FOR SELECT USING (true);

GRANT EXECUTE ON FUNCTION track_webapp_visit(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_list_bot_visitors(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_add_complaint_comment(TEXT, TEXT, TEXT) TO anon, authenticated;
