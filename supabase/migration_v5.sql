-- Міграція v5: тестовий push, виключення адміна, статистика, нагадування санітарки
-- Після schema.sql, migration_v2, v3, v4

-- Журнал відвідувань Mini App (для статистики)
CREATE TABLE IF NOT EXISTS webapp_visit_log (
  id BIGSERIAL PRIMARY KEY,
  telegram_user_id TEXT NOT NULL,
  visited_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_webapp_visit_log_at ON webapp_visit_log (visited_at DESC);
CREATE INDEX IF NOT EXISTS idx_webapp_visit_log_tg ON webapp_visit_log (telegram_user_id, visited_at DESC);

ALTER TABLE webapp_visit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "no_direct_webapp_visit_log" ON webapp_visit_log;

-- Налаштування push (міграція з bot_push_enabled)
INSERT INTO app_settings (key, value)
VALUES
  ('bot_push_mode', 'all'),
  ('admin_telegram_id', ''),
  ('admin_skip_push', 'true'),
  ('duty_reminders_enabled', 'true'),
  ('duty_reminder_last_date', '')
ON CONFLICT (key) DO NOTHING;

UPDATE app_settings SET key = 'bot_push_mode', value = 'off'
WHERE key = 'bot_push_enabled' AND value = 'false';

UPDATE app_settings SET key = 'bot_push_mode', value = 'all'
WHERE key = 'bot_push_enabled' AND value = 'true';

DELETE FROM app_settings WHERE key = 'bot_push_enabled';

CREATE OR REPLACE FUNCTION get_setting(p_key TEXT, p_default TEXT DEFAULT '')
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT value FROM app_settings WHERE key = p_key LIMIT 1), p_default);
$$;

CREATE OR REPLACE FUNCTION is_bot_push_enabled()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT get_setting('bot_push_mode', 'all') <> 'off';
$$;

CREATE OR REPLACE FUNCTION get_push_recipient_chat_ids(
  p_target_tg_id TEXT DEFAULT NULL,
  p_force_broadcast BOOLEAN DEFAULT FALSE
)
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT;
  v_admin_tg TEXT;
  v_skip TEXT;
  v_result JSON;
BEGIN
  v_mode := get_setting('bot_push_mode', 'all');
  v_admin_tg := trim(get_setting('admin_telegram_id', ''));
  v_skip := get_setting('admin_skip_push', 'true');

  IF v_mode = 'off' THEN
    RETURN '[]'::json;
  END IF;

  IF p_target_tg_id IS NOT NULL AND trim(p_target_tg_id) <> '' THEN
    SELECT COALESCE(json_agg(chat_id), '[]'::json) INTO v_result
    FROM bot_subscribers
    WHERE telegram_user_id = trim(p_target_tg_id) AND chat_id > 0;
    RETURN v_result;
  END IF;

  IF NOT p_force_broadcast AND v_mode = 'test' THEN
    IF v_admin_tg = '' THEN
      RETURN '[]'::json;
    END IF;
    SELECT COALESCE(json_agg(chat_id), '[]'::json) INTO v_result
    FROM bot_subscribers
    WHERE telegram_user_id = v_admin_tg AND chat_id > 0;
    RETURN v_result;
  END IF;

  SELECT COALESCE(json_agg(chat_id), '[]'::json) INTO v_result
  FROM bot_subscribers
  WHERE chat_id > 0
    AND telegram_user_id IS NOT NULL
    AND telegram_user_id <> ''
    AND (
      v_skip <> 'true'
      OR v_admin_tg = ''
      OR telegram_user_id <> v_admin_tg
    );

  RETURN v_result;
END;
$$;

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
DECLARE
  v_chat_id BIGINT;
  v_tg TEXT;
BEGIN
  IF p_tg_id IS NULL OR trim(p_tg_id) = '' THEN
    RETURN;
  END IF;
  v_tg := trim(p_tg_id);
  BEGIN
    v_chat_id := v_tg::BIGINT;
  EXCEPTION WHEN OTHERS THEN
    RETURN;
  END;

  INSERT INTO webapp_visit_log (telegram_user_id, visited_at)
  VALUES (v_tg, NOW());

  INSERT INTO bot_subscribers (
    chat_id, telegram_user_id, username, first_name, last_name,
    last_webapp_at, visit_count
  )
  VALUES (
    v_chat_id, v_tg,
    NULLIF(trim(p_username), ''),
    NULLIF(trim(p_first_name), ''),
    COALESCE(NULLIF(trim(p_last_name), ''), ''),
    NOW(), 0
  )
  ON CONFLICT (chat_id) DO UPDATE SET
    telegram_user_id = COALESCE(v_tg, bot_subscribers.telegram_user_id),
    username = COALESCE(NULLIF(trim(p_username), ''), bot_subscribers.username),
    first_name = COALESCE(NULLIF(trim(p_first_name), ''), bot_subscribers.first_name),
    last_name = COALESCE(NULLIF(trim(p_last_name), ''), bot_subscribers.last_name),
    last_webapp_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION admin_get_push_settings(p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;
  RETURN json_build_object(
    'mode', get_setting('bot_push_mode', 'all'),
    'admin_telegram_id', get_setting('admin_telegram_id', ''),
    'admin_skip_push', get_setting('admin_skip_push', 'true') = 'true',
    'duty_reminders_enabled', get_setting('duty_reminders_enabled', 'true') = 'true'
  );
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_push_settings(
  p_password TEXT,
  p_mode TEXT,
  p_admin_telegram_id TEXT DEFAULT NULL,
  p_admin_skip_push BOOLEAN DEFAULT NULL,
  p_duty_reminders_enabled BOOLEAN DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT;
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;

  IF p_mode IS NOT NULL THEN
    v_mode := lower(trim(p_mode));
    IF v_mode NOT IN ('all', 'off', 'test') THEN
      RAISE EXCEPTION 'Невірний режим push: all, off або test';
    END IF;
    INSERT INTO app_settings (key, value) VALUES ('bot_push_mode', v_mode)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  END IF;

  IF p_admin_telegram_id IS NOT NULL THEN
    INSERT INTO app_settings (key, value)
    VALUES ('admin_telegram_id', trim(p_admin_telegram_id))
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  END IF;

  IF p_admin_skip_push IS NOT NULL THEN
    INSERT INTO app_settings (key, value)
    VALUES ('admin_skip_push', CASE WHEN p_admin_skip_push THEN 'true' ELSE 'false' END)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  END IF;

  IF p_duty_reminders_enabled IS NOT NULL THEN
    INSERT INTO app_settings (key, value)
    VALUES ('duty_reminders_enabled', CASE WHEN p_duty_reminders_enabled THEN 'true' ELSE 'false' END)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  END IF;

  RETURN admin_get_push_settings(p_password);
END;
$$;

-- Сумісність з v4 (чекбокс увімкнено/вимкнено)
CREATE OR REPLACE FUNCTION admin_get_bot_push_enabled(p_password TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;
  RETURN get_setting('bot_push_mode', 'all') <> 'off';
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_bot_push_enabled(p_password TEXT, p_enabled BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM admin_set_push_settings(
    p_password,
    CASE WHEN p_enabled THEN 'all' ELSE 'off' END,
    NULL, NULL, NULL
  );
  RETURN p_enabled;
END;
$$;

CREATE OR REPLACE FUNCTION admin_get_activity_stats(p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := NOW() - INTERVAL '7 days';
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;

  RETURN json_build_object(
    'unique_users_7d', (
      SELECT COUNT(DISTINCT telegram_user_id)
      FROM webapp_visit_log
      WHERE visited_at >= v_since
    ),
    'total_visits_7d', (
      SELECT COUNT(*)::INT
      FROM webapp_visit_log
      WHERE visited_at >= v_since
    ),
    'by_day', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.day DESC), '[]'::json)
      FROM (
        SELECT
          to_char((visited_at AT TIME ZONE 'Europe/Kyiv')::date, 'YYYY-MM-DD') AS day,
          COUNT(*)::INT AS visits,
          COUNT(DISTINCT telegram_user_id)::INT AS unique_users
        FROM webapp_visit_log
        WHERE visited_at >= v_since
        GROUP BY 1
      ) d
    )
  );
END;
$$;

-- Санітарка на завтра (дата в duty.date як TEXT YYYY-MM-DD)
CREATE OR REPLACE FUNCTION get_duty_sanitary_tomorrow_kyiv()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tomorrow TEXT;
BEGIN
  v_tomorrow := to_char((NOW() AT TIME ZONE 'Europe/Kyiv')::date + 1, 'YYYY-MM-DD');
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json)
    FROM (
      SELECT id, floor, wing, room, date
      FROM duty
      WHERE date = v_tomorrow
      ORDER BY floor, wing, room
    ) t
  );
END;
$$;

CREATE OR REPLACE FUNCTION should_send_duty_reminder_today()
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tomorrow TEXT;
  v_last TEXT;
BEGIN
  IF get_setting('duty_reminders_enabled', 'true') <> 'true' THEN
    RETURN FALSE;
  END IF;
  IF get_setting('bot_push_mode', 'all') = 'off' THEN
    RETURN FALSE;
  END IF;
  v_tomorrow := to_char((NOW() AT TIME ZONE 'Europe/Kyiv')::date + 1, 'YYYY-MM-DD');
  v_last := get_setting('duty_reminder_last_date', '');
  IF v_last = v_tomorrow THEN
    RETURN FALSE;
  END IF;
  RETURN EXISTS (SELECT 1 FROM duty WHERE date = v_tomorrow);
END;
$$;

CREATE OR REPLACE FUNCTION mark_duty_reminder_sent_today()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tomorrow TEXT;
BEGIN
  v_tomorrow := to_char((NOW() AT TIME ZONE 'Europe/Kyiv')::date + 1, 'YYYY-MM-DD');
  INSERT INTO app_settings (key, value) VALUES ('duty_reminder_last_date', v_tomorrow)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
END;
$$;

GRANT EXECUTE ON FUNCTION get_push_recipient_chat_ids(TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_get_push_settings(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_set_push_settings(TEXT, TEXT, TEXT, BOOLEAN, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_get_activity_stats(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_duty_sanitary_tomorrow_kyiv() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION should_send_duty_reminder_today() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_duty_reminder_sent_today() TO anon, authenticated;
