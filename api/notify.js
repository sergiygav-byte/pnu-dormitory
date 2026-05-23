/**
 * Розсилка push у Telegram (режими: all / off / test, виключення адміна).
 * Vercel env: BOT_TOKEN, SUPABASE_URL, SUPABASE_ANON_KEY, NOTIFY_SECRET
 */

import { sendPushMessages } from './lib/push-helpers.js';

function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS, GET');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-Notify-Secret');
}

export default async function handler(req, res) {
  applyCors(res);

  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }

  if (req.method === 'GET') {
    return res.status(200).json({
      ok: true,
      service: 'pnu-dorm-notify',
      hint: 'POST with X-Notify-Secret, title, message; modes: all, off, test',
    });
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'POST only' });
  }

  const secret = req.headers['x-notify-secret'] || req.body?.secret;
  if (!secret || secret !== process.env.NOTIFY_SECRET) {
    return res.status(401).json({ error: 'Unauthorized', hint: 'NOTIFY_SECRET mismatch with config.public.js' });
  }

  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) {
    return res.status(500).json({ error: 'Supabase env missing on Vercel' });
  }

  const { message, title } = req.body || {};
  if (!message) {
    return res.status(400).json({ error: 'message required' });
  }

  const targetTgId = req.body?.target_tg_id || null;
  const forceBroadcast = !!req.body?.force_broadcast;

  try {
    const result = await sendPushMessages({ title, message, targetTgId, forceBroadcast });
    return res.status(200).json(result);
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: err.message });
  }
}
