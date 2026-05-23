// Скопіюйте як config.js і вставте ключі з Supabase Dashboard → Project Settings → API
window.SUPABASE_URL = 'https://ВАШ_ПРОЄКТ.supabase.co';
window.SUPABASE_ANON_KEY = 'ваш_anon_public_key';

// Push у Telegram (після деплою api/notify.js на Vercel) — опційно
window.NOTIFY_API_URL = 'https://ВАШ-ПРОЄКТ.vercel.app/api/notify';
window.NOTIFY_SECRET = 'той_самий_секрет_що_NOTIFY_SECRET_на_Vercel';
