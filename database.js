/**
 * Хмарний шар: Supabase + Storage + опитування + push + тікети скарг
 */
(function (global) {
    const BUCKET = 'dorm-photos';
    const MAX_FILE_MB = 20;

    let supabaseClient = null;
    let mockDB = {
        goals: [],
        payments: [],
        expenses: [],
        events: [],
        duty: [],
        leaders: [],
        complaints: [],
        complaintComments: [],
        polls: [],
        pollVotes: [],
        sanitaryComments: [],
        sanitaryReplies: [],
        info: { content: '' },
        rules: { content: '' },
        maintenanceMode: false,
    };

    function getClient() {
        if (!global.SUPABASE_URL || !global.SUPABASE_ANON_KEY) {
            throw new Error('Налаштуйте config.js (див. README)');
        }
        if (!supabaseClient) {
            supabaseClient = global.supabase.createClient(global.SUPABASE_URL, global.SUPABASE_ANON_KEY);
        }
        return supabaseClient;
    }

    function normalizeAttachments(row) {
        if (row.attachments && Array.isArray(row.attachments) && row.attachments.length > 0) {
            return row.attachments;
        }
        const legacy = row.photos_list || [];
        return legacy.map((url) => ({ url, type: 'image' }));
    }

    function mapRowToApp(row, type) {
        switch (type) {
            case 'goals':
                return { id: row.id, title: row.title, desc: row.description, target: Number(row.target_amount) };
            case 'payments':
                return { id: row.id, room: row.room, name: row.name, amount: Number(row.amount), date: row.date, status: row.status };
            case 'expenses':
                return { id: row.id, title: row.title, amount: Number(row.amount), desc: row.description, date: row.date, photosList: row.photos_list || [], attachments: normalizeAttachments(row) };
            case 'events':
                return { id: row.id, title: row.title, desc: row.description, date: row.date, time: row.time, location: row.location };
            case 'duty':
                return {
                    id: row.id,
                    floor: row.floor,
                    wing: row.wing,
                    room: row.room,
                    date: row.date,
                    dutyTime: row.duty_time || '22:00',
                    sanitaryStatus: row.sanitary_status || 'pending',
                    sanitaryComment: row.sanitary_comment || '',
                };
            case 'leaders':
                return {
                    id: row.id,
                    role: row.role,
                    name: row.name,
                    phone: row.phone || '',
                    tg: row.tg || '',
                    room: row.room || '',
                    photo: row.photo || '',
                };
            case 'complaints':
                return {
                    id: row.id,
                    subject: row.subject,
                    desc: row.description,
                    status: row.status,
                    date: row.date,
                    photosList: (row.photos_list || []).length ? row.photos_list : normalizeAttachments(row).filter((a) => a.type === 'image').map((a) => a.url),
                    attachments: normalizeAttachments(row),
                    telegramUserId: row.telegram_user_id || '',
                    telegramUsername: row.telegram_username || '',
                    telegramDisplayName: row.telegram_display_name || '',
                };
            case 'complaintComments':
                return {
                    id: row.id,
                    complaintId: row.complaint_id,
                    body: row.body,
                    authorType: row.author_type,
                    createdAt: row.created_at,
                };
            case 'polls':
                return {
                    id: row.id,
                    title: row.title,
                    desc: row.description,
                    options: row.options || [],
                    active: row.active !== false,
                    anonymous: row.anonymous !== false,
                    endsAt: row.ends_at || null,
                };
            case 'sanitaryComments':
                return {
                    id: row.id,
                    content: row.content,
                    authorName: row.author_name || '',
                    authorTelegramId: row.author_telegram_id || '',
                    isAdmin: !!row.is_admin,
                    parentId: row.parent_id || null,
                    createdAt: row.created_at,
                };
            default:
                return row;
        }
    }

    function isVideoFile(file) {
        const t = (file.type || '').toLowerCase();
        const n = (file.name || '').toLowerCase();
        return (
            t.startsWith('video/') ||
            /\.(mp4|mov|webm|avi|mkv|m4v|3gp|wmv|flv|mpeg|mpg)$/i.test(n)
        );
    }

    function fileKind(file) {
        if (isVideoFile(file)) {
            throw new Error(`Файл «${file.name}» не приймається. Дозволені лише фото та PDF.`);
        }
        const t = (file.type || '').toLowerCase();
        const n = (file.name || '').toLowerCase();
        if (t.startsWith('image/') || /\.(jpe?g|png|gif|webp|heic|heif|bmp)$/i.test(n)) return 'image';
        if (t === 'application/pdf' || n.endsWith('.pdf')) return 'pdf';
        throw new Error(`Файл «${file.name}» не підтримується. Дозволені лише фото та PDF.`);
    }

    function validateFileInput(fileInput) {
        if (!fileInput?.files?.length) return;
        Array.from(fileInput.files).forEach((file) => fileKind(file));
    }

    async function loadDB() {
        const sb = getClient();
        const [goals, payments, expenses, events, duty, leaders, complaints, comments, polls, votes, sanitary, content, maintenance] = await Promise.all([
            sb.from('goals').select('*').order('created_at', { ascending: true }),
            sb.from('payments').select('*').order('created_at', { ascending: false }),
            sb.from('expenses').select('*').order('created_at', { ascending: false }),
            sb.from('events').select('*').order('created_at', { ascending: false }),
            sb.from('duty').select('*').order('date', { ascending: true }),
            sb.from('leaders').select('*').order('sort_order', { ascending: true }),
            sb.from('complaints').select('*').order('created_at', { ascending: false }),
            sb.from('complaint_comments').select('*').order('created_at', { ascending: true }),
            sb.from('polls').select('*').order('created_at', { ascending: false }),
            sb.from('poll_votes').select('*'),
            sb.from('sanitary_comments').select('*').order('created_at', { ascending: true }),
            sb.from('content_blocks').select('*'),
            sb.rpc('get_maintenance_mode'),
        ]);

        const err = [goals, payments, expenses, events, duty, leaders, complaints, comments, polls, votes, sanitary, content, maintenance].find((r) => r.error);
        if (err) throw err.error;

        const infoBlock = (content.data || []).find((c) => c.id === 'info');
        const rulesBlock = (content.data || []).find((c) => c.id === 'rules');

        mockDB = {
            goals: (goals.data || []).map((r) => mapRowToApp(r, 'goals')),
            payments: (payments.data || []).map((r) => mapRowToApp(r, 'payments')),
            expenses: (expenses.data || []).map((r) => mapRowToApp(r, 'expenses')),
            events: (events.data || []).map((r) => mapRowToApp(r, 'events')),
            duty: (duty.data || []).map((r) => mapRowToApp(r, 'duty')),
            leaders: (leaders.data || []).map((r) => mapRowToApp(r, 'leaders')),
            complaints: (complaints.data || []).map((r) => mapRowToApp(r, 'complaints')),
            complaintComments: (comments.data || []).map((r) => mapRowToApp(r, 'complaintComments')),
            polls: (polls.data || []).map((r) => mapRowToApp(r, 'polls')),
            pollVotes: votes.data || [],
            sanitaryComments: (sanitary.data || []).map((r) => mapRowToApp(r, 'sanitaryComments')),
            sanitaryReplies: [],
            info: { content: infoBlock ? infoBlock.content : '' },
            rules: { content: rulesBlock ? rulesBlock.content : '' },
            maintenanceMode: maintenance.error ? false : !!maintenance.data,
        };
        return mockDB;
    }

    function getSanitaryCommentsForUI() {
        return mockDB.sanitaryComments || [];
    }

    async function setMaintenanceMode(password, enabled) {
        const sb = getClient();
        const { data, error } = await sb.rpc('set_maintenance_mode', {
            p_password: password,
            p_enabled: !!enabled,
        });
        if (error) throw error;
        await loadDB();
        return !!data;
    }

    async function uploadBlob(blob, folder = 'uploads') {
        if (!blob) return '';
        const sb = getClient();
        const path = `${folder}/${Date.now()}_${Math.random().toString(36).slice(2)}.jpg`;
        const { error } = await sb.storage.from(BUCKET).upload(path, blob, {
            cacheControl: '3600',
            upsert: false,
            contentType: 'image/jpeg',
        });
        if (error) throw error;
        const { data } = sb.storage.from(BUCKET).getPublicUrl(path);
        return data.publicUrl;
    }

    function isPollExpired(poll) {
        if (!poll?.endsAt) return false;
        return new Date(poll.endsAt).getTime() <= Date.now();
    }

    function isPollOpen(poll) {
        return poll?.active && !isPollExpired(poll);
    }

    function getPollVoters(pollId) {
        return (mockDB.pollVotes || []).filter((v) => v.poll_id === pollId);
    }

    function formatPollVoterLabel(vote) {
        const label = (vote.voter_label || '').trim();
        if (label && label !== vote.voter_tg_id) return label;
        if (vote.voter_tg_id) return `@${vote.voter_tg_id}`;
        return 'Користувач';
    }

    function getDB() {
        return mockDB;
    }

    function getCommentsForComplaint(complaintId) {
        return (mockDB.complaintComments || []).filter((c) => c.complaintId === complaintId);
    }

    function canViewComplaintThread(complaint, telegramUser) {
        if (!complaint) return false;
        if (!telegramUser) return false;
        return complaint.telegramUserId && complaint.telegramUserId === telegramUser.id;
    }

    function getPollResults(pollId) {
        const poll = mockDB.polls.find((p) => p.id === pollId);
        if (!poll) return [];
        const counts = poll.options.map(() => 0);
        mockDB.pollVotes
            .filter((v) => v.poll_id === pollId)
            .forEach((v) => {
                if (v.option_index >= 0 && v.option_index < counts.length) counts[v.option_index]++;
            });
        const total = counts.reduce((a, b) => a + b, 0) || 1;
        return poll.options.map((label, i) => ({
            label,
            count: counts[i],
            percent: Math.round((counts[i] / total) * 100),
        }));
    }

    function getUserVote(pollId, voterTgId) {
        if (!voterTgId) return null;
        const v = mockDB.pollVotes.find((x) => x.poll_id === pollId && x.voter_tg_id === voterTgId);
        return v ? v.option_index : null;
    }

    async function verifyAdmin(password) {
        const sb = getClient();
        const { data, error } = await sb.rpc('verify_admin_password', { p_password: password });
        if (error) throw error;
        return !!data;
    }

    async function trackWebAppVisit(telegramUser) {
        if (!telegramUser?.id) return;
        const sb = getClient();
        const u = window.Telegram?.WebApp?.initDataUnsafe?.user;
        await sb.rpc('track_webapp_visit', {
            p_tg_id: telegramUser.id,
            p_username: telegramUser.username || '',
            p_first_name: u?.first_name || telegramUser.name || '',
            p_last_name: u?.last_name || '',
        });
    }

    async function listBotVisitors(adminPassword) {
        const sb = getClient();
        const { data, error } = await sb.rpc('admin_list_bot_visitors', { p_password: adminPassword });
        if (error) throw error;
        return Array.isArray(data) ? data : [];
    }

    async function getBotPushEnabled(adminPassword) {
        const sb = getClient();
        const { data, error } = await sb.rpc('admin_get_bot_push_enabled', { p_password: adminPassword });
        if (error) throw error;
        return !!data;
    }

    async function setBotPushEnabled(adminPassword, enabled) {
        const sb = getClient();
        const { data, error } = await sb.rpc('admin_set_bot_push_enabled', {
            p_password: adminPassword,
            p_enabled: !!enabled,
        });
        if (error) throw error;
        return !!data;
    }

    async function getUsersDashboard(adminPassword) {
        const sb = getClient();
        const { data, error } = await sb.rpc('admin_get_users_dashboard', { p_password: adminPassword });
        if (error) throw error;
        return (
            data || {
                notifications_enabled: true,
                registered_count: 0,
                online_count: 0,
                registered: [],
                online_now: [],
                unique_users_7d: 0,
                total_visits_7d: 0,
                by_day: [],
            }
        );
    }

    async function setBotUserBlocked(adminPassword, telegramUserId, blocked) {
        const sb = getClient();
        const { error } = await sb.rpc('admin_set_bot_user_blocked', {
            p_password: adminPassword,
            p_tg_id: String(telegramUserId || ''),
            p_blocked: !!blocked,
        });
        if (error) throw error;
    }

    async function isBotUserBlocked(telegramUserId) {
        if (!telegramUserId) return false;
        const sb = getClient();
        const { data, error } = await sb.rpc('is_bot_user_blocked', {
            p_tg_id: String(telegramUserId),
        });
        if (error) {
            console.warn('is_bot_user_blocked', error);
            return false;
        }
        return !!data;
    }

    async function updateDutySanitary(adminPassword, dutyId, { status, comment, dutyTime }) {
        const sb = getClient();
        const { error } = await sb.rpc('admin_update_duty_sanitary', {
            p_password: adminPassword,
            p_id: dutyId,
            p_status: status,
            p_comment: comment != null ? comment : null,
            p_duty_time: dutyTime != null ? dutyTime : null,
        });
        if (error) throw error;
        await loadDB();
    }

    async function uploadPhotosFromInput(fileInput) {
        const files = await uploadFilesFromInput(fileInput);
        return files.filter((f) => f.type === 'image').map((f) => f.url);
    }

    async function uploadFilesFromInput(fileInput, folder = 'uploads') {
        if (!fileInput || !fileInput.files || fileInput.files.length === 0) return [];
        validateFileInput(fileInput);
        const sb = getClient();
        const out = [];
        const files = Array.from(fileInput.files);

        for (const file of files) {
            if (file.size > MAX_FILE_MB * 1024 * 1024) {
                throw new Error(`Файл ${file.name} завеликий (макс. ${MAX_FILE_MB} МБ)`);
            }
            const kind = fileKind(file);
            const ext = (file.name.split('.').pop() || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '') || 'bin';
            const path = `${folder}/${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
            const { error } = await sb.storage.from(BUCKET).upload(path, file, {
                cacheControl: '3600',
                upsert: false,
                contentType: file.type || 'application/octet-stream',
            });
            if (error) throw error;
            const { data } = sb.storage.from(BUCKET).getPublicUrl(path);
            out.push({ url: data.publicUrl, type: kind });
        }
        return out;
    }

    let notificationsEnabledCache = true;

    async function notifyPush(title, message, options) {
        const url = global.NOTIFY_API_URL;
        const secret = global.NOTIFY_SECRET;
        if (!url || !secret) {
            console.warn('Push вимкнено: немає NOTIFY_API_URL або NOTIFY_SECRET у config.public.js');
            return { ok: false, reason: 'no_config' };
        }
        if (!notificationsEnabledCache) {
            console.warn('Push пропущено: сповіщення вимкнено');
            return { ok: true, skipped: true, reason: 'notifications_disabled' };
        }
        const opts = options || {};
        try {
            const res = await fetch(url, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'X-Notify-Secret': secret,
                },
                body: JSON.stringify({
                    title,
                    message,
                    target_tg_id: opts.targetTgId || null,
                }),
            });
            let data = {};
            try {
                data = await res.json();
            } catch (_) {
                data = {};
            }
            if (!res.ok) {
                console.warn('Push помилка', res.status, data);
                return { ok: false, status: res.status, data };
            }
            if (data.total === 0) {
                console.warn('Push: немає підписників бота (/start)');
            } else if (data.sent === 0) {
                console.warn('Push: 0 надіслано', data);
            }
            return { ok: true, ...data };
        } catch (e) {
            console.warn('Push не надіслано (мережа/CORS?)', e);
            return { ok: false, reason: 'network', error: e.message };
        }
    }

    async function reorderLeaders(adminPassword, orderedIds) {
        const sb = getClient();
        const { error } = await sb.rpc('admin_reorder_leaders', {
            p_password: adminPassword,
            p_ids: orderedIds,
        });
        if (error) throw error;
        await loadDB();
    }

    async function deleteRow(adminPassword, table, id) {
        const sb = getClient();
        const { error } = await sb.rpc('admin_delete_row', {
            p_password: adminPassword,
            p_table: table,
            p_id: id,
        });
        if (error) throw error;
        await loadDB();
    }

    async function insertComplaint({ subject, desc, attachments, telegramUser }) {
        const sb = getClient();
        const id = 'c_' + Date.now();
        const tg = telegramUser || {};
        const { error } = await sb.rpc('insert_complaint_public', {
            p_id: id,
            p_subject: subject,
            p_desc: desc,
            p_attachments: attachments || [],
            p_tg_id: tg.id || '',
            p_tg_username: tg.username || '',
            p_tg_name: tg.name || '',
        });
        if (error) throw error;
        await loadDB();
        await notifyPush('🛠 Нове звернення', `${subject}\n${tg.name ? 'Від: ' + tg.name : ''}`);
    }

    async function addComplaintComment(adminPassword, complaintId, body, complaintForNotify) {
        const sb = getClient();
        const { error } = await sb.rpc('admin_add_complaint_comment', {
            p_password: adminPassword,
            p_complaint_id: complaintId,
            p_body: body,
        });
        if (error) throw error;
        await loadDB();
        const c = complaintForNotify || mockDB.complaints.find((x) => x.id === complaintId);
        const preview = body.length > 120 ? body.slice(0, 120) + '…' : body;
        if (c?.telegramUserId) {
            await notifyPush(
                '💬 Відповідь на ваше звернення',
                `«${c.subject}»\n\n${preview}`,
                { targetTgId: c.telegramUserId }
            );
        } else {
            await notifyPush('💬 Коментар до звернення', `«${c?.subject || 'Звернення'}»\n\n${preview}`);
        }
    }

    async function castVote(pollId, voterTgId, optionIndex, voterLabel) {
        const sb = getClient();
        const { error } = await sb.rpc('cast_poll_vote', {
            p_poll_id: pollId,
            p_voter_tg_id: String(voterTgId),
            p_option_index: optionIndex,
            p_voter_label: voterLabel || String(voterTgId),
        });
        if (error) throw error;
        await loadDB();
    }

    async function insertSanitaryComment({ adminPassword, content, parentId, authorName, authorTgId, isAdmin }) {
        const sb = getClient();
        const id = 'sc_' + Date.now();
        if (!parentId) {
            if (!adminPassword) throw new Error('Тільки адмін може додавати коментар');
            const { error } = await sb.rpc('insert_sanitary_comment_admin', {
                p_password: adminPassword,
                p_id: id,
                p_content: content,
                p_author_name: authorName || 'Адміністратор',
            });
            if (error) throw error;
        } else {
            const { error } = await sb.rpc('insert_sanitary_comment_reply', {
                p_id: id,
                p_content: content,
                p_parent_id: parentId,
                p_author_name: authorName || 'Користувач',
                p_author_tg_id: authorTgId ? String(authorTgId) : '',
                p_is_admin: !!isAdmin,
            });
            if (error) throw error;
        }
        await loadDB();
    }

    async function deleteSanitaryComment(adminPassword, commentId) {
        const sb = getClient();
        const { error } = await sb.rpc('admin_delete_sanitary_comment', {
            p_password: adminPassword,
            p_id: commentId,
        });
        if (error) throw error;
        await loadDB();
    }

    function formatPollResultsMessage(poll) {
        const results = getPollResults(poll.id);
        const lines = results.map((r) => `• ${r.label}: ${r.percent}% (${r.count})`);
        return `${poll.title}\n\n${lines.join('\n')}`;
    }

    async function adminSave(adminPassword, sheet, action, payload) {
        const sb = getClient();
        const pw = adminPassword;

        if (sheet === 'goals') {
            const { error } = await sb.rpc('admin_upsert_goal', {
                p_password: pw,
                p_id: payload.id,
                p_title: payload.title,
                p_desc: payload.desc,
                p_target: payload.target,
            });
            if (error) throw error;
            if (action === 'add') {
                await notifyPush('🎯 Нова ціль збору', `${payload.title}\nЦіль: ${payload.target} ₴`);
            }
        } else if (sheet === 'payments') {
            const { error } = await sb.rpc('admin_upsert_payment', {
                p_password: pw,
                p_id: payload.id,
                p_room: payload.room,
                p_name: payload.name,
                p_amount: payload.amount,
                p_date: payload.date,
                p_status: payload.status,
            });
            if (error) throw error;
            if (action === 'add') {
                await notifyPush(
                    '📥 Новий запис внеску',
                    `Кімн. ${payload.room}, ${payload.name}\n${payload.amount} ₴ — ${payload.status}`
                );
            }
        } else if (sheet === 'expenses') {
            const { error } = await sb.rpc('admin_insert_expense', {
                p_password: pw,
                p_id: payload.id,
                p_title: payload.title,
                p_amount: payload.amount,
                p_desc: payload.desc,
                p_date: payload.date,
                p_photos: payload.photosList || [],
            });
            if (error) throw error;
            await notifyPush('📤 Новий фінансовий звіт', `${payload.title}\n${payload.amount} ₴`);
        } else if (sheet === 'events') {
            const { error } = await sb.rpc('admin_upsert_event', {
                p_password: pw,
                p_id: payload.id,
                p_title: payload.title,
                p_desc: payload.desc,
                p_date: payload.date,
                p_time: payload.time,
                p_location: payload.location,
            });
            if (error) throw error;
            if (action === 'add') {
                await notifyPush('📢 Нове оголошення', payload.title);
            }
        } else if (sheet === 'duty') {
            const { error } = await sb.rpc('admin_insert_duty', {
                p_password: pw,
                p_id: payload.id,
                p_floor: payload.floor,
                p_wing: payload.wing,
                p_room: payload.room,
                p_date: payload.date,
                p_duty_time: payload.dutyTime || '22:00',
            });
            if (error) throw error;
            const t = payload.dutyTime || '22:00';
            await notifyPush(
                '🧹 Чергування',
                `${payload.date} о ${t}: поверх ${payload.floor}, ${payload.wing} крило, кімн. ${payload.room}`
            );
        } else if (sheet === 'leaders') {
            const { error } = await sb.rpc('admin_upsert_leader', {
                p_password: pw,
                p_id: payload.id,
                p_role: payload.role,
                p_name: payload.name,
                p_phone: payload.phone,
                p_tg: payload.tg,
                p_room: payload.room || '',
                p_photo: payload.photo !== undefined ? payload.photo : null,
            });
            if (error) throw error;
        } else if (sheet === 'complaints') {
            const { error } = await sb.rpc('admin_update_complaint', {
                p_password: pw,
                p_id: payload.id,
                p_subject: payload.subject,
                p_desc: payload.desc,
                p_status: payload.status,
            });
            if (error) throw error;
        } else if (sheet === 'polls') {
            if (action === 'add') {
                const { error } = await sb.rpc('admin_create_poll', {
                    p_password: pw,
                    p_id: payload.id,
                    p_title: payload.title,
                    p_desc: payload.desc,
                    p_options: payload.options,
                    p_anonymous: payload.anonymous !== false,
                    p_ends_at: payload.endsAt || null,
                });
                if (error) throw error;
                await notifyPush('📊 Нове опитування', payload.title);
            } else if (action === 'close') {
                const poll = mockDB.polls.find((p) => p.id === payload.id);
                const { error } = await sb.rpc('admin_set_poll_active', {
                    p_password: pw,
                    p_id: payload.id,
                    p_active: false,
                });
                if (error) throw error;
                const body = poll ? formatPollResultsMessage(poll) : 'Опитування завершено';
                await notifyPush('📊 Опитування закрито', body);
            }
        } else if (sheet === 'info' || sheet === 'rules') {
            const { error } = await sb.rpc('admin_update_content', {
                p_password: pw,
                p_id: sheet,
                p_content: payload.content,
            });
            if (error) throw error;
        }

        await loadDB();
    }

    global.DormDatabase = {
        loadDB,
        getDB,
        getCommentsForComplaint,
        canViewComplaintThread,
        getPollResults,
        getUserVote,
        getPollVoters,
        formatPollVoterLabel,
        isPollExpired,
        isPollOpen,
        getSanitaryCommentsForUI,
        insertSanitaryComment,
        deleteSanitaryComment,
        setMaintenanceMode,
        uploadBlob,
        formatPollResultsMessage,
        verifyAdmin,
        trackWebAppVisit,
        listBotVisitors,
        getBotPushEnabled,
        setBotPushEnabled,
        getUsersDashboard,
        setBotUserBlocked,
        isBotUserBlocked,
        updateDutySanitary,
        setNotificationsEnabledCache: (enabled) => {
            notificationsEnabledCache = !!enabled;
        },
        setBotPushEnabledCache: (enabled) => {
            notificationsEnabledCache = !!enabled;
        },
        validateFileInput,
        uploadPhotosFromInput,
        uploadFilesFromInput,
        reorderLeaders,
        deleteRow,
        insertComplaint,
        addComplaintComment,
        castVote,
        adminSave,
        notifyPush,
    };
})(window);
