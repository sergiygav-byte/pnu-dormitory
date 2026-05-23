-- Міграція v7: блокування користувачів + ранкове і погодинне нагадування про санітарку
-- Після v6

ALTER TABLE bot_subscribers ADD COLUMN IF NOT EXISTS is_blocked BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE bot_subscribers ADD COLUMN IF NOT EXISTS blocked_at TIMESTAMPTZ;

ALTER TABLE duty ADD COLUMN IF NOT EXISTS morning_reminder_sent BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE duty ADD COLUMN IF NOT EXISTS hour_reminder_sent BOOLEAN NOT NULL DEFAULT FALSE;

UPDATE duty SET morning_reminder_sent = TRUE WHERE reminder_sent = TRUE AND morning_reminder_sent = FALSE;

CREATE OR REPLACE FUNCTION is_bot_user_blocked(p_tg_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((
    SELECT bool_or(COALESCE(is_blocked, FALSE))
    FROM bot_subscribers
    WHERE telegram_user_id = trim(COALESCE(p_tg_id, ''))
  ), FALSE);
$$;

CREATE OR REPLACE FUNCTION admin_set_bot_user_blocked(
  p_password TEXT,
  p_tg_id TEXT,
  p_blocked BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN
    RAISE EXCEPTION 'Невірний пароль адміністратора';
  END IF;

  UPDATE bot_subscribers
  SET
    is_blocked = COALESCE(p_blocked, FALSE),
    blocked_at = CASE WHEN COALESCE(p_blocked, FALSE) THEN NOW() ELSE NULL END
  WHERE telegram_user_id = trim(COALESCE(p_tg_id, ''));

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Користувача не знайдено';
  END IF;
END;
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
    WHERE telegram_user_id = trim(p_target_tg_id)
      AND chat_id > 0
      AND COALESCE(is_blocked, FALSE) = FALSE;
    RETURN v_result;
  END IF;

  SELECT COALESCE(json_agg(chat_id), '[]'::json) INTO v_result
  FROM bot_subscribers
  WHERE chat_id > 0
    AND telegram_user_id IS NOT NULL
    AND telegram_user_id <> ''
    AND last_seen_at IS NOT NULL
    AND COALESCE(is_blocked, FALSE) = FALSE;

  RETURN v_result;
END;
$$;

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
        AND COALESCE(is_blocked, FALSE) = FALSE
        AND GREATEST(COALESCE(last_seen_at, '1970-01-01'::timestamptz), COALESCE(last_webapp_at, '1970-01-01'::timestamptz)) >= v_online_since
    ),
    'unique_users_7d', (
      SELECT COUNT(DISTINCT telegram_user_id)::INT FROM webapp_visit_log WHERE visited_at >= v_since
    ),
    'total_visits_7d', (
      SELECT COUNT(*)::INT FROM webapp_visit_log WHERE visited_at >= v_since
    ),
    'registered', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.is_blocked DESC, t.last_activity DESC NULLS LAST), '[]'::json)
      FROM (
        SELECT telegram_user_id, username, first_name, last_name, last_seen_at, last_webapp_at, is_blocked, blocked_at,
          GREATEST(COALESCE(last_seen_at, '1970-01-01'::timestamptz), COALESCE(last_webapp_at, '1970-01-01'::timestamptz)) AS last_activity
        FROM bot_subscribers
        WHERE telegram_user_id IS NOT NULL AND telegram_user_id <> '' AND last_seen_at IS NOT NULL
      ) t
    ),
    'online_now', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.last_activity DESC NULLS LAST), '[]'::json)
      FROM (
        SELECT telegram_user_id, username, first_name, last_name, last_seen_at, last_webapp_at, is_blocked, blocked_at,
          GREATEST(COALESCE(last_seen_at, '1970-01-01'::timestamptz), COALESCE(last_webapp_at, '1970-01-01'::timestamptz)) AS last_activity
        FROM bot_subscribers
        WHERE telegram_user_id IS NOT NULL AND telegram_user_id <> ''
          AND COALESCE(is_blocked, FALSE) = FALSE
          AND GREATEST(COALESCE(last_seen_at, '1970-01-01'::timestamptz), COALESCE(last_webapp_at, '1970-01-01'::timestamptz)) >= v_online_since
      ) t
    ),
    'by_day', (
      SELECT COALESCE(json_agg(row_to_json(d) ORDER BY d.day DESC), '[]'::json)
      FROM (
        SELECT to_char((visited_at AT TIME ZONE 'Europe/Kyiv')::date, 'YYYY-MM-DD') AS day,
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

CREATE OR REPLACE FUNCTION get_due_duty_reminders_kyiv()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now TIMESTAMP := NOW() AT TIME ZONE 'Europe/Kyiv';
  v_today TEXT := to_char((NOW() AT TIME ZONE 'Europe/Kyiv')::date, 'YYYY-MM-DD');
BEGIN
  IF NOT is_bot_push_enabled() OR get_setting('duty_reminders_enabled', 'true') <> 'true' THEN
    RETURN json_build_object('morning', '[]'::json, 'hour', '[]'::json);
  END IF;

  RETURN json_build_object(
    'morning', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.floor, t.wing, t.room), '[]'::json)
      FROM (
        SELECT id, floor, wing, room, date, duty_time, sanitary_status
        FROM duty
        WHERE date = v_today
          AND morning_reminder_sent = FALSE
      ) t
    ),
    'hour', (
      SELECT COALESCE(json_agg(row_to_json(t) ORDER BY t.floor, t.wing, t.room), '[]'::json)
      FROM (
        SELECT id, floor, wing, room, date, duty_time, sanitary_status
        FROM duty
        WHERE date = v_today
          AND hour_reminder_sent = FALSE
          AND (date::date + COALESCE(NULLIF(duty_time, '')::time, '22:00'::time)) BETWEEN v_now AND (v_now + INTERVAL '70 minutes')
      ) t
    )
  );
END;
$$;

CREATE OR REPLACE FUNCTION mark_duty_reminders_sent(p_kind TEXT, p_ids TEXT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  IF p_kind = 'morning' THEN
    UPDATE duty SET morning_reminder_sent = TRUE, reminder_sent = TRUE WHERE id = ANY(p_ids);
  ELSIF p_kind = 'hour' THEN
    UPDATE duty SET hour_reminder_sent = TRUE WHERE id = ANY(p_ids);
  ELSE
    RAISE EXCEPTION 'Невідомий тип нагадування';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION is_bot_user_blocked(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_set_bot_user_blocked(TEXT, TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_get_users_dashboard(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_push_recipient_chat_ids(TEXT, BOOLEAN) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION get_due_duty_reminders_kyiv() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION mark_duty_reminders_sent(TEXT, TEXT[]) TO anon, authenticated;
