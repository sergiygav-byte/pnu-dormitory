/**
 * Хмарний шар даних: Supabase PostgreSQL + Storage для фото.
 * Працює 24/7 без вашого ПК (безкоштовний тариф Supabase).
 */
(function (global) {
    const BUCKET = 'dorm-photos';

    let supabaseClient = null;
    let mockDB = {
        goals: [],
        payments: [],
        expenses: [],
        events: [],
        duty: [],
        leaders: [],
        complaints: [],
        info: { content: '' },
        rules: { content: '' }
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

    function mapRowToApp(row, type) {
        switch (type) {
            case 'goals':
                return { id: row.id, title: row.title, desc: row.description, target: Number(row.target_amount) };
            case 'payments':
                return { id: row.id, room: row.room, name: row.name, amount: Number(row.amount), date: row.date, status: row.status };
            case 'expenses':
                return { id: row.id, title: row.title, amount: Number(row.amount), desc: row.description, date: row.date, photosList: row.photos_list || [] };
            case 'events':
                return { id: row.id, title: row.title, desc: row.description, date: row.date, time: row.time, location: row.location };
            case 'duty':
                return { id: row.id, floor: row.floor, wing: row.wing, room: row.room, date: row.date };
            case 'leaders':
                return { id: row.id, role: row.role, name: row.name, phone: row.phone || '', tg: row.tg || '' };
            case 'complaints':
                return { id: row.id, subject: row.subject, desc: row.description, status: row.status, date: row.date, photosList: row.photos_list || [] };
            default:
                return row;
        }
    }

    async function loadDB() {
        const sb = getClient();
        const [goals, payments, expenses, events, duty, leaders, complaints, content] = await Promise.all([
            sb.from('goals').select('*').order('created_at', { ascending: true }),
            sb.from('payments').select('*').order('created_at', { ascending: false }),
            sb.from('expenses').select('*').order('created_at', { ascending: false }),
            sb.from('events').select('*').order('created_at', { ascending: false }),
            sb.from('duty').select('*').order('date', { ascending: true }),
            sb.from('leaders').select('*').order('sort_order', { ascending: true }),
            sb.from('complaints').select('*').order('created_at', { ascending: false }),
            sb.from('content_blocks').select('*')
        ]);

        const err = [goals, payments, expenses, events, duty, leaders, complaints, content]
            .find(r => r.error);
        if (err) throw err.error;

        const infoBlock = (content.data || []).find(c => c.id === 'info');
        const rulesBlock = (content.data || []).find(c => c.id === 'rules');

        mockDB = {
            goals: (goals.data || []).map(r => mapRowToApp(r, 'goals')),
            payments: (payments.data || []).map(r => mapRowToApp(r, 'payments')),
            expenses: (expenses.data || []).map(r => mapRowToApp(r, 'expenses')),
            events: (events.data || []).map(r => mapRowToApp(r, 'events')),
            duty: (duty.data || []).map(r => mapRowToApp(r, 'duty')),
            leaders: (leaders.data || []).map(r => mapRowToApp(r, 'leaders')),
            complaints: (complaints.data || []).map(r => mapRowToApp(r, 'complaints')),
            info: { content: infoBlock ? infoBlock.content : '' },
            rules: { content: rulesBlock ? rulesBlock.content : '' }
        };
        return mockDB;
    }

    function getDB() {
        return mockDB;
    }

    async function verifyAdmin(password) {
        const sb = getClient();
        const { data, error } = await sb.rpc('verify_admin_password', { p_password: password });
        if (error) throw error;
        return !!data;
    }

    async function uploadPhotosFromInput(fileInput) {
        if (!fileInput || !fileInput.files || fileInput.files.length === 0) return [];
        const sb = getClient();
        const urls = [];
        const files = Array.from(fileInput.files);

        for (const file of files) {
            const ext = (file.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '');
            const path = `${Date.now()}_${Math.random().toString(36).slice(2)}.${ext}`;
            const { error } = await sb.storage.from(BUCKET).upload(path, file, {
                cacheControl: '3600',
                upsert: false,
                contentType: file.type || 'image/jpeg'
            });
            if (error) throw error;
            const { data } = sb.storage.from(BUCKET).getPublicUrl(path);
            urls.push(data.publicUrl);
        }
        return urls;
    }

    async function deleteRow(adminPassword, table, id) {
        const sb = getClient();
        const { error } = await sb.rpc('admin_delete_row', {
            p_password: adminPassword,
            p_table: table,
            p_id: id
        });
        if (error) throw error;
        await loadDB();
    }

    async function insertComplaint({ subject, desc, photosList }) {
        const sb = getClient();
        const id = 'c_' + Date.now();
        const { error } = await sb.from('complaints').insert({
            id,
            subject,
            description: desc,
            status: 'В обробці ⏳',
            date: new Date().toISOString().split('T')[0],
            photos_list: photosList || []
        });
        if (error) throw error;
        await loadDB();
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
                p_target: payload.target
            });
            if (error) throw error;
        } else if (sheet === 'payments') {
            const { error } = await sb.rpc('admin_upsert_payment', {
                p_password: pw,
                p_id: payload.id,
                p_room: payload.room,
                p_name: payload.name,
                p_amount: payload.amount,
                p_date: payload.date,
                p_status: payload.status
            });
            if (error) throw error;
        } else if (sheet === 'expenses') {
            const { error } = await sb.rpc('admin_insert_expense', {
                p_password: pw,
                p_id: payload.id,
                p_title: payload.title,
                p_amount: payload.amount,
                p_desc: payload.desc,
                p_date: payload.date,
                p_photos: payload.photosList || []
            });
            if (error) throw error;
        } else if (sheet === 'events') {
            const { error } = await sb.rpc('admin_upsert_event', {
                p_password: pw,
                p_id: payload.id,
                p_title: payload.title,
                p_desc: payload.desc,
                p_date: payload.date,
                p_time: payload.time,
                p_location: payload.location
            });
            if (error) throw error;
        } else if (sheet === 'duty') {
            const { error } = await sb.rpc('admin_insert_duty', {
                p_password: pw,
                p_id: payload.id,
                p_floor: payload.floor,
                p_wing: payload.wing,
                p_room: payload.room,
                p_date: payload.date
            });
            if (error) throw error;
        } else if (sheet === 'leaders') {
            const { error } = await sb.rpc('admin_upsert_leader', {
                p_password: pw,
                p_id: payload.id,
                p_role: payload.role,
                p_name: payload.name,
                p_phone: payload.phone,
                p_tg: payload.tg
            });
            if (error) throw error;
        } else if (sheet === 'complaints') {
            const { error } = await sb.rpc('admin_update_complaint', {
                p_password: pw,
                p_id: payload.id,
                p_subject: payload.subject,
                p_desc: payload.desc,
                p_status: payload.status
            });
            if (error) throw error;
        } else if (sheet === 'info' || sheet === 'rules') {
            const { error } = await sb.rpc('admin_update_content', {
                p_password: pw,
                p_id: sheet,
                p_content: payload.content
            });
            if (error) throw error;
        }

        await loadDB();
    }

    global.DormDatabase = {
        loadDB,
        getDB,
        verifyAdmin,
        uploadPhotosFromInput,
        deleteRow,
        insertComplaint,
        adminSave
    };
})(window);
