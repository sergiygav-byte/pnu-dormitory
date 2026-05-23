/**
 * Спільна логіка отримання chat_id для push (Supabase RPC).
 */

export async function fetchPushRecipientChatIds(targetTgId, forceBroadcast = false) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  if (!url || !key) throw new Error('Supabase env missing');

  const res = await fetch(`${url}/rest/v1/rpc/get_push_recipient_chat_ids`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: key,
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      p_target_tg_id: targetTgId || null,
      p_force_broadcast: !!forceBroadcast,
    }),
  });

  if (!res.ok) throw new Error(await res.text());
  const data = await res.json();
  const ids = Array.isArray(data) ? data : [];
  return ids.filter((id) => id != null && Number(id) > 0);
}

export async function isBotPushEnabled() {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  if (!url || !key) return true;
  const res = await fetch(`${url}/rest/v1/rpc/is_bot_push_enabled`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: key,
      Authorization: `Bearer ${key}`,
    },
    body: '{}',
  });
  if (!res.ok) {
    console.warn('is_bot_push_enabled failed', await res.text());
    return true;
  }
  const data = await res.json();
  return data !== false;
}

export async function telegramSend(token, chatId, text) {
  const res = await fetch(`https://api.telegram.org/bot${token}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: chatId,
      text,
      parse_mode: 'HTML',
      disable_web_page_preview: true,
    }),
  });
  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Telegram API: ${errText}`);
  }
}

export async function sendPushMessages({ title, message, targetTgId, forceBroadcast }) {
  const token = process.env.BOT_TOKEN;
  if (!token) throw new Error('BOT_TOKEN missing on Vercel');

  const pushEnabled = await isBotPushEnabled();
  if (!pushEnabled) {
    return {
      ok: true,
      sent: 0,
      total: 0,
      skipped: true,
      hint: 'Сповіщення вимкнено для всіх',
    };
  }

  const text = title
    ? `<b>${title}</b>\n\n${message}\n\n🏫 Відкрийте додаток через меню бота.`
    : `${message}\n\n🏫 Відкрийте додаток через меню бота.`;

  const chatIds = await fetchPushRecipientChatIds(targetTgId, forceBroadcast);
  let sent = 0;
  const errors = [];

  for (const chatId of chatIds) {
    try {
      await telegramSend(token, chatId, text);
      sent++;
    } catch (e) {
      console.error('send failed', chatId, e);
      errors.push({ chatId, error: e.message });
    }
  }

  return {
    ok: true,
    sent,
    total: chatIds.length,
    hint:
      chatIds.length === 0
        ? 'Немає підписників — потрібен /start у боті або сповіщення вимкнені'
        : sent === 0
          ? 'Одержувачі є, але Telegram не прийняв повідомлення'
          : undefined,
    errors: errors.length ? errors : undefined,
  };
}

export async function supabaseRpc(name, body = {}) {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: key,
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}
