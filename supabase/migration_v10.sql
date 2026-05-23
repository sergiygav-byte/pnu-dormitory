-- Міграція v10: фото контактів не скидається; окреме сортування
-- Після v9

CREATE OR REPLACE FUNCTION admin_upsert_leader(
  p_password TEXT,
  p_id TEXT,
  p_role TEXT,
  p_name TEXT,
  p_phone TEXT,
  p_tg TEXT,
  p_room TEXT DEFAULT '',
  p_photo TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO leaders (id, role, name, phone, tg, room, photo)
  VALUES (
    p_id, p_role, p_name,
    COALESCE(p_phone, ''), COALESCE(p_tg, ''),
    COALESCE(p_room, ''),
    COALESCE(p_photo, '')
  )
  ON CONFLICT (id) DO UPDATE SET
    role = p_role,
    name = p_name,
    phone = p_phone,
    tg = p_tg,
    room = COALESCE(p_room, ''),
    photo = CASE
      WHEN p_photo IS NULL THEN leaders.photo
      ELSE p_photo
    END;
END;
$$;

CREATE OR REPLACE FUNCTION admin_reorder_leaders(
  p_password TEXT,
  p_ids TEXT[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  i INT := 0;
  lid TEXT;
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  IF p_ids IS NULL THEN RETURN; END IF;
  FOREACH lid IN ARRAY p_ids LOOP
    UPDATE leaders SET sort_order = i WHERE id = lid;
    i := i + 1;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION admin_upsert_leader(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_reorder_leaders(TEXT, TEXT[]) TO anon, authenticated;
