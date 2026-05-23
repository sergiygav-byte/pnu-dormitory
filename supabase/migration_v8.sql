-- Міграція v8: фото контактів, опитування (анонім/публічно, дата кінця), коментарі санітарки
-- Після v7

-- === Контакти: фото ===
ALTER TABLE leaders ADD COLUMN IF NOT EXISTS photo TEXT NOT NULL DEFAULT '';

DROP FUNCTION IF EXISTS admin_upsert_leader(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS admin_upsert_leader(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION admin_upsert_leader(
  p_password TEXT,
  p_id TEXT,
  p_role TEXT,
  p_name TEXT,
  p_phone TEXT,
  p_tg TEXT,
  p_room TEXT DEFAULT '',
  p_photo TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO leaders (id, role, name, phone, tg, room, photo)
  VALUES (p_id, p_role, p_name, COALESCE(p_phone, ''), COALESCE(p_tg, ''), COALESCE(p_room, ''), COALESCE(p_photo, ''))
  ON CONFLICT (id) DO UPDATE SET
    role = p_role,
    name = p_name,
    phone = p_phone,
    tg = p_tg,
    room = COALESCE(p_room, ''),
    photo = COALESCE(p_photo, '');
END;
$$;

GRANT EXECUTE ON FUNCTION admin_upsert_leader(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;

-- === Опитування: анонімність, дата кінця, сповіщення ===
ALTER TABLE polls ADD COLUMN IF NOT EXISTS anonymous BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE polls ADD COLUMN IF NOT EXISTS ends_at TIMESTAMPTZ;
ALTER TABLE polls ADD COLUMN IF NOT EXISTS end_notified BOOLEAN NOT NULL DEFAULT false;

ALTER TABLE poll_votes ADD COLUMN IF NOT EXISTS voter_label TEXT NOT NULL DEFAULT '';

DROP FUNCTION IF EXISTS admin_create_poll(TEXT, TEXT, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION admin_create_poll(
  p_password TEXT,
  p_id TEXT,
  p_title TEXT,
  p_desc TEXT,
  p_options JSONB,
  p_anonymous BOOLEAN DEFAULT true,
  p_ends_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO polls (id, title, description, options, active, anonymous, ends_at, end_notified)
  VALUES (
    p_id, p_title, p_desc, p_options, true,
    COALESCE(p_anonymous, true),
    p_ends_at,
    false
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_create_poll(TEXT, TEXT, TEXT, TEXT, JSONB, BOOLEAN, TIMESTAMPTZ) TO anon, authenticated;

DROP FUNCTION IF EXISTS cast_poll_vote(TEXT, TEXT, INT);

CREATE OR REPLACE FUNCTION cast_poll_vote(
  p_poll_id TEXT,
  p_voter_tg_id TEXT,
  p_option_index INT,
  p_voter_label TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  opts JSONB;
  len INT;
  v_ends TIMESTAMPTZ;
BEGIN
  IF p_voter_tg_id IS NULL OR p_voter_tg_id = '' THEN
    RAISE EXCEPTION 'Потрібен Telegram-акаунт';
  END IF;
  SELECT options, ends_at INTO opts, v_ends
  FROM polls WHERE id = p_poll_id AND active = true;
  IF opts IS NULL THEN RAISE EXCEPTION 'Опитування не знайдено або закрите'; END IF;
  IF v_ends IS NOT NULL AND v_ends <= NOW() THEN
    RAISE EXCEPTION 'Голосування вже завершено';
  END IF;
  len := jsonb_array_length(opts);
  IF p_option_index < 0 OR p_option_index >= len THEN
    RAISE EXCEPTION 'Невірний варіант';
  END IF;
  INSERT INTO poll_votes (poll_id, voter_tg_id, option_index, voter_label, voted_at)
  VALUES (p_poll_id, p_voter_tg_id, p_option_index, COALESCE(NULLIF(trim(p_voter_label), ''), p_voter_tg_id), NOW())
  ON CONFLICT (poll_id, voter_tg_id) DO UPDATE SET
    option_index = p_option_index,
    voter_label = COALESCE(NULLIF(trim(p_voter_label), ''), p_voter_tg_id),
    voted_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION cast_poll_vote(TEXT, TEXT, INT, TEXT) TO anon, authenticated;

-- Закрити прострочені опитування; повернути JSON для push
CREATE OR REPLACE FUNCTION close_expired_polls()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result JSON;
BEGIN
  UPDATE polls
  SET active = false
  WHERE active = true
    AND ends_at IS NOT NULL
    AND ends_at <= NOW();

  SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json) INTO v_result
  FROM (
    SELECT
      p.id,
      p.title,
      p.anonymous,
      p.options,
      (
        SELECT COALESCE(json_agg(json_build_object(
          'option_index', pv.option_index,
          'voter_tg_id', pv.voter_tg_id,
          'voter_label', pv.voter_label
        )), '[]'::json)
        FROM poll_votes pv
        WHERE pv.poll_id = p.id
      ) AS votes
    FROM polls p
    WHERE p.active = false
      AND p.ends_at IS NOT NULL
      AND p.ends_at <= NOW()
      AND p.end_notified = false
  ) t;

  UPDATE polls SET end_notified = true
  WHERE active = false
    AND ends_at IS NOT NULL
    AND ends_at <= NOW()
    AND end_notified = false;

  RETURN COALESCE(v_result, '[]'::json);
END;
$$;

GRANT EXECUTE ON FUNCTION close_expired_polls() TO anon, authenticated;

-- === Коментарі про санітарку ===
CREATE TABLE IF NOT EXISTS sanitary_comments (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL,
  author_name TEXT NOT NULL DEFAULT '',
  author_telegram_id TEXT,
  is_admin BOOLEAN NOT NULL DEFAULT false,
  parent_id TEXT REFERENCES sanitary_comments(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sanitary_comments_parent ON sanitary_comments (parent_id);
CREATE INDEX IF NOT EXISTS idx_sanitary_comments_created ON sanitary_comments (created_at ASC);

ALTER TABLE sanitary_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_sanitary_top" ON sanitary_comments;
CREATE POLICY "public_read_sanitary_top" ON sanitary_comments
  FOR SELECT USING (parent_id IS NULL);

-- Прямий INSERT/DELETE заборонено — лише RPC

CREATE OR REPLACE FUNCTION insert_sanitary_comment_admin(
  p_password TEXT,
  p_id TEXT,
  p_content TEXT,
  p_author_name TEXT DEFAULT 'Адміністратор'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  IF trim(COALESCE(p_content, '')) = '' THEN RAISE EXCEPTION 'Порожній коментар'; END IF;
  INSERT INTO sanitary_comments (id, content, author_name, author_telegram_id, is_admin, parent_id)
  VALUES (p_id, trim(p_content), COALESCE(NULLIF(trim(p_author_name), ''), 'Адміністратор'), NULL, true, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION insert_sanitary_comment_reply(
  p_id TEXT,
  p_content TEXT,
  p_parent_id TEXT,
  p_author_name TEXT,
  p_author_tg_id TEXT,
  p_is_admin BOOLEAN DEFAULT false
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF trim(COALESCE(p_content, '')) = '' THEN RAISE EXCEPTION 'Порожній коментар'; END IF;
  IF p_parent_id IS NULL OR p_parent_id = '' THEN
    RAISE EXCEPTION 'Відповідь лише на існуючий коментар';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM sanitary_comments WHERE id = p_parent_id AND parent_id IS NULL) THEN
    RAISE EXCEPTION 'Коментар для відповіді не знайдено';
  END IF;
  IF COALESCE(p_is_admin, false) = false AND (p_author_tg_id IS NULL OR trim(p_author_tg_id) = '') THEN
    RAISE EXCEPTION 'Відкрийте додаток у Telegram';
  END IF;
  INSERT INTO sanitary_comments (id, content, author_name, author_telegram_id, is_admin, parent_id)
  VALUES (
    p_id, trim(p_content),
    COALESCE(NULLIF(trim(p_author_name), ''), 'Користувач'),
    NULLIF(trim(p_author_tg_id), ''),
    COALESCE(p_is_admin, false),
    p_parent_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION admin_list_sanitary_replies(p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.created_at ASC), '[]'::json)
    FROM (
      SELECT id, content, author_name, author_telegram_id, is_admin, parent_id, created_at
      FROM sanitary_comments
      WHERE parent_id IS NOT NULL
    ) t
  );
END;
$$;

CREATE OR REPLACE FUNCTION admin_delete_sanitary_comment(p_password TEXT, p_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  DELETE FROM sanitary_comments WHERE id = p_id OR parent_id = p_id;
END;
$$;

GRANT EXECUTE ON FUNCTION insert_sanitary_comment_admin(TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION insert_sanitary_comment_reply(TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_list_sanitary_replies(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_sanitary_comment(TEXT, TEXT) TO anon, authenticated;
