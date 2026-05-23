-- Міграція v2: голосування, Telegram-автор скарги, вкладення, push-підписники
-- Supabase → SQL Editor → Run (після schema.sql)

-- Скарги: хто подав + вкладення (фото / відео / PDF)
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS telegram_user_id TEXT;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS telegram_username TEXT;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS telegram_display_name TEXT;
ALTER TABLE complaints ADD COLUMN IF NOT EXISTS attachments JSONB NOT NULL DEFAULT '[]'::jsonb;

-- Голосування
CREATE TABLE IF NOT EXISTS polls (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  options JSONB NOT NULL DEFAULT '[]'::jsonb,
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS poll_votes (
  poll_id TEXT NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
  voter_tg_id TEXT NOT NULL,
  option_index INT NOT NULL,
  voted_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (poll_id, voter_tg_id)
);

-- Підписники push (зберігаються при /start у боті)
CREATE TABLE IF NOT EXISTS bot_subscribers (
  chat_id BIGINT PRIMARY KEY,
  telegram_user_id TEXT,
  username TEXT,
  first_name TEXT,
  subscribed_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO app_settings (key, value)
VALUES ('notify_secret', 'change_me_notify_secret')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE bot_subscribers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_polls" ON polls FOR SELECT USING (true);
CREATE POLICY "public_read_poll_votes" ON poll_votes FOR SELECT USING (true);
CREATE POLICY "public_read_subscribers" ON bot_subscribers FOR SELECT USING (true);
CREATE POLICY "public_upsert_subscribers" ON bot_subscribers FOR INSERT WITH CHECK (true);
CREATE POLICY "public_update_subscribers" ON bot_subscribers FOR UPDATE USING (true);

-- Публічна заявка з Telegram-даними
CREATE OR REPLACE FUNCTION insert_complaint_public(
  p_id TEXT,
  p_subject TEXT,
  p_desc TEXT,
  p_attachments JSONB,
  p_tg_id TEXT,
  p_tg_username TEXT,
  p_tg_name TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO complaints (
    id, subject, description, status, date,
    photos_list, attachments,
    telegram_user_id, telegram_username, telegram_display_name
  ) VALUES (
    p_id, p_subject, p_desc, 'В обробці ⏳', to_char(NOW(), 'YYYY-MM-DD'),
    '[]'::jsonb, COALESCE(p_attachments, '[]'::jsonb),
    NULLIF(p_tg_id, ''), NULLIF(p_tg_username, ''), NULLIF(p_tg_name, '')
  );
END;
$$;

CREATE OR REPLACE FUNCTION admin_update_complaint(
  p_password TEXT, p_id TEXT, p_subject TEXT, p_desc TEXT, p_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  UPDATE complaints
  SET subject = p_subject, description = p_desc, status = p_status
  WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION admin_create_poll(
  p_password TEXT,
  p_id TEXT,
  p_title TEXT,
  p_desc TEXT,
  p_options JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO polls (id, title, description, options, active)
  VALUES (p_id, p_title, p_desc, p_options, true);
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_poll_active(
  p_password TEXT, p_id TEXT, p_active BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  UPDATE polls SET active = p_active WHERE id = p_id;
END;
$$;

CREATE OR REPLACE FUNCTION cast_poll_vote(
  p_poll_id TEXT,
  p_voter_tg_id TEXT,
  p_option_index INT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  opts JSONB;
  len INT;
BEGIN
  IF p_voter_tg_id IS NULL OR p_voter_tg_id = '' THEN
    RAISE EXCEPTION 'Потрібен Telegram-акаунт';
  END IF;
  SELECT options INTO opts FROM polls WHERE id = p_poll_id AND active = true;
  IF opts IS NULL THEN RAISE EXCEPTION 'Опитування не знайдено або закрите'; END IF;
  len := jsonb_array_length(opts);
  IF p_option_index < 0 OR p_option_index >= len THEN
    RAISE EXCEPTION 'Невірний варіант';
  END IF;
  INSERT INTO poll_votes (poll_id, voter_tg_id, option_index)
  VALUES (p_poll_id, p_voter_tg_id, p_option_index)
  ON CONFLICT (poll_id, voter_tg_id) DO UPDATE SET option_index = p_option_index, voted_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION register_bot_subscriber(
  p_chat_id BIGINT,
  p_tg_id TEXT,
  p_username TEXT,
  p_first_name TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO bot_subscribers (chat_id, telegram_user_id, username, first_name)
  VALUES (p_chat_id, p_tg_id, p_username, p_first_name)
  ON CONFLICT (chat_id) DO UPDATE SET
    telegram_user_id = EXCLUDED.telegram_user_id,
    username = EXCLUDED.username,
    first_name = EXCLUDED.first_name,
    subscribed_at = NOW();
END;
$$;

-- Оновити видалення: додати polls
CREATE OR REPLACE FUNCTION admin_delete_row(p_password TEXT, p_table TEXT, p_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;
  CASE p_table
    WHEN 'goals' THEN DELETE FROM goals WHERE id = p_id;
    WHEN 'payments' THEN DELETE FROM payments WHERE id = p_id;
    WHEN 'expenses' THEN DELETE FROM expenses WHERE id = p_id;
    WHEN 'events' THEN DELETE FROM events WHERE id = p_id;
    WHEN 'duty' THEN DELETE FROM duty WHERE id = p_id;
    WHEN 'leaders' THEN DELETE FROM leaders WHERE id = p_id;
    WHEN 'complaints' THEN DELETE FROM complaints WHERE id = p_id;
    WHEN 'polls' THEN DELETE FROM polls WHERE id = p_id;
    ELSE RAISE EXCEPTION 'Невідома таблиця';
  END CASE;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_complaint_public(TEXT,TEXT,TEXT,JSONB,TEXT,TEXT,TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_create_poll(TEXT,TEXT,TEXT,TEXT,JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_set_poll_active(TEXT,TEXT,BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION cast_poll_vote(TEXT,TEXT,INT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION register_bot_subscriber(BIGINT,TEXT,TEXT,TEXT) TO anon, authenticated;
