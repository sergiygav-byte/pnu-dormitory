-- Міграція v6: простий push on/off, онлайн у боті, санітарка в день події, статус+коментар
-- Після v2–v5

CREATE OR REPLACE FUNCTION get_setting(p_key TEXT, p_default TEXT DEFAULT '')
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT value FROM app_settings WHERE key = p_key LIMIT 1), p_default);
$$;

-- === Сповіщення: лише УВІМК / ВИМК для всіх ===
INSERT INTO app_settings (key, value)
VALUES ('bot_notifications_enabled', 'true')
ON CONFLICT (key) DO NOTHING;

UPDATE app_settings SET key = 'bot_notifications_enabled', value = 'false'
WHERE key = 'bot_push_mode' AND value = 'off';

UPDATE app_settings SET key = 'bot_notifications_enabled', value = 'true'
WHERE key = 'bot_push_mode' AND value IN ('all', 'test');

-- === Санітарка: час, статус, коментар, прапорець нагадування ===
ALTER TABLE duty ADD COLUMN IF NOT EXISTS duty_time TEXT NOT NULL DEFAULT '22:00';
ALTER TABLE duty ADD COLUMN IF NOT EXISTS sanitary_status TEXT NOT NULL DEFAULT 'pending';
ALTER TABLE duty ADD COLUMN IF NOT EXISTS sanitary_comment TEXT NOT NULL DEFAULT '';
ALTER TABLE duty ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN NOT NULL DEFAULT FALSE;

-- === Push: увімкнено чи ні ===
CREATE OR REPLACE FUNCTION is_bot_push_enabled()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT value = 'true' FROM app_settings WHERE key = 'bot_notifications_enabled' LIMIT 1),
    (SELECT value <> 'off' FROM app_settings WHERE key = 'bot_push_mode' LIMIT 1),
    true
  );
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
  v_result JSON;
BEGIN
  IF NOT is_bot_push_enabled() THEN
    RETURN '[]'::json;
  END IF;

  IF p_target_tg_id IS NOT NULL AND trim(p_target_tg_id) <> '' THEN
    SELECT COALESCE(json_agg(chat_id), '[]'::json) INTO v_result
    FROM bot_subscribers
    WHERE telegram_user_id = trim(p_target_tg_id) AND chat_id > 0;
    RETURN v_result;
  END IF;

  -- Усі зареєстровані в боті (/start)
  SELECT COALESCE(json_agg(chat_id), '[]'::json) INTO v_result
  FROM bot_subscribers
  WHERE chat_id > 0
    AND telegram_user_id IS NOT NULL
    AND telegram_user_id <> ''
    AND last_seen_at IS NOT NULL;

  RETURN v_result;
END;
$$;

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
  RETURN is_bot_push_enabled();
END;
$$;

CREATE OR REPLACE FUNCTION admin_set_bot_push_enabled(p_password TEXT, p_enabled BOOLEAN)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;
  INSERT INTO app_settings (key, value)
  VALUES ('bot_notifications_enabled', CASE WHEN p_enabled THEN 'true' ELSE 'false' END)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  RETURN p_enabled;
END;
$$;

-- Дашборд: зареєстровані + зараз онлайн (15 хв)
CREATE OR REPLACE FUNCTION admin_get_users_dashboard(p_password TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_since TIMESTAMPTZ := NOW() - INTERVAL '7 days';
  v_online_since TIMESTAMPTZ := NOW() - INTERVAL '15 minutes';
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;

  RETURN json_build_object(
    'notifications_enabled', is_bot_push_enabled(),
    'registered_count', (
      SELECT COUNT(*)::INT FROM bot_subscribers
      WHERE telegram_user_id IS NOT NULL AND telegram_user_id <> '' AND last_seen_at IS NOT NULL
    ),
    'online_count', (
      SELECT COUNT(*)::INT FROM bot_subscribers
      WHERE telegram_user_id IS NOT NULL AND telegram_user_id <> ''
        AND GREATEST(
          COALESCE(last_seen_at, '1970-01-01'::timestamptz),
          COALESCE(last_webapp_at, '1970-01-01'::timestamptz)
        ) >= v_online_since
    ),
    'unique_users_7d', (
      SELECT COUNT(DISTINCT telegram_user_id)::INT FROM webapp_visit_log WHERE visited_at >= v_since
    ),
    'total_visits_7d', (
      SELECT COUNT(*)::INT FROM webapp_visit_log WHERE visited_at >= v_since
    ),
    'registered', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.last_activity DESC NULLS LAST), '[]'::json)
      FROM (
        SELECT
          telegram_user_id, username, first_name, last_name,
          last_seen_at, last_webapp_at,
          GREATEST(COALESCE(last_seen_at, '1970-01-01'::timestamptz), COALESCE(last_webapp_at, '1970-01-01'::timestamptz)) AS last_activity
        FROM bot_subscribers
        WHERE telegram_user_id IS NOT NULL AND telegram_user_id <> '' AND last_seen_at IS NOT NULL
      ) t
    ),
    'online_now', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.last_activity DESC NULLS LAST), '[]'::json)
      FROM (
        SELECT
          telegram_user_id, username, first_name, last_name,
          last_seen_at, last_webapp_at,
          GREATEST(COALESCE(last_seen_at, '1970-01-01'::timestamptz), COALESCE(last_webapp_at, '1970-01-01'::timestamptz)) AS last_activity
        FROM bot_subscribers
        WHERE telegram_user_id IS NOT NULL AND telegram_user_id <> ''
          AND GREATEST(
            COALESCE(last_seen_at, '1970-01-01'::timestamptz),
            COALESCE(last_webapp_at, '1970-01-01'::timestamptz)
          ) >= v_online_since
      ) t
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

-- Санітарка: нагадування вранці в ДЕНЬ чергування (Kyiv)
CREATE OR REPLACE FUNCTION get_duty_sanitary_today_kyiv()
RETURNS JSON
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today TEXT;
BEGIN
  v_today := to_char((NOW() AT TIME ZONE 'Europe/Kyiv')::date, 'YYYY-MM-DD');
  RETURN (
    SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.floor, t.wing, t.room), '[]'::json)
    FROM (
      SELECT id, floor, wing, room, date, duty_time, sanitary_status
      FROM duty
      WHERE date = v_today AND reminder_sent = FALSE
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
BEGIN
  IF NOT is_bot_push_enabled() THEN
    RETURN FALSE;
  END IF;
  IF get_setting('duty_reminders_enabled', 'true') <> 'true' THEN
    RETURN FALSE;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM duty
    WHERE date = to_char((NOW() AT TIME ZONE 'Europe/Kyiv')::date, 'YYYY-MM-DD')
      AND reminder_sent = FALSE
  );
END;
$$;

CREATE OR REPLACE FUNCTION mark_duty_reminders_sent_today()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today TEXT;
BEGIN
  v_today := to_char((NOW() AT TIME ZONE 'Europe/Kyiv')::date, 'YYYY-MM-DD');
  UPDATE duty SET reminder_sent = TRUE WHERE date = v_today AND reminder_sent = FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION admin_insert_duty(
  p_password TEXT,
  p_id TEXT,
  p_floor TEXT,
  p_wing TEXT,
  p_room TEXT,
  p_date TEXT,
  p_duty_time TEXT DEFAULT '22:00'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO duty (id, floor, wing, room, date, duty_time, sanitary_status, sanitary_comment, reminder_sent)
  VALUES (
    p_id, p_floor, p_wing, p_room, p_date,
    COALESCE(NULLIF(trim(p_duty_time), ''), '22:00'),
    'pending', '', FALSE
  );
END;
$$;

CREATE OR REPLACE FUNCTION admin_update_duty_sanitary(
  p_password TEXT,
  p_id TEXT,
  p_status TEXT,
  p_comment TEXT DEFAULT NULL,
  p_duty_time TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  v_status := lower(trim(COALESCE(p_status, 'pending')));
  IF v_status NOT IN ('pending', 'done', 'not_done') THEN
    RAISE EXCEPTION 'Статус: pending, done або not_done';
  END IF;
  UPDATE duty SET
    sanitary_status = v_status,
    sanitary_comment = COALESCE(p_comment, sanitary_comment),
    duty_time = COALESCE(NULLIF(trim(p_duty_time), ''), duty_time)
  WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Чергування не знайдено';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_get_users_dashboard(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_duty_sanitary_today_kyiv() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_duty_reminders_sent_today() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_update_duty_sanitary(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
