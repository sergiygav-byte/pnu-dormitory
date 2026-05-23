import { sendPushMessages, supabaseRpc } from './lib/push-helpers.js';

function formatPollResultLines(poll) {
  const options = Array.isArray(poll.options) ? poll.options : [];
  const votes = Array.isArray(poll.votes) ? poll.votes : [];
  const counts = options.map(() => 0);
  votes.forEach((v) => {
    const idx = Number(v.option_index);
    if (idx >= 0 && idx < counts.length) counts[idx]++;
  });
  const total = counts.reduce((a, b) => a + b, 0) || 1;
  return options.map((label, i) => {
    const pct = Math.round((counts[i] / total) * 100);
    return `• ${label}: ${pct}% (${counts[i]})`;
  });
}

export default async function handler(req, res) {
  if (req.method !== 'GET' && req.method !== 'POST') {
    return res.status(405).json({ error: 'GET or POST' });
  }

  const cronSecret = process.env.CRON_SECRET;
  const auth = req.headers.authorization || '';
  const bearer = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  const headerSecret = req.headers['x-cron-secret'] || bearer;

  if (cronSecret && headerSecret !== cronSecret) {
    return res.status(401).json({ error: 'Unauthorized cron' });
  }

  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY || !process.env.BOT_TOKEN) {
    return res.status(500).json({ error: 'Missing env: SUPABASE_*, BOT_TOKEN' });
  }

  try {
    const closed = await supabaseRpc('close_expired_polls');
    const list = Array.isArray(closed) ? closed : [];
    const results = [];

    for (const poll of list) {
      const lines = formatPollResultLines(poll);
      const message = `<b>${poll.title}</b>\n\nГолосування завершено.\n\n${lines.join('\n')}`;
      const push = await sendPushMessages({
        title: '📊 Результати опитування',
        message,
        targetTgId: null,
        forceBroadcast: true,
      });
      results.push({ id: poll.id, title: poll.title, ...push });
    }

    return res.status(200).json({
      ok: true,
      closed: list.length,
      results,
    });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: err.message });
  }
}
