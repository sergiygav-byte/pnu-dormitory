-- Міграція v9: коментарі санітарки (всі бачать текст), режим оновлення
-- Після v8

DROP POLICY IF EXISTS "public_read_sanitary_top" ON sanitary_comments;
CREATE POLICY "public_read_sanitary_all" ON sanitary_comments
  FOR SELECT USING (true);

INSERT INTO app_settings (key, value)
VALUES ('maintenance_mode', 'false')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION get_maintenance_mode()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT value = 'true' FROM app_settings WHERE key = 'maintenance_mode' LIMIT 1),
    false
  );
$$;

CREATE OR REPLACE FUNCTION set_maintenance_mode(
  p_password TEXT,
  p_enabled BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF trim(COALESCE(p_password, '')) <> 'update1177' THEN
    RAISE EXCEPTION 'Невірний пароль';
  END IF;
  INSERT INTO app_settings (key, value)
  VALUES ('maintenance_mode', CASE WHEN COALESCE(p_enabled, false) THEN 'true' ELSE 'false' END)
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  RETURN COALESCE(p_enabled, false);
END;
$$;

GRANT EXECUTE ON FUNCTION get_maintenance_mode() TO anon, authenticated;
GRANT EXECUTE ON FUNCTION set_maintenance_mode(TEXT, BOOLEAN) TO anon, authenticated;
