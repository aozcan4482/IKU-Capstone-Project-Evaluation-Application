// ============================================================
// Graduation Project Evaluation System - Final Backend Server
// Base: server_v3 (per-student eval, project status, workflow)
// + Task 5: Admin bypass login, AUDIT_LOG, UNLOCK_REQUESTS,
//           is_submitted lock, verifyAdmin, logAudit
// ============================================================

const express = require('express');
const { Pool } = require('pg');
const axios   = require('axios');

const app  = express();
const PORT = 3000;

app.use(express.json());

// ── Veritabanı Bağlantısı ─────────────────────────────────
const pool = new Pool({
    host:     'localhost',
    port:     5432,
    database: 'graduation_db',
    user:     'postgres',
    password: '', 
});

// ════════════════════════════════════════════════════════════
// YARDIMCI: CATS username'den kullanıcıyı DB'den bul
// ════════════════════════════════════════════════════════════
async function getUserByCatsUsername(catsUsername) {
    const result = await pool.query(
        'SELECT user_id, cats_username, name, email, role FROM USERS WHERE cats_username = $1',
        [catsUsername]
    );
    if (result.rows.length === 0) return null;
    return result.rows[0];
}

// ════════════════════════════════════════════════════════════
// YARDIMCI: Bir öğrencinin ağırlıklı final skorunu hesapla
// ════════════════════════════════════════════════════════════
async function calculateWeightedAverageForStudent(projectId, studentId) {
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

    const scores     = Object.values(juryScores);
    const totalScore = scores.reduce((sum, s) => sum + s, 0);
    return Math.round((totalScore / scores.length) * 100) / 100;
}

// ════════════════════════════════════════════════════════════
// YARDIMCI: Proje status'ünü güncelle
// Pending → In Progress → Completed → Finalized
// ════════════════════════════════════════════════════════════
async function updateProjectStatus(projectId) {
    const criteriaCount  = await pool.query('SELECT COUNT(*) FROM CRITERIA');
    const totalCriteria  = parseInt(criteriaCount.rows[0].count);

    const membersRes     = await pool.query(
        'SELECT COUNT(*) FROM PROJECT_MEMBERS WHERE project_id = $1', [projectId]
    );
    const totalStudents  = parseInt(membersRes.rows[0].count);

    const assignmentsRes = await pool.query(
        'SELECT COUNT(*) FROM JURY_ASSIGNMENTS WHERE project_id = $1', [projectId]
    );
    const totalJuries    = parseInt(assignmentsRes.rows[0].count);

    // Finalized: tüm öğrencilerin final skoru hesaplanmış
    const finalRes = await pool.query(
        'SELECT COUNT(*) FROM FINAL_RESULTS WHERE project_id = $1', [projectId]
    );
    const finalCount = parseInt(finalRes.rows[0].count);
    if (totalStudents > 0 && finalCount === totalStudents) {
        await pool.query(`UPDATE PROJECTS SET status = 'Finalized' WHERE project_id = $1`, [projectId]);
        return 'Finalized';
    }

    // Bir jürinin tamamlanmış sayılması: her öğrenciye her kriterden puan vermiş olması
    const evalsPerJury    = totalCriteria * totalStudents;
    const completedJuries = await pool.query(`
        SELECT jury_id, COUNT(*) AS done_count
        FROM EVALUATIONS
        WHERE project_id = $1
        GROUP BY jury_id
        HAVING COUNT(*) = $2
    `, [projectId, evalsPerJury]);

    const completedCount = completedJuries.rows.length;

    let status;
    if (completedCount === 0) {
        const anyEval = await pool.query(
            'SELECT COUNT(*) FROM EVALUATIONS WHERE project_id = $1', [projectId]
        );
        status = parseInt(anyEval.rows[0].count) === 0 ? 'Pending' : 'In Progress';
    } else if (completedCount < totalJuries) {
        status = 'In Progress';
    } else {
        status = 'Completed';
    }

    await pool.query('UPDATE PROJECTS SET status = $1 WHERE project_id = $2', [status, projectId]);

    // is_completed bayraklarını güncelle
    for (const row of completedJuries.rows) {
        await pool.query(`
            UPDATE JURY_ASSIGNMENTS
            SET is_completed = TRUE, completed_at = NOW()
            WHERE jury_id = $1 AND project_id = $2 AND is_completed = FALSE
        `, [row.jury_id, projectId]);
    }

    return status;
}

// ════════════════════════════════════════════════════════════
// YARDIMCI: Admin doğrulama
// ════════════════════════════════════════════════════════════
async function verifyAdmin(adminUserId) {
    if (!adminUserId) return false;
    const result = await pool.query(
        'SELECT role FROM USERS WHERE user_id = $1', [adminUserId]
    );
    if (result.rows.length === 0) return false;
    return result.rows[0].role === 'Admin';
}

// ════════════════════════════════════════════════════════════
// YARDIMCI: Audit log kaydı oluştur
// ════════════════════════════════════════════════════════════
async function logAudit({
    actorUserId, actionType, evaluationId,
    projectId, studentId, criteriaId,
    oldScore, newScore, comment = null,
}) {
    try {
        await pool.query(`
            INSERT INTO AUDIT_LOG
                (actor_user_id, action_type, evaluation_id, project_id,
                 student_id, criteria_id, old_score, new_score, comment)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [actorUserId, actionType, evaluationId, projectId,
            studentId, criteriaId, oldScore, newScore, comment]);
    } catch (err) {
        console.error('Audit log error:', err.message);
    }
}

// ════════════════════════════════════════════════════════════
// AUTH
// ════════════════════════════════════════════════════════════
app.post('/api/auth/login', async (req, res) => {
    const { cats_username, password } = req.body;

    // Önce kullanıcıyı DB'den bul
    const user = await getUserByCatsUsername(cats_username);
    if (!user) {
        return res.status(403).json({ error: 'User not found in database' });
    }

    const isAdmin = user.role === 'Admin';

    if (!isAdmin) {
        // Normal Jury/Student: CATS doğrulaması
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
        // Admin: basit şifre kontrolü
        if (password !== 'admin123') {
            return res.status(401).json({ error: 'Authentication failed' });
        }
    }

    if (!['Jury', 'Student', 'Admin'].includes(user.role)) {
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
// USERS
// ════════════════════════════════════════════════════════════
app.post('/api/users', async (req, res) => {
    const { cats_username, name, email, role } = req.body;
    const result = await pool.query(
        'INSERT INTO USERS (cats_username, name, email, role) VALUES ($1,$2,$3,$4) RETURNING user_id, cats_username, name, email, role',
        [cats_username, name, email, role]
    );
    res.status(201).json(result.rows[0]);
});

app.get('/api/users', async (req, res) => {
    const result = await pool.query(
        'SELECT user_id, cats_username, name, email, role FROM USERS ORDER BY user_id'
    );
    res.json(result.rows);
});

app.get('/api/users/:id', async (req, res) => {
    const result = await pool.query(
        'SELECT user_id, cats_username, name, email, role FROM USERS WHERE user_id = $1',
        [req.params.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ error: 'User not found' });
    res.json(result.rows[0]);
});

// ════════════════════════════════════════════════════════════
// PROJECTS
// ════════════════════════════════════════════════════════════
app.post('/api/projects', async (req, res) => {
    const { project_name, student_id, description, advisor, 
            exam_datetime, member_ids, advisor_id } = req.body;
    try {
        let finalName = project_name;
        if (!finalName || finalName.trim() === '') {
            const countRes = await pool.query('SELECT COUNT(*) FROM PROJECTS');
            finalName = `New Project ${parseInt(countRes.rows[0].count) + 1}`;
        }

        // student_id zorunlu olduğu için geçici olarak admin'i (user_id=10) koy
        const tempStudentId = student_id || 10;

        const result = await pool.query(
            `INSERT INTO PROJECTS 
                (project_name, student_id, description, advisor, exam_datetime, advisor_id)
             VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
            [finalName, tempStudentId, description || '', 
             advisor || '', exam_datetime || null, advisor_id || null]
        );
        const project = result.rows[0];

        if (Array.isArray(member_ids)) {
            for (const memberId of member_ids) {
                await pool.query(
                    'INSERT INTO PROJECT_MEMBERS (project_id, student_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',
                    [project.project_id, memberId]
                );
            }
        }

        const membersRes = await pool.query(`
            SELECT u.user_id, u.name, u.cats_username
            FROM PROJECT_MEMBERS pm
            JOIN USERS u ON pm.student_id = u.user_id
            WHERE pm.project_id = $1
        `, [project.project_id]);

        res.status(201).json({ ...project, members: membersRes.rows });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/projects', async (req, res) => {
    try {
        const projectsResult = await pool.query(`
            SELECT p.project_id, p.project_name, p.description, p.advisor,
                   p.exam_datetime, p.status, u.name AS student_name
            FROM PROJECTS p
            JOIN USERS u ON p.student_id = u.user_id
            ORDER BY p.project_id
        `);

        const projects = await Promise.all(projectsResult.rows.map(async (project) => {
            const membersResult = await pool.query(`
                SELECT u.user_id, u.name, u.cats_username
                FROM PROJECT_MEMBERS pm
                JOIN USERS u ON pm.student_id = u.user_id
                WHERE pm.project_id = $1
            `, [project.project_id]);
            return { ...project, members: membersResult.rows };
        }));

        res.json(projects);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});


app.get('/api/projects/advisor/:advisorId', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT p.project_id, p.project_name, p.description,
                   p.advisor, p.exam_datetime, p.status,
                   u.name AS advisor_name
            FROM PROJECTS p
            LEFT JOIN USERS u ON p.advisor_id = u.user_id
            WHERE p.advisor_id = $1
            ORDER BY p.project_id
        `, [req.params.advisorId]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/projects/status/:status', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT p.project_id, p.project_name, p.status, p.exam_datetime, u.name AS student_name
            FROM PROJECTS p JOIN USERS u ON p.student_id = u.user_id
            WHERE p.status = $1 ORDER BY p.exam_datetime
        `, [req.params.status]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/projects/:id', async (req, res) => {
    try {
        const projectRes = await pool.query(
            'SELECT * FROM PROJECTS WHERE project_id = $1', [req.params.id]
        );
        if (projectRes.rows.length === 0) return res.status(404).json({ error: 'Project not found' });

        const membersRes = await pool.query(`
            SELECT u.user_id, u.name, u.cats_username, u.email
            FROM PROJECT_MEMBERS pm
            JOIN USERS u ON pm.student_id = u.user_id
            WHERE pm.project_id = $1
        `, [req.params.id]);

        res.json({ ...projectRes.rows[0], members: membersRes.rows });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/projects/:id/members', async (req, res) => {
    try {
        const { student_id } = req.body;
        const result = await pool.query(
            `INSERT INTO PROJECT_MEMBERS (project_id, student_id)
             VALUES ($1,$2) ON CONFLICT (project_id, student_id) DO NOTHING RETURNING *`,
            [req.params.id, student_id]
        );
        if (result.rows.length === 0)
            return res.status(409).json({ error: 'Student is already a member' });
        res.status(201).json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.delete('/api/projects/:id/members/:studentId', async (req, res) => {
    try {
        const result = await pool.query(
            'DELETE FROM PROJECT_MEMBERS WHERE project_id = $1 AND student_id = $2 RETURNING *',
            [req.params.id, req.params.studentId]
        );
        if (result.rows.length === 0) return res.status(404).json({ error: 'Member not found' });
        res.json({ message: 'Member removed', deleted: result.rows[0] });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/projects/:id/members', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT u.user_id, u.name, u.cats_username, u.email
            FROM PROJECT_MEMBERS pm
            JOIN USERS u ON pm.student_id = u.user_id
            WHERE pm.project_id = $1 ORDER BY u.name
        `, [req.params.id]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Proje durum/workflow endpoint'leri
app.get('/api/projects/:id/state', async (req, res) => {
    try {
        const projectId = req.params.id;
        const projectRes = await pool.query(
            'SELECT project_id, project_name, status FROM PROJECTS WHERE project_id = $1', [projectId]
        );
        if (projectRes.rows.length === 0) return res.status(404).json({ error: 'Project not found' });

        const totalCriteria  = parseInt((await pool.query('SELECT COUNT(*) FROM CRITERIA')).rows[0].count);
        const totalStudents  = parseInt((await pool.query('SELECT COUNT(*) FROM PROJECT_MEMBERS WHERE project_id = $1', [projectId])).rows[0].count);
        const totalJuries    = parseInt((await pool.query('SELECT COUNT(*) FROM JURY_ASSIGNMENTS WHERE project_id = $1', [projectId])).rows[0].count);
        const completedJuries= parseInt((await pool.query('SELECT COUNT(*) FROM JURY_ASSIGNMENTS WHERE project_id = $1 AND is_completed = TRUE', [projectId])).rows[0].count);
        const submittedEvals = parseInt((await pool.query('SELECT COUNT(*) FROM EVALUATIONS WHERE project_id = $1', [projectId])).rows[0].count);
        const finalRes       = await pool.query('SELECT * FROM FINAL_RESULTS WHERE project_id = $1', [projectId]);

        const expectedEvals  = totalJuries * totalStudents * totalCriteria;
        const isFinalized    = finalRes.rows.length > 0 && finalRes.rows.length === totalStudents;

        res.json({
            project_id:            projectRes.rows[0].project_id,
            project_name:          projectRes.rows[0].project_name,
            status:                projectRes.rows[0].status,
            total_students:        totalStudents,
            total_juries:          totalJuries,
            completed_juries:      completedJuries,
            pending_juries:        totalJuries - completedJuries,
            submitted_evaluations: submittedEvals,
            expected_evaluations:  expectedEvals,
            pending_evaluations:   expectedEvals - submittedEvals,
            completion_percent:    expectedEvals === 0 ? 0 : Math.round((submittedEvals / expectedEvals) * 100),
            is_finalized:          isFinalized,
            final_results:         finalRes.rows
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.post('/api/projects/:id/recalculate-status', async (req, res) => {
    try {
        const newStatus = await updateProjectStatus(req.params.id);
        res.json({ project_id: req.params.id, status: newStatus });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});



// ════════════════════════════════════════════════════════════
// CRITERIA
// ════════════════════════════════════════════════════════════
app.get('/api/criteria', async (req, res) => {
    const result = await pool.query('SELECT * FROM CRITERIA ORDER BY criteria_id');
    res.json(result.rows);
});

app.post('/api/criteria', async (req, res) => {
    const { criteria_name, weight } = req.body;
    const result = await pool.query(
        'INSERT INTO CRITERIA (criteria_name, weight) VALUES ($1,$2) RETURNING *',
        [criteria_name, weight]
    );
    res.status(201).json(result.rows[0]);
});

// ════════════════════════════════════════════════════════════
// EVALUATIONS
// Lock kontrollü upsert + audit log + project status güncelleme
// ════════════════════════════════════════════════════════════
app.post('/api/evaluations', async (req, res) => {
    const { jury_id, project_id, student_id, criteria_id, score, comment } = req.body;

    if (score < 0 || score > 100)
        return res.status(400).json({ error: 'Score must be between 0 and 100.' });
    if (!student_id)
        return res.status(400).json({ error: 'student_id is required.' });

    try {
        const existingRes = await pool.query(`
            SELECT evaluation_id, score, is_submitted FROM EVALUATIONS
            WHERE jury_id = $1 AND project_id = $2 AND criteria_id = $3 AND student_id = $4
        `, [jury_id, project_id, criteria_id, student_id]);

        const isUpdate     = existingRes.rows.length > 0;
        const oldScore     = isUpdate ? existingRes.rows[0].score : null;
        const wasSubmitted = isUpdate ? existingRes.rows[0].is_submitted : false;

        // Lock kontrolü
        if (isUpdate && wasSubmitted) {
            return res.status(403).json({
                error: 'This evaluation is locked. Request an unlock from admin to modify it.'
            });
        }

        const isResubmit = isUpdate && !wasSubmitted;

        const result = await pool.query(`
            INSERT INTO EVALUATIONS (jury_id, project_id, student_id, criteria_id, score, comment, is_submitted)
            VALUES ($1,$2,$3,$4,$5,$6,TRUE)
            ON CONFLICT (jury_id, project_id, student_id, criteria_id)
            DO UPDATE SET score = EXCLUDED.score, comment = EXCLUDED.comment,
                          submitted_at = NOW(), is_submitted = TRUE
            RETURNING *
        `, [jury_id, project_id, student_id, criteria_id, score, comment]);

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

        const newStatus = await updateProjectStatus(project_id);

        res.status(201).json({ ...result.rows[0], project_status: newStatus });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Jürinin kendi evaluation'ları (tüm projeler)
app.get('/api/evaluations/jury/:juryId', async (req, res) => {
    const result = await pool.query(`
        SELECT e.evaluation_id, p.project_name,
               u.name AS student_name, u.user_id AS student_id,
               c.criteria_name, c.weight, e.score, e.comment, e.is_submitted
        FROM EVALUATIONS e
        JOIN PROJECTS  p ON e.project_id  = p.project_id
        JOIN USERS     u ON e.student_id  = u.user_id
        JOIN CRITERIA  c ON e.criteria_id = c.criteria_id
        WHERE e.jury_id = $1
        ORDER BY e.project_id, e.student_id, c.criteria_id
    `, [req.params.juryId]);
    res.json(result.rows);
});

// Jürinin belirli bir projedeki evaluation'ları (is_submitted dahil)
// Flutter bu endpoint'i kullanarak unlock durumunu öğrenir
app.get('/api/evaluations/jury/:juryId/project/:projectId', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT e.evaluation_id, e.student_id, e.criteria_id,
                   c.criteria_name, c.weight, e.score, e.comment, e.is_submitted
            FROM EVALUATIONS e
            JOIN CRITERIA c ON e.criteria_id = c.criteria_id
            WHERE e.jury_id = $1 AND e.project_id = $2
        `, [req.params.juryId, req.params.projectId]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/evaluations/:id/jury/:juryId', async (req, res) => {
    const result = await pool.query(
        'SELECT * FROM EVALUATIONS WHERE evaluation_id = $1 AND jury_id = $2',
        [req.params.id, req.params.juryId]
    );
    if (result.rows.length === 0)
        return res.status(403).json({ error: 'Access denied. This evaluation does not belong to you.' });
    res.json(result.rows[0]);
});

app.put('/api/evaluations/:id/jury/:juryId', async (req, res) => {
    const { score, comment } = req.body;
    const result = await pool.query(
        `UPDATE EVALUATIONS SET score = $1, comment = $2, submitted_at = NOW()
         WHERE evaluation_id = $3 AND jury_id = $4 RETURNING *`,
        [score, comment, req.params.id, req.params.juryId]
    );
    if (result.rows.length === 0)
        return res.status(403).json({ error: 'Access denied or evaluation not found.' });

    await updateProjectStatus(result.rows[0].project_id);
    res.json(result.rows[0]);
});

// Bir projenin tüm evaluation'ları
app.get('/api/evaluations/project/:projectId', async (req, res) => {
    const result = await pool.query(`
        SELECT e.evaluation_id, u.name AS jury_name,
               s.name AS student_name, s.user_id AS student_id,
               c.criteria_name, c.weight, e.score, e.comment, e.is_submitted
        FROM EVALUATIONS e
        JOIN USERS    u ON e.jury_id     = u.user_id
        JOIN USERS    s ON e.student_id  = s.user_id
        JOIN CRITERIA c ON e.criteria_id = c.criteria_id
        WHERE e.project_id = $1
        ORDER BY e.jury_id, e.student_id, c.criteria_id
    `, [req.params.projectId]);
    res.json(result.rows);
});

// Belirli bir öğrencinin evaluation'ları
app.get('/api/evaluations/project/:projectId/student/:studentId', async (req, res) => {
    const result = await pool.query(`
        SELECT e.evaluation_id, u.name AS jury_name,
               c.criteria_name, c.weight, e.score, e.comment, e.is_submitted
        FROM EVALUATIONS e
        JOIN USERS    u ON e.jury_id     = u.user_id
        JOIN CRITERIA c ON e.criteria_id = c.criteria_id
        WHERE e.project_id = $1 AND e.student_id = $2
        ORDER BY e.jury_id, c.criteria_id
    `, [req.params.projectId, req.params.studentId]);
    res.json(result.rows);
});

// Jürinin bekleyen evaluation'ları
app.get('/api/jury/:juryId/pending-evaluations', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT ja.project_id, p.project_name,
                   pm.student_id, s.name AS student_name,
                   c.criteria_id, c.criteria_name, c.weight
            FROM JURY_ASSIGNMENTS ja
            JOIN PROJECTS p         ON ja.project_id = p.project_id
            JOIN PROJECT_MEMBERS pm ON pm.project_id = p.project_id
            JOIN USERS s            ON pm.student_id = s.user_id
            CROSS JOIN CRITERIA c
            WHERE ja.jury_id = $1
              AND NOT EXISTS (
                  SELECT 1 FROM EVALUATIONS e
                  WHERE e.jury_id     = ja.jury_id
                    AND e.project_id  = ja.project_id
                    AND e.student_id  = pm.student_id
                    AND e.criteria_id = c.criteria_id
              )
            ORDER BY p.project_id, pm.student_id, c.criteria_id
        `, [req.params.juryId]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Jürinin ilerleme durumu
app.get('/api/jury/:juryId/progress', async (req, res) => {
    try {
        const juryId        = req.params.juryId;
        const totalCriteria = parseInt((await pool.query('SELECT COUNT(*) FROM CRITERIA')).rows[0].count);
        const totalProjects = parseInt((await pool.query('SELECT COUNT(*) FROM JURY_ASSIGNMENTS WHERE jury_id = $1', [juryId])).rows[0].count);

        const studentCountRes = await pool.query(`
            SELECT COUNT(*) FROM PROJECT_MEMBERS pm
            WHERE pm.project_id IN (SELECT project_id FROM JURY_ASSIGNMENTS WHERE jury_id = $1)
        `, [juryId]);
        const totalStudents   = parseInt(studentCountRes.rows[0].count);

        const completedProjects = parseInt((await pool.query(
            'SELECT COUNT(*) FROM JURY_ASSIGNMENTS WHERE jury_id = $1 AND is_completed = TRUE', [juryId]
        )).rows[0].count);

        const submittedEvals = parseInt((await pool.query(
            'SELECT COUNT(*) FROM EVALUATIONS WHERE jury_id = $1', [juryId]
        )).rows[0].count);
        const expectedEvals  = totalStudents * totalCriteria;

        res.json({
            jury_id:               juryId,
            total_projects:        totalProjects,
            total_students:        totalStudents,
            completed_projects:    completedProjects,
            pending_projects:      totalProjects - completedProjects,
            submitted_evaluations: submittedEvals,
            expected_evaluations:  expectedEvals,
            pending_evaluations:   expectedEvals - submittedEvals,
            completion_percent:    expectedEvals === 0 ? 0 : Math.round((submittedEvals / expectedEvals) * 100)
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ════════════════════════════════════════════════════════════
// FINAL RESULTS
// ════════════════════════════════════════════════════════════
app.post('/api/results/:projectId', async (req, res) => {
    const projectId = req.params.projectId;

    const statusCheck = await pool.query('SELECT status FROM PROJECTS WHERE project_id = $1', [projectId]);
    if (statusCheck.rows.length === 0)
        return res.status(404).json({ error: 'Project not found' });
    if (statusCheck.rows[0].status !== 'Completed') {
        return res.status(400).json({
            error: 'Cannot finalize — project is not in Completed state.',
            current_status: statusCheck.rows[0].status
        });
    }

    const membersRes = await pool.query(
        'SELECT student_id FROM PROJECT_MEMBERS WHERE project_id = $1', [projectId]
    );

    const results = [];
    for (const member of membersRes.rows) {
        const studentId  = member.student_id;
        const finalScore = await calculateWeightedAverageForStudent(projectId, studentId);

        const result = await pool.query(`
            INSERT INTO FINAL_RESULTS (project_id, student_id, total_weighted_score)
            VALUES ($1,$2,$3)
            ON CONFLICT (project_id, student_id)
            DO UPDATE SET total_weighted_score = EXCLUDED.total_weighted_score, generated_at = NOW()
            RETURNING *
        `, [projectId, studentId, finalScore]);

        results.push(result.rows[0]);
    }

    await updateProjectStatus(projectId);

    res.status(201).json({
        message:    'Final scores calculated for all students',
        project_id: projectId,
        status:     'Finalized',
        results:    results
    });
});

app.get('/api/results', async (req, res) => {
    const result = await pool.query(`
        SELECT fr.result_id, p.project_name,
               u.name AS student_name, u.user_id AS student_id,
               fr.total_weighted_score, fr.generated_at
        FROM FINAL_RESULTS fr
        JOIN PROJECTS p ON fr.project_id = p.project_id
        JOIN USERS    u ON fr.student_id  = u.user_id
        ORDER BY fr.generated_at DESC
    `);
    res.json(result.rows);
});

app.get('/api/results/:projectId', async (req, res) => {
    const result = await pool.query(`
        SELECT fr.*, u.name AS student_name
        FROM FINAL_RESULTS fr
        JOIN USERS u ON fr.student_id = u.user_id
        WHERE fr.project_id = $1 ORDER BY u.name
    `, [req.params.projectId]);
    if (result.rows.length === 0)
        return res.status(404).json({ error: 'No results found for this project' });
    res.json(result.rows);
});

app.get('/api/results/:projectId/student/:studentId', async (req, res) => {
    const result = await pool.query(`
        SELECT fr.*, u.name AS student_name
        FROM FINAL_RESULTS fr JOIN USERS u ON fr.student_id = u.user_id
        WHERE fr.project_id = $1 AND fr.student_id = $2
    `, [req.params.projectId, req.params.studentId]);
    if (result.rows.length === 0)
        return res.status(404).json({ error: 'No result found for this student' });
    res.json(result.rows[0]);
});

// ════════════════════════════════════════════════════════════
// JURY_ASSIGNMENTS
// ════════════════════════════════════════════════════════════
app.post('/api/assignments', async (req, res) => {
    const { jury_id, project_id } = req.body;
    const result = await pool.query(
        'INSERT INTO JURY_ASSIGNMENTS (jury_id, project_id) VALUES ($1,$2) RETURNING *',
        [jury_id, project_id]
    );
    res.status(201).json(result.rows[0]);
});

app.get('/api/assignments/jury/:juryId', async (req, res) => {
    const projectsResult = await pool.query(`
        SELECT p.project_id, p.project_name, p.description,
               p.advisor, p.exam_datetime, p.status,
               ja.is_completed, ja.completed_at
        FROM JURY_ASSIGNMENTS ja
        JOIN PROJECTS p ON ja.project_id = p.project_id
        WHERE ja.jury_id = $1 ORDER BY p.exam_datetime
    `, [req.params.juryId]);

    const projects = await Promise.all(projectsResult.rows.map(async (project) => {
        const membersResult = await pool.query(`
            SELECT u.user_id, u.name, u.cats_username
            FROM PROJECT_MEMBERS pm
            JOIN USERS u ON pm.student_id = u.user_id
            WHERE pm.project_id = $1
        `, [project.project_id]);
        return { ...project, members: membersResult.rows };
    }));

    res.json(projects);
});

app.get('/api/assignments/project/:projectId', async (req, res) => {
    const result = await pool.query(`
        SELECT ja.assignment_id, u.user_id, u.name AS jury_name,
               u.email, ja.assigned_at, ja.is_completed, ja.completed_at
        FROM JURY_ASSIGNMENTS ja
        JOIN USERS u ON ja.jury_id = u.user_id
        WHERE ja.project_id = $1 ORDER BY ja.assigned_at
    `, [req.params.projectId]);
    res.json(result.rows);
});

app.get('/api/assignments', async (req, res) => {
    const result = await pool.query(`
        SELECT ja.assignment_id, u.name AS jury_name,
               p.project_name, ja.assigned_at, ja.is_completed
        FROM JURY_ASSIGNMENTS ja
        JOIN USERS    u ON ja.jury_id    = u.user_id
        JOIN PROJECTS p ON ja.project_id = p.project_id
        ORDER BY ja.assignment_id
    `);
    res.json(result.rows);
});

app.delete('/api/assignments/:assignmentId', async (req, res) => {
    const result = await pool.query(
        'DELETE FROM JURY_ASSIGNMENTS WHERE assignment_id = $1 RETURNING *',
        [req.params.assignmentId]
    );
    if (result.rows.length === 0)
        return res.status(404).json({ error: 'Assignment not found' });
    res.json({ message: 'Assignment deleted', deleted: result.rows[0] });
});

// ════════════════════════════════════════════════════════════
// STUDENT ENDPOINTS
// ════════════════════════════════════════════════════════════
app.get('/api/student/:studentId/project', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT p.project_id, p.project_name, p.description,
                   p.advisor, p.exam_datetime, p.status
            FROM PROJECTS p
            JOIN PROJECT_MEMBERS pm ON p.project_id = pm.project_id
            WHERE pm.student_id = $1 LIMIT 1
        `, [req.params.studentId]);
        if (result.rows.length === 0) return res.status(404).json({ error: 'No project found' });

        const membersRes = await pool.query(`
            SELECT u.user_id, u.name, u.cats_username, u.email
            FROM PROJECT_MEMBERS pm
            JOIN USERS u ON pm.student_id = u.user_id
            WHERE pm.project_id = $1
        `, [result.rows[0].project_id]);

        res.json({ ...result.rows[0], members: membersRes.rows });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/student/:studentId/project', async (req, res) => {
    try {
        const { project_name, description } = req.body;
        const projectRes = await pool.query(
            'SELECT project_id FROM PROJECT_MEMBERS WHERE student_id = $1 LIMIT 1',
            [req.params.studentId]
        );
        if (projectRes.rows.length === 0) return res.status(404).json({ error: 'No project found' });
        const result = await pool.query(
            `UPDATE PROJECTS SET project_name = $1, description = $2
             WHERE project_id = $3 RETURNING project_id, project_name, description`,
            [project_name, description, projectRes.rows[0].project_id]
        );
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/student/:studentId/result', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT fr.total_weighted_score, fr.generated_at, p.project_name
            FROM FINAL_RESULTS fr
            JOIN PROJECTS p ON fr.project_id = p.project_id
            WHERE fr.student_id = $1
            ORDER BY fr.generated_at DESC LIMIT 1
        `, [req.params.studentId]);
        if (result.rows.length === 0) return res.json({ score: null });
        res.json({
            score:        result.rows[0].total_weighted_score,
            project_name: result.rows[0].project_name,
            generated_at: result.rows[0].generated_at
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ════════════════════════════════════════════════════════════
// ADMIN ENDPOINTS
// ════════════════════════════════════════════════════════════

// Statistics — v3 versiyonu (status breakdown dahil)
app.get('/api/admin/statistics', async (req, res) => {
    const { admin_user_id } = req.query;
    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) return res.status(403).json({ error: 'Admin privileges required.' });

    try {
        const stats = await pool.query(`
            SELECT
                (SELECT COUNT(*)::int FROM PROJECTS)                                    AS total_projects,
                (SELECT COUNT(*)::int FROM PROJECTS WHERE status = 'Pending')           AS pending_projects,
                (SELECT COUNT(*)::int FROM PROJECTS WHERE status = 'In Progress')       AS in_progress_projects,
                (SELECT COUNT(*)::int FROM PROJECTS WHERE status = 'Completed')         AS completed_projects,
                (SELECT COUNT(*)::int FROM PROJECTS WHERE status = 'Finalized')         AS finalized_projects,
                (SELECT COUNT(*)::int FROM USERS WHERE role = 'Jury')                   AS total_jury,
                (SELECT COUNT(*)::int FROM USERS WHERE role = 'Student')                AS total_students,
                (SELECT COUNT(*)::int FROM JURY_ASSIGNMENTS)                            AS total_assignments,
                (SELECT COUNT(*)::int FROM JURY_ASSIGNMENTS WHERE is_completed = TRUE)  AS completed_assignments,
                (SELECT COUNT(*)::int FROM EVALUATIONS)                                 AS total_evaluations,
                (SELECT COUNT(*)::int FROM FINAL_RESULTS)                               AS total_final_results,
                (SELECT COUNT(*)::int FROM AUDIT_LOG)                                   AS total_audit_records,
                (SELECT COUNT(*)::int FROM AUDIT_LOG WHERE action_type = 'ADMIN_OVERRIDE') AS total_admin_overrides
        `);
        res.json(stats.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// Audit Log
app.get('/api/admin/audit-log', async (req, res) => {
    const { admin_user_id, actor_user_id, project_id, action_type, date_from, date_to, limit } = req.query;

    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) return res.status(403).json({ error: 'Admin privileges required.' });

    const validActions = ['CREATE','UPDATE','ADMIN_OVERRIDE','UNLOCK_REQUESTED','UNLOCK_APPROVED','UNLOCK_DENIED','RESUBMIT'];
    if (action_type && !validActions.includes(action_type))
        return res.status(400).json({ error: 'Invalid action_type.' });

    const conditions = [];
    const params     = [];
    let i = 1;

    if (actor_user_id) { conditions.push(`a.actor_user_id = $${i++}`); params.push(actor_user_id); }
    if (project_id)    { conditions.push(`a.project_id = $${i++}`);    params.push(project_id); }
    if (action_type)   { conditions.push(`a.action_type = $${i++}`);   params.push(action_type); }
    if (date_from)     { conditions.push(`a.timestamp >= $${i++}`);    params.push(date_from); }
    if (date_to)       { conditions.push(`a.timestamp <= $${i++}`);    params.push(date_to); }

    const whereClause = conditions.length > 0 ? 'WHERE ' + conditions.join(' AND ') : '';
    let limitNum = Math.min(Math.max(parseInt(limit) || 100, 1), 500);

    try {
        const result = await pool.query(`
            SELECT a.audit_id, a.action_type, a.old_score, a.new_score, a.comment, a.timestamp,
                   a.evaluation_id, a.project_id, a.student_id, a.criteria_id,
                   actor.user_id   AS actor_user_id,
                   actor.name      AS actor_name,
                   actor.role      AS actor_role,
                   student.name    AS student_name,
                   p.project_name  AS project_name,
                   c.criteria_name AS criteria_name
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

// Projects overview (admin)
app.get('/api/admin/projects-overview', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT p.project_id, p.project_name, p.status, p.advisor, p.exam_datetime,
                (SELECT COUNT(*) FROM PROJECT_MEMBERS pm WHERE pm.project_id = p.project_id) AS total_students,
                (SELECT COUNT(*) FROM JURY_ASSIGNMENTS ja WHERE ja.project_id = p.project_id) AS total_juries,
                (SELECT COUNT(*) FROM JURY_ASSIGNMENTS ja WHERE ja.project_id = p.project_id AND ja.is_completed = TRUE) AS completed_juries,
                (SELECT COUNT(*) FROM EVALUATIONS e WHERE e.project_id = p.project_id) AS submitted_evaluations,
                (SELECT COUNT(*) FROM CRITERIA)
                    * (SELECT COUNT(*) FROM PROJECT_MEMBERS pm WHERE pm.project_id = p.project_id)
                    * (SELECT COUNT(*) FROM JURY_ASSIGNMENTS ja WHERE ja.project_id = p.project_id) AS expected_evaluations
            FROM PROJECTS p ORDER BY p.project_id
        `);

        const projects = await Promise.all(result.rows.map(async (project) => {
            const membersRes = await pool.query(`
                SELECT u.user_id, u.name, u.cats_username
                FROM PROJECT_MEMBERS pm JOIN USERS u ON pm.student_id = u.user_id
                WHERE pm.project_id = $1
            `, [project.project_id]);
            return { ...project, members: membersRes.rows };
        }));

        res.json(projects);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ════════════════════════════════════════════════════════════
// UNLOCK REQUESTS
// ════════════════════════════════════════════════════════════
app.post('/api/unlock-requests', async (req, res) => {
    const { jury_id, project_id, student_id, reason } = req.body;

    if (!jury_id || !project_id || !student_id || !reason || reason.trim().length === 0)
        return res.status(400).json({ error: 'jury_id, project_id, student_id and reason are required.' });

    try {
        // Zaten PENDING request var mı?
        const pendingCheck = await pool.query(
            `SELECT request_id FROM UNLOCK_REQUESTS 
             WHERE jury_id = $1 AND project_id = $2 AND student_id = $3 AND status = 'PENDING'`,
            [jury_id, project_id, student_id]
        );
        if (pendingCheck.rows.length > 0)
            return res.status(409).json({ error: 'There is already a pending unlock request.' });

        // O kombinasyondaki evaluation'lar gerçekten submitted mi?
        const evalCheck = await pool.query(
            `SELECT COUNT(*) FROM EVALUATIONS 
             WHERE jury_id = $1 AND project_id = $2 AND student_id = $3 AND is_submitted = TRUE`,
            [jury_id, project_id, student_id]
        );
        if (parseInt(evalCheck.rows[0].count) === 0)
            return res.status(400).json({ error: 'No submitted evaluations found.' });

        const result = await pool.query(`
            INSERT INTO UNLOCK_REQUESTS (jury_id, project_id, student_id, reason)
            VALUES ($1, $2, $3, $4) RETURNING *
        `, [jury_id, project_id, student_id, reason.trim()]);

        // Audit log — her evaluation için ayrı kayıt
        const evals = await pool.query(
            `SELECT evaluation_id, criteria_id FROM EVALUATIONS 
             WHERE jury_id = $1 AND project_id = $2 AND student_id = $3`,
            [jury_id, project_id, student_id]
        );
        for (const e of evals.rows) {
            await logAudit({
                actorUserId:  jury_id,
                actionType:   'UNLOCK_REQUESTED',
                evaluationId: e.evaluation_id,
                projectId:    project_id,
                studentId:    student_id,
                criteriaId:   e.criteria_id,
                oldScore:     null, newScore: null,
                comment:      reason.trim(),
            });
        }

        res.status(201).json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/unlock-requests/jury/:juryId', async (req, res) => {
    try {
        const result = await pool.query(`
            SELECT ur.*, p.project_name, s.name AS student_name
            FROM UNLOCK_REQUESTS ur
            JOIN PROJECTS p ON ur.project_id = p.project_id
            JOIN USERS    s ON ur.student_id  = s.user_id
            WHERE ur.jury_id = $1
            ORDER BY ur.created_at DESC
        `, [req.params.juryId]);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.get('/api/admin/unlock-requests', async (req, res) => {
    const { admin_user_id, status } = req.query;

    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) return res.status(403).json({ error: 'Admin privileges required.' });

    const statusFilter = status || 'PENDING';
    if (!['PENDING','APPROVED','DENIED','ALL'].includes(statusFilter))
        return res.status(400).json({ error: 'Invalid status filter.' });

    const whereClause = statusFilter === 'ALL' ? '' : `WHERE ur.status = '${statusFilter}'`;

    try {
        const result = await pool.query(`
            SELECT ur.request_id, ur.jury_id, ur.project_id, ur.student_id,
                   ur.reason, ur.status, ur.admin_comment,
                   ur.created_at, ur.reviewed_at,
                   jury.name         AS jury_name,
                   reviewer.name     AS reviewer_name,
                   p.project_name,
                   student.name      AS student_name
            FROM UNLOCK_REQUESTS ur
            JOIN USERS       jury     ON ur.jury_id    = jury.user_id
            LEFT JOIN USERS  reviewer ON ur.reviewed_by = reviewer.user_id
            JOIN PROJECTS    p        ON ur.project_id  = p.project_id
            JOIN USERS       student  ON ur.student_id  = student.user_id
            ${whereClause}
            ORDER BY ur.created_at DESC
        `);
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

app.put('/api/admin/unlock-requests/:requestId', async (req, res) => {
    const { requestId } = req.params;
    const { decision, admin_comment, admin_user_id } = req.body;

    const isAdmin = await verifyAdmin(admin_user_id);
    if (!isAdmin) return res.status(403).json({ error: 'Admin privileges required.' });

    if (!['APPROVE','DENY'].includes(decision))
        return res.status(400).json({ error: "decision must be 'APPROVE' or 'DENY'." });

    try {
        const reqCheck = await pool.query(
            'SELECT * FROM UNLOCK_REQUESTS WHERE request_id = $1', [requestId]
        );
        if (reqCheck.rows.length === 0)
            return res.status(404).json({ error: 'Unlock request not found.' });

        const request = reqCheck.rows[0];
        if (request.status !== 'PENDING')
            return res.status(400).json({ error: `This request is already ${request.status.toLowerCase()}.` });

        const newStatus = decision === 'APPROVE' ? 'APPROVED' : 'DENIED';

        const updated = await pool.query(`
            UPDATE UNLOCK_REQUESTS
            SET status = $1, reviewed_by = $2, reviewed_at = NOW(), admin_comment = $3
            WHERE request_id = $4 RETURNING *
        `, [newStatus, admin_user_id, admin_comment ?? null, requestId]);

        if (decision === 'APPROVE') {
            // Tüm kombinasyonu unlock et
            await pool.query(
                `UPDATE EVALUATIONS SET is_submitted = FALSE 
                 WHERE jury_id = $1 AND project_id = $2 AND student_id = $3`,
                [request.jury_id, request.project_id, request.student_id]
            );
        }

        // Audit log
        const evals = await pool.query(
            `SELECT evaluation_id, criteria_id FROM EVALUATIONS 
             WHERE jury_id = $1 AND project_id = $2 AND student_id = $3`,
            [request.jury_id, request.project_id, request.student_id]
        );
        for (const e of evals.rows) {
            await logAudit({
                actorUserId:  admin_user_id,
                actionType:   decision === 'APPROVE' ? 'UNLOCK_APPROVED' : 'UNLOCK_DENIED',
                evaluationId: e.evaluation_id,
                projectId:    request.project_id,
                studentId:    request.student_id,
                criteriaId:   e.criteria_id,
                oldScore:     null, newScore: null,
                comment:      admin_comment ?? null,
            });
        }

        res.json(updated.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── Sunucuyu Başlat ───────────────────────────────────────
app.listen(PORT, () => {
    console.log(`Server running on http://localhost:${PORT}`);
});

// Admin Panel Eklemeleri

// Advisor'ın projelerini getir (sidebar için)


//Proje adı/desc güncelle (advisor tarafından)

app.put('/api/projects/:id', async (req, res) => {
    try {
        const { project_name, description } = req.body;
        const result = await pool.query(`
            UPDATE PROJECTS 
            SET project_name = $1, description = $2
            WHERE project_id = $3
            RETURNING *
        `, [project_name, description, req.params.id]);
        if (result.rows.length === 0)
            return res.status(404).json({ error: 'Project not found' });
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});
 // Projeye Advisor Atama
 app.put('/api/projects/:id/advisor', async (req, res) => {
    try {
        const { advisor_id } = req.body;
        // Kullanıcının adını da advisor string olarak kaydet
        const userRes = await pool.query(
            'SELECT name FROM USERS WHERE user_id = $1', [advisor_id]
        );
        if (userRes.rows.length === 0)
            return res.status(404).json({ error: 'User not found' });

        const result = await pool.query(`
            UPDATE PROJECTS 
            SET advisor_id = $1, advisor = $2
            WHERE project_id = $3
            RETURNING *
        `, [advisor_id, userRes.rows[0].name, req.params.id]);

        if (result.rows.length === 0)
            return res.status(404).json({ error: 'Project not found' });
        res.json(result.rows[0]);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});


// Kullanıcıları Rollere göre getirme (Admin Paneli Dropdown)
app.get('/api/users/role/:role', async (req, res) => {
    try {
        const result = await pool.query(
            `SELECT user_id, cats_username, name, email, role 
             FROM USERS WHERE role = $1 ORDER BY name`,
            [req.params.role]
        );
        res.json(result.rows);
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});