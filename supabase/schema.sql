-- Гуртожиток №1 ПНУ — хмарна база (Supabase, безкоштовний тариф)
-- Виконайте в Supabase → SQL Editor → Run

-- Таблиці
CREATE TABLE IF NOT EXISTS goals (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  target_amount NUMERIC NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS payments (
  id TEXT PRIMARY KEY,
  room TEXT NOT NULL,
  name TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  date TEXT NOT NULL DEFAULT '-',
  status TEXT NOT NULL DEFAULT 'Не здано',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS expenses (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  amount NUMERIC NOT NULL DEFAULT 0,
  description TEXT NOT NULL DEFAULT '',
  date TEXT NOT NULL,
  photos_list JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS events (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  date TEXT NOT NULL,
  time TEXT NOT NULL DEFAULT '12:00',
  location TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS duty (
  id TEXT PRIMARY KEY,
  floor TEXT NOT NULL,
  wing TEXT NOT NULL,
  room TEXT NOT NULL,
  date TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS leaders (
  id TEXT PRIMARY KEY,
  role TEXT NOT NULL,
  name TEXT NOT NULL,
  phone TEXT DEFAULT '',
  tg TEXT DEFAULT '',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS complaints (
  id TEXT PRIMARY KEY,
  subject TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'В обробці ⏳',
  date TEXT NOT NULL,
  photos_list JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS content_blocks (
  id TEXT PRIMARY KEY,
  content TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT INTO app_settings (key, value)
VALUES ('admin_password', 'admin777')
ON CONFLICT (key) DO NOTHING;

-- Перевірка пароля адміна (змініть у таблиці app_settings після деплою!)
CREATE OR REPLACE FUNCTION is_admin(p_password TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM app_settings
    WHERE key = 'admin_password' AND value = p_password
  );
$$;

-- Видалення запису (тільки адмін)
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
    ELSE RAISE EXCEPTION 'Невідома таблиця';
  END CASE;
END;
$$;

-- RLS: усі читають; скарги — будь-хто додає; решта змін — через RPC
ALTER TABLE goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE events ENABLE ROW LEVEL SECURITY;
ALTER TABLE duty ENABLE ROW LEVEL SECURITY;
ALTER TABLE leaders ENABLE ROW LEVEL SECURITY;
ALTER TABLE complaints ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "public_read_goals" ON goals FOR SELECT USING (true);
CREATE POLICY "public_read_payments" ON payments FOR SELECT USING (true);
CREATE POLICY "public_read_expenses" ON expenses FOR SELECT USING (true);
CREATE POLICY "public_read_events" ON events FOR SELECT USING (true);
CREATE POLICY "public_read_duty" ON duty FOR SELECT USING (true);
CREATE POLICY "public_read_leaders" ON leaders FOR SELECT USING (true);
CREATE POLICY "public_read_complaints" ON complaints FOR SELECT USING (true);
CREATE POLICY "public_read_content" ON content_blocks FOR SELECT USING (true);

CREATE POLICY "public_insert_complaints" ON complaints FOR INSERT WITH CHECK (true);
-- Оновлення скарг — лише через admin_update_complaint (RPC)

-- Адмінські записи через service role у RPC — додаємо політики для authenticated anon через функції
-- Для goals/payments/... використовуємо RPC з SECURITY DEFINER (нижче)

CREATE OR REPLACE FUNCTION admin_upsert_goal(p_password TEXT, p_id TEXT, p_title TEXT, p_desc TEXT, p_target NUMERIC)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO goals (id, title, description, target_amount)
  VALUES (p_id, p_title, p_desc, p_target)
  ON CONFLICT (id) DO UPDATE SET title = p_title, description = p_desc, target_amount = p_target;
END; $$;

CREATE OR REPLACE FUNCTION admin_upsert_payment(p_password TEXT, p_id TEXT, p_room TEXT, p_name TEXT, p_amount NUMERIC, p_date TEXT, p_status TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO payments (id, room, name, amount, date, status)
  VALUES (p_id, p_room, p_name, p_amount, p_date, p_status)
  ON CONFLICT (id) DO UPDATE SET room = p_room, name = p_name, amount = p_amount, date = p_date, status = p_status;
END; $$;

CREATE OR REPLACE FUNCTION admin_insert_expense(p_password TEXT, p_id TEXT, p_title TEXT, p_amount NUMERIC, p_desc TEXT, p_date TEXT, p_photos JSONB)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO expenses (id, title, amount, description, date, photos_list)
  VALUES (p_id, p_title, p_amount, p_desc, p_date, COALESCE(p_photos, '[]'::jsonb));
END; $$;

CREATE OR REPLACE FUNCTION admin_upsert_event(p_password TEXT, p_id TEXT, p_title TEXT, p_desc TEXT, p_date TEXT, p_time TEXT, p_location TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO events (id, title, description, date, time, location)
  VALUES (p_id, p_title, p_desc, p_date, p_time, p_location)
  ON CONFLICT (id) DO UPDATE SET title = p_title, description = p_desc, date = p_date, time = p_time, location = p_location;
END; $$;

CREATE OR REPLACE FUNCTION admin_insert_duty(p_password TEXT, p_id TEXT, p_floor TEXT, p_wing TEXT, p_room TEXT, p_date TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO duty (id, floor, wing, room, date) VALUES (p_id, p_floor, p_wing, p_room, p_date);
END; $$;

CREATE OR REPLACE FUNCTION admin_upsert_leader(p_password TEXT, p_id TEXT, p_role TEXT, p_name TEXT, p_phone TEXT, p_tg TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO leaders (id, role, name, phone, tg)
  VALUES (p_id, p_role, p_name, COALESCE(p_phone, ''), COALESCE(p_tg, ''))
  ON CONFLICT (id) DO UPDATE SET role = p_role, name = p_name, phone = p_phone, tg = p_tg;
END; $$;

CREATE OR REPLACE FUNCTION admin_update_complaint(p_password TEXT, p_id TEXT, p_subject TEXT, p_desc TEXT, p_status TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  UPDATE complaints SET subject = p_subject, description = p_desc, status = p_status WHERE id = p_id;
END; $$;

CREATE OR REPLACE FUNCTION admin_update_content(p_password TEXT, p_id TEXT, p_content TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_admin(p_password) THEN RAISE EXCEPTION 'Невірний пароль'; END IF;
  INSERT INTO content_blocks (id, content) VALUES (p_id, p_content)
  ON CONFLICT (id) DO UPDATE SET content = p_content;
END; $$;

CREATE OR REPLACE FUNCTION verify_admin_password(p_password TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT is_admin(p_password);
$$;

GRANT EXECUTE ON FUNCTION verify_admin_password(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_row(TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_upsert_goal(TEXT, TEXT, TEXT, TEXT, NUMERIC) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_upsert_payment(TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_insert_expense(TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT, JSONB) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_upsert_event(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_insert_duty(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_upsert_leader(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_update_complaint(TEXT, TEXT, TEXT, TEXT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION admin_update_content(TEXT, TEXT, TEXT) TO anon, authenticated;

-- Storage: створіть bucket "dorm-photos" (Public) в Dashboard → Storage
-- Політики для bucket (SQL):
-- INSERT, SELECT для anon на dorm-photos

INSERT INTO storage.buckets (id, name, public)
VALUES ('dorm-photos', 'dorm-photos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

CREATE POLICY "dorm_photos_public_read"
ON storage.objects FOR SELECT
USING (bucket_id = 'dorm-photos');

CREATE POLICY "dorm_photos_public_upload"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'dorm-photos');

-- Початкові дані (як у вашому index.html)
INSERT INTO goals (id, title, description, target_amount) VALUES
  ('g1', 'Ремонт пральних машин 🧺', 'Заміна ТЕНів та підшипників у двох пральних машинах на 3 та 4 поверхах.', 3500),
  ('g2', 'Посуд на кухні 🍳', 'Закупівля нових сковорідок та каструль спільного користування.', 1800)
ON CONFLICT (id) DO NOTHING;

INSERT INTO payments (id, room, name, amount, date, status) VALUES
  ('p1', '302', 'Владислав Ковальчук', 150, '2026-05-10', 'Здано'),
  ('p2', '415', 'Анна Мельник', 150, '2026-05-11', 'Здано'),
  ('p3', '204', 'Дмитро Шевченко', 0, '-', 'Не здано'),
  ('p4', '508', 'Марія Бондар', 150, '2026-05-12', 'Здано')
ON CONFLICT (id) DO NOTHING;

INSERT INTO expenses (id, title, amount, description, date, photos_list) VALUES
  ('e1', 'Закупівля миючих засобів', 450, 'Придбано 5л хлорних засобів та рідкого мила для кухонь першого поверху.', '2026-05-08', '[]'),
  ('e2', 'Нові замки на двері', 900, 'Заміна серцевин та виготовлення дублікатів ключів для сушильної кімнати.', '2026-05-14', '[]')
ON CONFLICT (id) DO NOTHING;

INSERT INTO events (id, title, description, date, time, location) VALUES
  ('ev1', 'Генеральне прибирання території 🌿', 'Збираємось біля головного входу для благоустрою клумб та фарбування лавок.', '2026-05-25', '15:00', 'Подвір''я гуртожитку'),
  ('ev2', 'Планова перевірка електромереж ⚡', 'Електрики проводитимуть огляд щитових. Можливі короткочасні відключення світла.', '2026-05-28', '10:00 - 14:00', 'Усі блоки')
ON CONFLICT (id) DO NOTHING;

INSERT INTO duty (id, floor, wing, room, date) VALUES
  ('d1', '1', 'Ліве', '105', '2026-05-22'),
  ('d2', '3', 'Ліве', '305', '2026-05-22'),
  ('d3', '3', 'Праве', '309', '2026-05-23')
ON CONFLICT (id) DO NOTHING;

INSERT INTO leaders (id, role, name, phone, tg, sort_order) VALUES
  ('l1', 'Завідувач гуртожитку 🔑', 'Ольга Миколаївна', '+380671234567', 'olga_pnu', 1),
  ('l2', 'Голова студради 🎓', 'Артем Захаров', '+380939876543', 'artem_pnu_st', 2),
  ('l3', 'Староста гуртожитку 📜', 'Микола Васильович', '', '', 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO content_blocks (id, content) VALUES
('info', '<div class="text-center mb-4"><div class="w-12 h-12 rounded-full bg-gradient-to-tr from-blue-500 to-indigo-500 text-white flex items-center justify-center text-xl mx-auto mb-2 shadow-lg"><i class="fa-solid fa-sparkles"></i></div><h3 class="text-[17px] font-black uppercase text-slate-800 dark:text-slate-100">Ласкаво просимо!</h3><p class="text-[13px] text-slate-500 mt-1">Твій кишеньковий помічник по гуртожитку</p></div>'),
('rules', '<p>Просимо з повагою ставитися до санітарки і не змушувати адміністрацію зачиняти кухні на тиждень.</p><p>Зверніть увагу: щосереди проводиться генеральне прибирання кухні.</p>')
ON CONFLICT (id) DO NOTHING;
