// ============================================================
// Graduation Project Evaluation System - Backend Server
// Node.js + Express + PostgreSQL
// CATS entegrasyonlu, DB tabanlı authorization
// ============================================================

const express = require('express');  // Web framework
const { Pool } = require('pg');      // PostgreSQL bağlantısı
const axios   = require('axios');    // CATS'e HTTP isteği göndermek için

const app  = express();
const PORT = 3000;

app.use(express.json()); // Gelen isteklerin body'sini JSON olarak parse et

// ── Veritabanı Bağlantısı ─────────────────────────────────────────────────────
const pool = new Pool({
    host:     'localhost',
    port:     5432,
    database: 'graduation_db',
    user:     'postgres',
    password: 'swkiu24258', // Kendi PostgreSQL şifrenle değiştir
});

// ════════════════════════════════════════════════════════════
// YARDIMCI FONKSİYON: CATS login sonrası kullanıcıyı DB'den bul
// Authentication CATS'te yapılır, Authorization DB'den yapılır
// Dictionary kullanımı tamamen kaldırıldı
// ════════════════════════════════════════════════════════════
async function getUserByCatsUsername(catsUsername) {
    // CATS'ten gelen kullanıcı adını DB'de ara
    // Eskiden: USER_ROLES.get(username) → Artık: SELECT ... FROM USERS WHERE cats_username = ?
    const result = await pool.query(
        'SELECT user_id, cats_username, name, email, role FROM USERS WHERE cats_username = $1',
        [catsUsername]
    );
    if (result.rows.length === 0) return null; // Kullanıcı DB'de yoksa null döner → "authenticated but not authorized"
    return result.rows[0]; // Kullanıcı bulunduysa rolü ve kimliği döndür
}

// ════════════════════════════════════════════════════════════
// YARDIMCI FONKSİYON: Ağırlıklı Ortalama Hesapla
// ════════════════════════════════════════════════════════════
async function calculateWeightedAverage(projectId) {
    const result = await pool.query(`
        SELECT e.jury_id, e.score, c.weight
        FROM EVALUATIONS e
        JOIN CRITERIA c ON e.criteria_id = c.criteria_id
        WHERE e.project_id = $1
    `, [projectId]);

    if (result.rows.length === 0) return 0;

    // Her jüri üyesinin ağırlıklı skorunu hesapla
    const juryScores = {};
    for (const row of result.rows) {
        if (!juryScores[row.jury_id]) juryScores[row.jury_id] = 0;
        juryScores[row.jury_id] += (row.score / 10 * 100) * row.weight; // Puan * Ağırlık
    }

    // Tüm jüri skorlarının ortalaması → final skor
    const scores     = Object.values(juryScores);
    const totalScore = scores.reduce((sum, s) => sum + s, 0);
    return Math.round((totalScore / scores.length) * 100) / 100;
}

// ════════════════════════════════════════════════════════════
// AUTH ENDPOINTİ
// CATS login başarılı olduktan sonra kullanıcıyı DB'de bul
// ════════════════════════════════════════════════════════════

// POST /api/auth/login
// Body: { cats_username: "2200004962", password: "..." }
// Akış: 1) CATS'e gönder → 302 değilse 401
//        2) DB'den kullanıcıyı bul → yoksa 403
//        3) Rol Jury değilse 403
//        4) Başarılıysa kullanıcı bilgilerini döndür
app.post('/api/auth/login', async (req, res) => {
    const { cats_username, password } = req.body;

    // Aşama 1: CATS'e kimlik doğrulama isteği gönder
    try {
        const catsResponse = await axios.post(
            'https://cats.iku.edu.tr/portal/xlogin',
            new URLSearchParams({ eid: cats_username, pw: password, submit: 'Login' }),
            {
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                maxRedirects: 0,        // 302'yi takip etme, yakala
                validateStatus: status => status === 302 // Sadece 302'yi başarılı say
            }
        );

        // CATS 302 dönmedi → kimlik doğrulama başarısız
        if (catsResponse.status !== 302) {
            return res.status(401).json({ error: 'Authentication failed' });
        }
    } catch (err) {
        // axios 302'yi hata olarak fırlatabilir, bu durumda başarılı sayıyoruz
        if (!err.response || err.response.status !== 302) {
            return res.status(401).json({ error: 'Authentication failed' });
        }
        // 302 geldi, devam et
    }

    // Aşama 2: DB'den kullanıcıyı bul
    const user = await getUserByCatsUsername(cats_username);

    if (!user) {
        // CATS'te geçerli ama DB'de kayıtlı değil → yetkisiz
        return res.status(403).json({ error: 'Authenticated but not authorized' });
    }

    // Aşama 3: Sadece Jury rolüne izin ver
    if (user.role !== 'Jury') {
        return res.status(403).json({ error: 'Access denied. Jury only.' });
    }

    // Aşama 4: Başarılı → kullanıcı bilgilerini döndür
    res.status(200).json({
        user_id:       user.user_id,
        cats_username: user.cats_username,
        name:          user.name,
        role:          user.role,
    });
});

// ════════════════════════════════════════════════════════════
// USERS ENDPOINTLERİ
// ════════════════════════════════════════════════════════════

// Yeni kullanıcı ekle (Admin tarafından yapılır)
// POST /api/users
app.post('/api/users', async (req, res) => {
    const { cats_username, name, email, role } = req.body;
    const result = await pool.query(
        'INSERT INTO USERS (cats_username, name, email, role) VALUES ($1,$2,$3,$4) RETURNING user_id, cats_username, name, email, role',
        [cats_username, name, email, role]
    );
    res.status(201).json(result.rows[0]);
});

// Tüm kullanıcıları getir
// GET /api/users
app.get('/api/users', async (req, res) => {
    const result = await pool.query(
        'SELECT user_id, cats_username, name, email, role FROM USERS ORDER BY user_id'
    );
    res.json(result.rows);
});

// Belirli bir kullanıcıyı getir
// GET /api/users/:id
app.get('/api/users/:id', async (req, res) => {
    const result = await pool.query(
        'SELECT user_id, cats_username, name, email, role FROM USERS WHERE user_id = $1',
        [req.params.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    res.json(result.rows[0]);
});

// ════════════════════════════════════════════════════════════
// PROJECTS ENDPOINTLERİ
// ════════════════════════════════════════════════════════════

// Yeni proje ekle
// POST /api/projects
app.post('/api/projects', async (req, res) => {
    const { project_name, student_id, description } = req.body;
    const result = await pool.query(
        'INSERT INTO PROJECTS (project_name, student_id, description) VALUES ($1,$2,$3) RETURNING *',
        [project_name, student_id, description]
    );
    res.status(201).json(result.rows[0]);
});

// Tüm projeleri getir
// GET /api/projects
app.get('/api/projects', async (req, res) => {
    const result = await pool.query(`
        SELECT p.project_id, p.project_name, p.description, u.name AS student_name
        FROM PROJECTS p
        JOIN USERS u ON p.student_id = u.user_id
        ORDER BY p.project_id
    `);
    res.json(result.rows);
});

// Belirli bir projeyi getir
// GET /api/projects/:id
app.get('/api/projects/:id', async (req, res) => {
    const result = await pool.query(
        'SELECT * FROM PROJECTS WHERE project_id = $1',
        [req.params.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'Project not found' });
    res.json(result.rows[0]);
});

// ════════════════════════════════════════════════════════════
// CRITERIA ENDPOINTLERİ
// ════════════════════════════════════════════════════════════

// Tüm kriterleri getir
// GET /api/criteria
app.get('/api/criteria', async (req, res) => {
    const result = await pool.query('SELECT * FROM CRITERIA ORDER BY criteria_id');
    res.json(result.rows);
});

// Yeni kriter ekle
// POST /api/criteria
app.post('/api/criteria', async (req, res) => {
    const { criteria_name, weight } = req.body;
    const result = await pool.query(
        'INSERT INTO CRITERIA (criteria_name, weight) VALUES ($1,$2) RETURNING *',
        [criteria_name, weight]
    );
    res.status(201).json(result.rows[0]);
});

// ════════════════════════════════════════════════════════════
// EVALUATIONS ENDPOINTLERİ
// Dictionary tamamen kaldırıldı, ownership DB'den kontrol edilir
// ════════════════════════════════════════════════════════════

// Yeni değerlendirme ekle
// POST /api/evaluations
app.post('/api/evaluations', async (req, res) => {
    const { jury_id, project_id, criteria_id, score, comment } = req.body;
    const result = await pool.query(
        'INSERT INTO EVALUATIONS (jury_id, project_id, criteria_id, score, comment) VALUES ($1,$2,$3,$4,$5) RETURNING *',
        [jury_id, project_id, criteria_id, score, comment]
    );
    res.status(201).json(result.rows[0]);
});

// Jüri paneli: sadece giriş yapan jüriye ait evaluation'ları getir
// GET /api/evaluations/jury/:juryId
// Eskiden: EVALUATION_OWNERS dictionary'si dolaşılıyordu
// Artık: EVALUATIONS.jury_id üzerinden DB sorgusu yapılıyor
app.get('/api/evaluations/jury/:juryId', async (req, res) => {
    const result = await pool.query(`
        SELECT 
            e.evaluation_id,
            p.project_name,
            c.criteria_name,
            c.weight,
            e.score,
            e.comment
        FROM EVALUATIONS e
        JOIN PROJECTS  p ON e.project_id  = p.project_id
        JOIN CRITERIA  c ON e.criteria_id = c.criteria_id
        WHERE e.jury_id = $1         -- Sadece bu jüriye ait kayıtlar gelir
        ORDER BY e.project_id, c.criteria_id
    `, [req.params.juryId]);
    res.json(result.rows);
});

// Evaluation detay sayfası: DB'den ownership kontrolü yapılır
// GET /api/evaluations/:id/jury/:juryId
// Eskiden: dictionary'de evaluation owner'a bakılıyordu
// Artık: DB'den evaluation çekilir, jury_id eşleşiyor mu kontrol edilir
app.get('/api/evaluations/:id/jury/:juryId', async (req, res) => {
    const result = await pool.query(
        'SELECT * FROM EVALUATIONS WHERE evaluation_id = $1 AND jury_id = $2',
        // WHERE evaluation_id = ? AND jury_id = ? → sadece sahibi görebilir
        [req.params.id, req.params.juryId]
    );
    if (result.rows.length === 0) {
        // Eşleşme yoksa erişim reddedilir (başkasının evaluation'ına giremez)
        return res.status(403).json({ error: 'Access denied. This evaluation does not belong to you.' });
    }
    res.json(result.rows[0]);
});

// Evaluation güncelle (submit): ownership kontrolü WHERE ile yapılır
// PUT /api/evaluations/:id/jury/:juryId
// Eskiden: sadece dictionary owner kontrolü vardı
// Artık: WHERE evaluation_id = ? AND jury_id = ? → kullanıcı request'i değiştirse bile başkasının kaydını update edemez
app.put('/api/evaluations/:id/jury/:juryId', async (req, res) => {
    const { score, comment } = req.body;
    const result = await pool.query(
        `UPDATE EVALUATIONS 
         SET score = $1, comment = $2 
         WHERE evaluation_id = $3 AND jury_id = $4  -- Ownership kontrolü burada
         RETURNING *`,
        [score, comment, req.params.id, req.params.juryId]
    );
    if (result.rows.length === 0) {
        return res.status(403).json({ error: 'Access denied or evaluation not found.' });
    }
    res.json(result.rows[0]);
});

// Bir projenin tüm değerlendirmelerini getir
// GET /api/evaluations/project/:projectId
app.get('/api/evaluations/project/:projectId', async (req, res) => {
    const result = await pool.query(`
        SELECT 
            e.evaluation_id,
            u.name  AS jury_name,
            c.criteria_name,
            c.weight,
            e.score,
            e.comment
        FROM EVALUATIONS e
        JOIN USERS    u ON e.jury_id     = u.user_id
        JOIN CRITERIA c ON e.criteria_id = c.criteria_id
        WHERE e.project_id = $1
        ORDER BY e.jury_id, c.criteria_id
    `, [req.params.projectId]);
    res.json(result.rows);
});

// ════════════════════════════════════════════════════════════
// FINAL RESULTS ENDPOINTLERİ
// ════════════════════════════════════════════════════════════

// Bir projenin final skorunu hesapla ve kaydet
// POST /api/results/:projectId
app.post('/api/results/:projectId', async (req, res) => {
    const projectId  = req.params.projectId;
    const finalScore = await calculateWeightedAverage(projectId);

    const result = await pool.query(
        'INSERT INTO FINAL_RESULTS (project_id, total_weighted_score) VALUES ($1,$2) RETURNING *',
        [projectId, finalScore]
    );
    res.status(201).json({
        message:     'Final score calculated and saved successfully',
        project_id:  projectId,
        final_score: finalScore,
        result:      result.rows[0]
    });
});

// Tüm final sonuçlarını getir
// GET /api/results
app.get('/api/results', async (req, res) => {
    const result = await pool.query(`
        SELECT 
            fr.result_id,
            p.project_name,
            u.name            AS student_name,
            fr.total_weighted_score,
            fr.generated_at
        FROM FINAL_RESULTS fr
        JOIN PROJECTS p ON fr.project_id = p.project_id
        JOIN USERS    u ON p.student_id  = u.user_id
        ORDER BY fr.generated_at DESC
    `);
    res.json(result.rows);
});

// Belirli bir projenin final sonucunu getir
// GET /api/results/:projectId
app.get('/api/results/:projectId', async (req, res) => {
    const result = await pool.query(
        'SELECT * FROM FINAL_RESULTS WHERE project_id = $1 ORDER BY generated_at DESC LIMIT 1',
        [req.params.projectId]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'No result found for this project' });
    res.json(result.rows[0]);
});

// ── Sunucuyu Başlat ───────────────────────────────────────────────────────────
app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});

// ════════════════════════════════════════════════════════════
// JURY_ASSIGNMENTS ENDPOINTLERİ
// Bir jüriye birden fazla proje, bir projeye birden fazla jüri atanabilir (N-N ilişkisi)
// ════════════════════════════════════════════════════════════

// Yeni jüri-proje ataması yap (Admin tarafından yapılır)
// POST /api/assignments
app.post('/api/assignments', async (req, res) => {
    const { jury_id, project_id } = req.body;
    const result = await pool.query(
        'INSERT INTO JURY_ASSIGNMENTS (jury_id, project_id) VALUES ($1,$2) RETURNING *',
        [jury_id, project_id]
    );
    res.status(201).json(result.rows[0]);
});

// Bir jüriye atanmış tüm projeleri getir
// GET /api/assignments/jury/:juryId
app.get('/api/assignments/jury/:juryId', async (req, res) => {
    const result = await pool.query(`
        SELECT ja.assignment_id, p.project_id, p.project_name,
               p.description, u.name AS student_name, ja.assigned_at
        FROM JURY_ASSIGNMENTS ja
        JOIN PROJECTS p ON ja.project_id = p.project_id
        JOIN USERS    u ON p.student_id  = u.user_id
        WHERE ja.jury_id = $1
        ORDER BY ja.assigned_at
    `, [req.params.juryId]);
    res.json(result.rows);
});

// Bir projeye atanmış tüm jürileri getir
// GET /api/assignments/project/:projectId
app.get('/api/assignments/project/:projectId', async (req, res) => {
    const result = await pool.query(`
        SELECT ja.assignment_id, u.user_id, u.name AS jury_name,
               u.email, ja.assigned_at
        FROM JURY_ASSIGNMENTS ja
        JOIN USERS u ON ja.jury_id = u.user_id
        WHERE ja.project_id = $1
        ORDER BY ja.assigned_at
    `, [req.params.projectId]);
    res.json(result.rows);
});

// Tüm atamaları listele
// GET /api/assignments
app.get('/api/assignments', async (req, res) => {
    const result = await pool.query(`
        SELECT ja.assignment_id, u.name AS jury_name,
               p.project_name, ja.assigned_at
        FROM JURY_ASSIGNMENTS ja
        JOIN USERS    u ON ja.jury_id    = u.user_id
        JOIN PROJECTS p ON ja.project_id = p.project_id
        ORDER BY ja.assignment_id
    `);
    res.json(result.rows);
});

// Atama sil
// DELETE /api/assignments/:assignmentId
app.delete('/api/assignments/:assignmentId', async (req, res) => {
    const result = await pool.query(
        'DELETE FROM JURY_ASSIGNMENTS WHERE assignment_id = $1 RETURNING *',
        [req.params.assignmentId]
    );
    if (result.rows.length === 0)
        return res.status(404).json({ error: 'Assignment not found' });
    res.json({ message: 'Assignment deleted', deleted: result.rows[0] });
});
