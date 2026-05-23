export async function telegramApi(token, method, body) {
  const res = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) console.error(method, await res.text());
  return res;
}

export async function registerSubscriber(message) {
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
    }),
  });
}
