/**
 * Telegram webhook: /start, підписка на push, кнопка Mini App.
 */

async function telegramApi(token, method, body) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) console.error(method, await res.text());
  return res;
}

async function registerSubscriber(message) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  if (!url || !key || !message?.chat?.id) return;
  const from = message.from || {};
  await fetch(`${url}/rest/v1/rpc/register_bot_subscriber`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: key,
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      p_chat_id: message.chat.id,
      p_tg_id: from.id ? String(from.id) : '',
      p_username: from.username || '',
      p_first_name: from.first_name || '',
      p_last_name: from.last_name || '',
    }),
  });
}

async function isSubscriberBlocked(message) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  const tgId = message?.from?.id ? String(message.from.id) : '';
  if (!url || !key || !tgId) return false;
  const res = await fetch(`${url}/rest/v1/rpc/is_bot_user_blocked`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: key,
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({ p_tg_id: tgId }),
  });
  if (!res.ok) return false;
  return (await res.json()) === true;
}

const APP_BUILD = process.env.APP_BUILD || '20260525a';
const WEBAPP_BASE =
  process.env.WEBAPP_URL ||
  'https://sergiygav-byte.github.io/pnu-dorm-miniapp/index.html';
const WEBAPP_URL = WEBAPP_BASE.includes('?')
  ? `${WEBAPP_BASE}&b=${APP_BUILD}`
  : `${WEBAPP_BASE}?b=${APP_BUILD}`;

const WELCOME_TEXT = `🏫 <b>Гуртожиток №1 ПНУ</b>

Вітаємо! Це офіційний додаток мешканців гуртожитку.

• Прозорий бюджет і внески
• Опитування та оголошення
• Звернення (фото або PDF за бажанням)

👇 Натисніть кнопку нижче, щоб відкрити додаток.

<i>Після /start ви отримуватимете сповіщення про нові оголошення та опитування.</i>`;

function miniAppKeyboard() {
  return {
    inline_keyboard: [
      [
        {
          text: '🏫 Відкрити гуртожиток',
          web_app: { url: WEBAPP_URL },
        },
      ],
    ],
  };
}

export default async function handler(req, res) {
  if (req.method === 'GET') {
    return res.status(200).json({
      ok: true,
      service: 'pnu-dorm-bot-webhook',
      webapp: WEBAPP_URL,
    });
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const token = process.env.BOT_TOKEN;
  if (!token) {
    return res.status(500).json({ error: 'BOT_TOKEN is not configured on Vercel' });
  }

  const update = req.body;
  const message = update?.message || update?.edited_message;
  if (!message?.text) {
    return res.status(200).json({ ok: true });
  }

  const chatId = message.chat.id;
  const text = message.text.trim();
  const isStart = /^\/start(\s|$)/.test(text);
  const isHelp = text === '/help';

  if (await isSubscriberBlocked(message)) {
    await telegramApi(token, 'sendMessage', {
      chat_id: chatId,
      text: '🚫 Доступ до бота обмежено адміністратором.',
    });
    return res.status(200).json({ ok: true, blocked: true });
  }

  if (isStart || isHelp) {
    await registerSubscriber(message);
    await telegramApi(token, 'sendMessage', {
      chat_id: chatId,
      text: WELCOME_TEXT,
      parse_mode: 'HTML',
      reply_markup: miniAppKeyboard(),
    });
  } else {
    await telegramApi(token, 'sendMessage', {
      chat_id: chatId,
      text: 'Щоб відкрити додаток, надішліть /start або натисніть кнопку нижче.',
      reply_markup: miniAppKeyboard(),
    });
  }

  return res.status(200).json({ ok: true });
}
