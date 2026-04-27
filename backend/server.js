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
    password: 'yourpassword', // Kendi PostgreSQL şifrenle değiştir
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
// Öğrenci bazlı ağırlıklı ortalama hesapla
async function calculateWeightedAverage(projectId, studentId) {
    const result = await pool.query(`
        SELECT e.jury_id, e.score, c.weight
        FROM EVALUATIONS e
        JOIN CRITERIA c ON e.criteria_id = c.criteria_id
        WHERE e.project_id = $1 AND e.student_id = $2
    `, [projectId, studentId]);

    if (result.rows.length === 0) return 0;

    const juryScores = {};
    for (const row of result.rows) {
        if (!juryScores[row.jury_id]) juryScores[row.jury_id] = 0;
        juryScores[row.jury_id] += row.score * row.weight;
    }

    const scores = Object.values(juryScores);
    const totalScore = scores.reduce((sum, s) => sum + s, 0);
    return Math.round((totalScore / scores.length) * 100) / 100;
}

// ════════════════════════════════════════════════════════════
// YARDIMCI: Audit Log Kaydı Oluştur
// Her evaluation insert/update'te çağrılır
// action_type: 'CREATE' | 'UPDATE' | 'ADMIN_OVERRIDE'
// ════════════════════════════════════════════════════════════
async function logAudit({
    actorUserId,      // Kim yaptı (jury veya admin user_id)
    actionType,       // 'CREATE' | 'UPDATE' | 'ADMIN_OVERRIDE'
    evaluationId,     // Hangi evaluation kaydı (null olabilir)
    projectId,
    studentId,
    criteriaId,
    oldScore,         // null eğer CREATE ise
    newScore,
    comment = null,
}) {
    try {
        await pool.query(`
            INSERT INTO AUDIT_LOG 
                (actor_user_id, action_type, evaluation_id, project_id, 
                 student_id, criteria_id, old_score, new_score, comment)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [
            actorUserId, actionType, evaluationId, projectId,
            studentId, criteriaId, oldScore, newScore, comment
        ]);
    } catch (err) {
        // Audit log hatası ana işlemi bozmamalı, sadece konsola yaz
        console.error('Audit log error:', err.message);
    }
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

    // Önce DB'den kullanıcıyı bul (Admin için CATS bypass yapabilmek için)
    const user = await getUserByCatsUsername(cats_username);
    if (!user) {
        return res.status(403).json({ error: 'User not found in database' });
    }

    // Admin rolü için CATS bypass
    // CATS'te olmayan sistem kullanıcıları (admin001 gibi) doğrudan login olabilir
    // Production'da bu kısım kaldırılıp gerçek admin hesapları CATS'e eklenmelidir
    const isAdmin = user.role === 'Admin';

    if (!isAdmin) {
        // Normal Jury/Student akışı: CATS'e kimlik doğrulama isteği
        try {
            const catsResponse = await axios.post(
                'https://cats.iku.edu.tr/portal/xlogin',
                new URLSearchParams({ eid: cats_username, pw: password, submit: 'Login' }),
                {
                    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                    maxRedirects: 0,
                    validateStatus: status => status === 302
                }
            );
            if (catsResponse.status !== 302) {
                return res.status(401).json({ error: 'Authentication failed' });
            }
        } catch (err) {
            if (!err.response || err.response.status !== 302) {
                return res.status(401).json({ error: 'Authentication failed' });
            }
        }
    } else {
        // Admin için basit şifre kontrolü (şimdilik sabit, sonra hash'le değiştirilebilir)
        // Şifre: 'admin123' (geliştirme için)
        if (password !== 'admin123') {
            return res.status(401).json({ error: 'Authentication failed' });
        }
    }

    // Rol kontrolü
    if (user.role !== 'Jury' && user.role !== 'Student' && user.role !== 'Admin') {
        return res.status(403).json({ error: 'Access denied.' });
    }

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
// Yeni değerlendirme ekle / güncelle
// POST /api/evaluations
// Artık lock kontrollü: is_submitted=TRUE olan kayıt tekrar submit edilemez.
// Resubmit sadece unlock approve edildikten sonra mümkün.
app.post('/api/evaluations', async (req, res) => {
    const { jury_id, project_id, student_id, criteria_id, score, comment } = req.body;

    if (score < 0 || score > 100) {
        return res.status(400).json({ error: 'Score must be between 0 and 100.' });
    }
    if (!student_id) {
        return res.status(400).json({ error: 'student_id is required.' });
    }

    try {
        // Mevcut kaydı çek (varsa) — hem UPDATE/CREATE ayrımı için hem lock kontrolü için
        const existingRes = await pool.query(`
            SELECT evaluation_id, score, is_submitted FROM EVALUATIONS
            WHERE jury_id = $1 AND project_id = $2 
              AND criteria_id = $3 AND student_id = $4
        `, [jury_id, project_id, criteria_id, student_id]);

        const isUpdate = existingRes.rows.length > 0;
        const oldScore = isUpdate ? existingRes.rows[0].score : null;
        const wasSubmitted = isUpdate ? existingRes.rows[0].is_submitted : false;

        // ► LOCK ENFORCEMENT
        // Kayıt zaten submitted ise yeni POST'u reddet
        // Jüri unlock approve olduktan sonra yeniden submit edebilir
        if (isUpdate && wasSubmitted) {
            return res.status(403).json({ 
                error: 'This evaluation is locked. Request an unlock from admin to modify it.' 
            });
        }

        // RESUBMIT mi normal CREATE mi? 
        // (unlock sonrası is_submitted=FALSE kayıt üzerine yazılıyorsa bu resubmit)
        const isResubmit = isUpdate && !wasSubmitted;

        // Upsert — her submit is_submitted=TRUE olarak kilitliyor
        const result = await pool.query(`
            INSERT INTO EVALUATIONS (jury_id, project_id, criteria_id, student_id, score, comment, is_submitted)
            VALUES ($1, $2, $3, $4, $5, $6, TRUE)
            ON CONFLICT (jury_id, project_id, student_id, criteria_id)
            DO UPDATE SET 
                score = EXCLUDED.score, 
                comment = EXCLUDED.comment, 
                submitted_at = NOW(),
                is_submitted = TRUE
            RETURNING *
        `, [jury_id, project_id, criteria_id, student_id, score, comment]);

        // Audit log
        await logAudit({
            actorUserId:  jury_id,
            actionType:   isResubmit ? 'RESUBMIT' : 'CREATE',
            evaluationId: result.rows[0].evaluation_id,
            projectId:    project_id,
            studentId:    student_id,
            criteriaId:   criteria_id,
            oldScore:     oldScore,
            newScore:     score,
            comment:      comment,
        });

        res.status(201).json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
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

// Bir jürinin bir projedeki tüm evaluation'larını öğrenci × kriter breakdown'u ile getir
// GET /api/evaluations/jury/:juryId/project/:projectId
app.get('/api/evaluations/jury/:juryId/project/:projectId', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT e.student_id, e.criteria_id, c.criteria_name, c.weight, e.score, e.comment
            FROM EVALUATIONS e
            JOIN CRITERIA c ON e.criteria_id = c.criteria_id
            WHERE e.jury_id = $1 AND e.project_id = $2
        `, [req.params.juryId, req.params.projectId]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ════════════════════════════════════════════════════════════
// FINAL RESULTS ENDPOINTLERİ
// ════════════════════════════════════════════════════════════

// Bir projenin final skorunu hesapla ve kaydet
// POST /api/results/:projectId
app.post('/api/results/:projectId', async (req, res) => {
    const projectId = req.params.projectId;

    try {
        // Projeye ait tüm üyeleri al
        const members = await pool.query(
            'SELECT student_id FROM PROJECT_MEMBERS WHERE project_id = $1',
            [projectId]
        );

        if (members.rows.length === 0) {
            return res.status(404).json({ error: 'No members found for this project' });
        }

        // Her öğrenci için ayrı final skor hesapla ve kaydet (upsert)
        const results = [];
        for (const m of members.rows) {
            const finalScore = await calculateWeightedAverage(projectId, m.student_id);
            const insert = await pool.query(`
                INSERT INTO FINAL_RESULTS (project_id, student_id, total_weighted_score)
                VALUES ($1, $2, $3)
                ON CONFLICT (project_id, student_id)
                DO UPDATE SET total_weighted_score = EXCLUDED.total_weighted_score, generated_at = NOW()
                RETURNING *
            `, [projectId, m.student_id, finalScore]);
            results.push(insert.rows[0]);
        }

        res.status(201).json({
            message: 'Final scores calculated per student',
            project_id: projectId,
            results: results
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
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
    const projectsResult = await pool.query(`
        SELECT p.project_id, p.project_name, p.description,
               p.advisor, p.exam_datetime
        FROM JURY_ASSIGNMENTS ja
        JOIN PROJECTS p ON ja.project_id = p.project_id
        WHERE ja.jury_id = $1
        ORDER BY p.exam_datetime
    `, [req.params.juryId]);

    const projects = await Promise.all(projectsResult.rows.map(async (project) => {
        const membersResult = await pool.query(`
            SELECT u.user_id, u.name, u.cats_username
            FROM PROJECT_MEMBERS pm
            JOIN USERS u ON pm.student_id = u.user_id
            WHERE pm.project_id = $1
        `, [project.project_id]);

        const evaluatedResult = await pool.query(`
            SELECT COUNT(DISTINCT pm.student_id) as evaluated_count
            FROM PROJECT_MEMBERS pm
            WHERE pm.project_id = $1
            AND EXISTS (
                SELECT 1 FROM EVALUATIONS e
                WHERE e.jury_id = $2
                AND e.project_id = $1
                AND e.criteria_id IN (SELECT criteria_id FROM CRITERIA)
            )
        `, [project.project_id, req.params.juryId]);

        return {
            ...project,
            members: membersResult.rows,
            evaluated_count: parseInt(evaluatedResult.rows[0].evaluated_count),
        };
    }));

    res.json(projects);
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

// Öğrencinin kendi projesini getir
// GET /api/student/:studentId/project
app.get('/api/student/:studentId/project', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT p.project_id, p.project_name, p.description,
                   p.advisor, p.exam_datetime
            FROM PROJECTS p
            WHERE p.student_id = $1
        `, [req.params.studentId]);

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'No project found' });
        }
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Öğrencinin proje ismini ve açıklamasını güncelle
// PUT /api/student/:studentId/project
app.put('/api/student/:studentId/project', async (req, res) => {
    try {
        const { project_name, description } = req.body;
        const result = await pool.query(`
            UPDATE PROJECTS
            SET project_name = $1, description = $2
            WHERE student_id = $3
            RETURNING project_id, project_name, description
        `, [project_name, description, req.params.studentId]);

        if (result.rows.length === 0) {
            return res.status(404).json({ error: 'No project found' });
        }
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Öğrencinin final notunu getir
// GET /api/student/:studentId/result
app.get('/api/student/:studentId/result', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT fr.total_weighted_score, fr.generated_at
            FROM FINAL_RESULTS fr
            WHERE fr.student_id = $1
            ORDER BY fr.generated_at DESC LIMIT 1
        `, [req.params.studentId]);

        if (result.rows.length === 0) return res.json({ score: null });

        res.json({
            score: result.rows[0].total_weighted_score,
            generated_at: result.rows[0].generated_at
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
// ════════════════════════════════════════════════════════════
// ADMIN ENDPOINTLERİ
// Tüm admin endpoint'leri Yol A ile korunur:
//   - admin_user_id body/query parametresi olarak alınır
//   - USERS tablosunda bu kullanıcının role='Admin' olduğu doğrulanır
//   - Eşleşmezse 403 döner
// ════════════════════════════════════════════════════════════

// Yardımcı: admin_user_id gerçekten Admin mi?
async function verifyAdmin(adminUserId) {
    if (!adminUserId) return false;
    const result = await pool.query(
        'SELECT role FROM USERS WHERE user_id = $1',
        [adminUserId]
    );
    if (result.rows.length === 0) return false;
    return result.rows[0].role === 'Admin';
}

// ────────────────────────────────────────────────────────────
// GET /api/admin/audit-log
// Query params:
//   - admin_user_id (zorunlu)    → Admin doğrulaması için
//   - actor_user_id (opsiyonel)  → Kim yaptı filtresi
//   - project_id    (opsiyonel)  → Hangi proje filtresi
//   - action_type   (opsiyonel)  → 'CREATE' | 'UPDATE' | 'ADMIN_OVERRIDE'
//   - date_from     (opsiyonel)  → ISO date
//   - date_to       (opsiyonel)  → ISO date
//   - limit         (opsiyonel)  → default 100, max 500
// ────────────────────────────────────────────────────────────
app.get('/api/admin/audit-log', async (req, res) => {
    const {
        admin_user_id,
        actor_user_id,
        project_id,
        action_type,
        date_from,
        date_to,
        limit
    } = req.query;

    // Admin kontrolü
    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) {
        return res.status(403).json({ error: 'Admin privileges required.' });
    }

    // action_type validasyonu (beklenmeyen değer gelirse direkt reddet)
    if (action_type && !['CREATE', 'UPDATE', 'ADMIN_OVERRIDE'].includes(action_type)) {
        return res.status(400).json({ error: 'Invalid action_type.' });
    }

    // Dinamik WHERE kurulumu — parametreleri sırayla $1, $2, ... diye diz
    const conditions = [];
    const params = [];
    let i = 1;

    if (actor_user_id) {
        conditions.push(`a.actor_user_id = $${i++}`);
        params.push(actor_user_id);
    }
    if (project_id) {
        conditions.push(`a.project_id = $${i++}`);
        params.push(project_id);
    }
    if (action_type) {
        conditions.push(`a.action_type = $${i++}`);
        params.push(action_type);
    }
    if (date_from) {
        conditions.push(`a.timestamp >= $${i++}`);
        params.push(date_from);
    }
    if (date_to) {
        conditions.push(`a.timestamp <= $${i++}`);
        params.push(date_to);
    }

    const whereClause = conditions.length > 0
        ? 'WHERE ' + conditions.join(' AND ')
        : '';

    // Limit: 1-500 arası, default 100
    let limitNum = parseInt(limit) || 100;
    if (limitNum < 1) limitNum = 1;
    if (limitNum > 500) limitNum = 500;

    try {
        const result = await pool.query(`
            SELECT
                a.audit_id,
                a.action_type,
                a.old_score,
                a.new_score,
                a.comment,
                a.timestamp,
                a.evaluation_id,
                a.project_id,
                a.student_id,
                a.criteria_id,
                actor.user_id       AS actor_user_id,
                actor.name          AS actor_name,
                actor.role          AS actor_role,
                student.name        AS student_name,
                p.project_name      AS project_name,
                c.criteria_name     AS criteria_name
            FROM AUDIT_LOG a
            LEFT JOIN USERS    actor   ON a.actor_user_id = actor.user_id
            LEFT JOIN USERS    student ON a.student_id    = student.user_id
            LEFT JOIN PROJECTS p       ON a.project_id    = p.project_id
            LEFT JOIN CRITERIA c       ON a.criteria_id   = c.criteria_id
            ${whereClause}
            ORDER BY a.timestamp DESC
            LIMIT ${limitNum}
        `, params);

        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ────────────────────────────────────────────────────────────
// PUT /api/admin/evaluations/:evaluationId
// Admin override — submit edilmiş bir evaluation'ın puanını değiştirir
// Body: { new_score, comment, admin_user_id }
// ────────────────────────────────────────────────────────────


// ────────────────────────────────────────────────────────────
// GET /api/admin/statistics
// Admin ekranındaki özet kartları için sayılar
// Query: admin_user_id (zorunlu)
// ────────────────────────────────────────────────────────────
app.get('/api/admin/statistics', async (req, res) => {
    const { admin_user_id } = req.query;

    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) {
        return res.status(403).json({ error: 'Admin privileges required.' });
    }

    try {
        // Paralel sorgular
        const [
            projectCount,
            evaluationCount,
            auditCount,
            overrideCount,
            juryCount,
            studentCount,
            finalResultCount
        ] = await Promise.all([
            pool.query('SELECT COUNT(*)::int AS c FROM PROJECTS'),
            pool.query('SELECT COUNT(*)::int AS c FROM EVALUATIONS'),
            pool.query('SELECT COUNT(*)::int AS c FROM AUDIT_LOG'),
            pool.query(`SELECT COUNT(*)::int AS c FROM AUDIT_LOG WHERE action_type = 'ADMIN_OVERRIDE'`),
            pool.query(`SELECT COUNT(*)::int AS c FROM USERS WHERE role = 'Jury'`),
            pool.query(`SELECT COUNT(*)::int AS c FROM USERS WHERE role = 'Student'`),
            pool.query('SELECT COUNT(*)::int AS c FROM FINAL_RESULTS'),
        ]);

        res.json({
            total_projects:       projectCount.rows[0].c,
            total_evaluations:    evaluationCount.rows[0].c,
            total_audit_records:  auditCount.rows[0].c,
            total_admin_overrides: overrideCount.rows[0].c,
            total_jury:           juryCount.rows[0].c,
            total_students:       studentCount.rows[0].c,
            total_final_results:  finalResultCount.rows[0].c,
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ════════════════════════════════════════════════════════════
// UNLOCK REQUEST ENDPOINTLERİ
// Jüri → Admin akışı:
//   1. Jüri locked evaluation için unlock isteği gönderir (reason ile)
//   2. Admin bekleyen istekleri görür, approve veya deny eder
//   3. Approve edilirse EVALUATIONS.is_submitted = FALSE yapılır
//      → jüri yeniden submit edebilir
// ════════════════════════════════════════════════════════════

// ────────────────────────────────────────────────────────────
// POST /api/unlock-requests
// Jüri yeni unlock isteği oluşturur
// Body: { evaluation_id, requested_by (jury user_id), reason }
// ────────────────────────────────────────────────────────────
app.post('/api/unlock-requests', async (req, res) => {
    const { evaluation_id, requested_by, reason } = req.body;

    if (!evaluation_id || !requested_by || !reason || reason.trim().length === 0) {
        return res.status(400).json({ 
            error: 'evaluation_id, requested_by and reason are required.' 
        });
    }

    try {
        // Evaluation gerçekten bu jüriye mi ait? (ownership kontrolü)
        const evalCheck = await pool.query(
            'SELECT evaluation_id, jury_id, project_id, student_id, criteria_id, is_submitted FROM EVALUATIONS WHERE evaluation_id = $1',
            [evaluation_id]
        );
        if (evalCheck.rows.length === 0) {
            return res.status(404).json({ error: 'Evaluation not found.' });
        }
        const evaluation = evalCheck.rows[0];
        if (evaluation.jury_id !== requested_by) {
            return res.status(403).json({ 
                error: 'You can only request unlock for your own evaluations.' 
            });
        }
        if (!evaluation.is_submitted) {
            return res.status(400).json({ 
                error: 'This evaluation is already unlocked.' 
            });
        }

        // Zaten bekleyen PENDING istek var mı?
        const pendingCheck = await pool.query(
            `SELECT request_id FROM UNLOCK_REQUESTS 
             WHERE evaluation_id = $1 AND status = 'PENDING'`,
            [evaluation_id]
        );
        if (pendingCheck.rows.length > 0) {
            return res.status(409).json({ 
                error: 'There is already a pending unlock request for this evaluation.' 
            });
        }

        // Yeni istek oluştur
        const result = await pool.query(`
            INSERT INTO UNLOCK_REQUESTS (evaluation_id, requested_by, reason)
            VALUES ($1, $2, $3)
            RETURNING *
        `, [evaluation_id, requested_by, reason.trim()]);

        // Audit log
        await logAudit({
            actorUserId:  requested_by,
            actionType:   'UNLOCK_REQUESTED',
            evaluationId: evaluation_id,
            projectId:    evaluation.project_id,
            studentId:    evaluation.student_id,
            criteriaId:   evaluation.criteria_id,
            oldScore:     null,
            newScore:     null,
            comment:      reason.trim(),
        });

        res.status(201).json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ────────────────────────────────────────────────────────────
// GET /api/unlock-requests/jury/:juryId
// Bir jürinin kendi gönderdiği unlock isteklerini getir
// (locked view'da "Request Unlock" butonunu gizlemek için — zaten pending varsa buton görünmesin)
// ────────────────────────────────────────────────────────────
app.get('/api/unlock-requests/jury/:juryId', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT ur.*, c.criteria_name, p.project_name, s.name AS student_name
            FROM UNLOCK_REQUESTS ur
            JOIN EVALUATIONS e  ON ur.evaluation_id = e.evaluation_id
            JOIN CRITERIA    c  ON e.criteria_id    = c.criteria_id
            JOIN PROJECTS    p  ON e.project_id     = p.project_id
            JOIN USERS       s  ON e.student_id     = s.user_id
            WHERE ur.requested_by = $1
            ORDER BY ur.created_at DESC
        `, [req.params.juryId]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ────────────────────────────────────────────────────────────
// GET /api/admin/unlock-requests
// Admin tüm unlock isteklerini görür (default: sadece PENDING)
// Query: admin_user_id (zorunlu), status (opsiyonel: PENDING/APPROVED/DENIED/ALL)
// ────────────────────────────────────────────────────────────
app.get('/api/admin/unlock-requests', async (req, res) => {
    const { admin_user_id, status } = req.query;

    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) {
        return res.status(403).json({ error: 'Admin privileges required.' });
    }

    const statusFilter = status || 'PENDING';
    if (!['PENDING', 'APPROVED', 'DENIED', 'ALL'].includes(statusFilter)) {
        return res.status(400).json({ error: 'Invalid status filter.' });
    }

    const whereClause = statusFilter === 'ALL' 
        ? '' 
        : `WHERE ur.status = '${statusFilter}'`;

    try {
        const result = await pool.query(`
            SELECT 
                ur.request_id,
                ur.evaluation_id,
                ur.reason,
                ur.status,
                ur.admin_comment,
                ur.created_at,
                ur.reviewed_at,
                jury.user_id      AS jury_id,
                jury.name         AS jury_name,
                reviewer.name     AS reviewer_name,
                e.score,
                c.criteria_name,
                p.project_id,
                p.project_name,
                student.name      AS student_name
            FROM UNLOCK_REQUESTS ur
            JOIN USERS       jury     ON ur.requested_by = jury.user_id
            LEFT JOIN USERS  reviewer ON ur.reviewed_by  = reviewer.user_id
            JOIN EVALUATIONS e        ON ur.evaluation_id = e.evaluation_id
            JOIN CRITERIA    c        ON e.criteria_id    = c.criteria_id
            JOIN PROJECTS    p        ON e.project_id     = p.project_id
            JOIN USERS       student  ON e.student_id     = student.user_id
            ${whereClause}
            ORDER BY ur.created_at DESC
        `);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ────────────────────────────────────────────────────────────
// PUT /api/admin/unlock-requests/:requestId
// Admin bir isteği approve veya deny eder
// Body: { decision: 'APPROVE' | 'DENY', admin_comment, admin_user_id }
// APPROVE → EVALUATIONS.is_submitted = FALSE → jüri yeniden submit edebilir
// DENY    → sadece kayıt güncellenir, evaluation kilitli kalır
// ────────────────────────────────────────────────────────────
app.put('/api/admin/unlock-requests/:requestId', async (req, res) => {
    const { requestId } = req.params;
    const { decision, admin_comment, admin_user_id } = req.body;

    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) {
        return res.status(403).json({ error: 'Admin privileges required.' });
    }

    if (!['APPROVE', 'DENY'].includes(decision)) {
        return res.status(400).json({ 
            error: "decision must be 'APPROVE' or 'DENY'." 
        });
    }

    try {
        // İsteği çek, hâlâ PENDING mi?
        const reqCheck = await pool.query(
            `SELECT ur.*, e.project_id, e.student_id, e.criteria_id
             FROM UNLOCK_REQUESTS ur
             JOIN EVALUATIONS e ON ur.evaluation_id = e.evaluation_id
             WHERE ur.request_id = $1`,
            [requestId]
        );
        if (reqCheck.rows.length === 0) {
            return res.status(404).json({ error: 'Unlock request not found.' });
        }
        const request = reqCheck.rows[0];
        if (request.status !== 'PENDING') {
            return res.status(400).json({ 
                error: `This request is already ${request.status.toLowerCase()}.` 
            });
        }

        const newStatus = decision === 'APPROVE' ? 'APPROVED' : 'DENIED';

        // İsteği güncelle
        const updated = await pool.query(`
            UPDATE UNLOCK_REQUESTS
            SET status = $1, reviewed_by = $2, reviewed_at = NOW(), admin_comment = $3
            WHERE request_id = $4
            RETURNING *
        `, [newStatus, admin_user_id, admin_comment ?? null, requestId]);

        // Approve ise evaluation'ı unlock et
        if (decision === 'APPROVE') {
            await pool.query(
                'UPDATE EVALUATIONS SET is_submitted = FALSE WHERE evaluation_id = $1',
                [request.evaluation_id]
            );
        }

        // Audit log
        await logAudit({
            actorUserId:  admin_user_id,
            actionType:   decision === 'APPROVE' ? 'UNLOCK_APPROVED' : 'UNLOCK_DENIED',
            evaluationId: request.evaluation_id,
            projectId:    request.project_id,
            studentId:    request.student_id,
            criteriaId:   request.criteria_id,
            oldScore:     null,
            newScore:     null,
            comment:      admin_comment ?? null,
        });

        res.json(updated.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

