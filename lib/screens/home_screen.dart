import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:capstone_evaluationapp/models/project.dart';
import 'package:capstone_evaluationapp/screens/evaluation_screen.dart';
import 'package:capstone_evaluationapp/screens/results_dashboard.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);
  static const Color bgColor = Color(0xFFF5F5F7);

  // Yeni palette: 3 status için
  static const Color statusNotStarted = Color(0xFF9E9E9E); // gri
  static const Color statusInProgress = Color(0xFFFF6B35); // turuncu
  static const Color statusSubmitted = Color(0xFF2ECC71);  // yeşil

  String? _expandedProjectId;
  List<CapstoneProject> _projects = [];
  List<String> _criteriaNames = [];
  bool _isLoading = true;
  String? _errorMessage;

  Map<String, dynamic>? _user;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map<String, dynamic>) {
      _user = args;
    }
    _loadProjects();
  }

Future<void> _loadProjects() async {
  if (_user == null) return;
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });
  try {
    final juryId = _user!['user_id'];

    // Kriterleri çek
    final criteriaRes = await http.get(
      Uri.parse('http://localhost:3000/api/criteria'),
    );
    if (criteriaRes.statusCode == 200) {
      final List cData = jsonDecode(criteriaRes.body);
      _criteriaNames = cData.map((c) => c['criteria_name'] as String).toList();
    }

    // Atanmış projeleri çek
    final response = await http.get(
      Uri.parse('http://localhost:3000/api/assignments/jury/$juryId'),
    );
    if (response.statusCode != 200) {
      setState(() {
        _errorMessage = 'Failed to load projects.';
        _isLoading = false;
      });
      return;
    }

    final List data = jsonDecode(response.body);
    final projects = data.map((p) => CapstoneProject.fromJson(p)).toList();

    // Her proje için backend'den evaluation durumlarını çek
    final enriched = <CapstoneProject>[];
    for (final project in projects) {
      final evalRes = await http.get(
        Uri.parse('http://localhost:3000/api/evaluations/jury/$juryId/project/${project.id}'),
      );

      final Map<String, MemberEvaluation> memberEvals = {
        for (final m in project.members)
          m.studentId: MemberEvaluation.empty(_criteriaNames),
      };

      if (evalRes.statusCode == 200) {
        final List backendRows = jsonDecode(evalRes.body);

        // Backend satırlarını student'a göre grupla
        final Map<String, List<dynamic>> byStudent = {};
        for (final row in backendRows) {
          final studentUserId = row['student_id'].toString();
          final member = project.members.firstWhere(
            (m) => m.userId.toString() == studentUserId,
            orElse: () => ProjectMember(userId: -1, name: '', studentId: ''),
          );
          if (member.userId == -1) continue;
          byStudent.putIfAbsent(member.studentId, () => []);
          byStudent[member.studentId]!.add(row);
        }

        // Her üye için durumu belirle
        for (final member in project.members) {
          final rows = byStudent[member.studentId];
          if (rows == null || rows.isEmpty) continue;

          final scores = <String, double?>{};
          final ids = <int>[];
          for (final r in rows) {
            scores[r['criteria_name'] as String] = (r['score'] as num).toDouble();
            ids.add(r['evaluation_id'] as int);
          }

          final allSubmitted = rows.every((r) => r['is_submitted'] == true);
          final anyUnlocked  = rows.any((r) => r['is_submitted'] == false);

          if (anyUnlocked) {
            memberEvals[member.studentId] = MemberEvaluation(
              scores: scores,
              status: MemberEvaluationStatus.inProgress,
              evaluationIds: ids,
            );
          } else if (allSubmitted) {
            memberEvals[member.studentId] = MemberEvaluation(
              scores: scores,
              status: MemberEvaluationStatus.submitted,
              submittedAt: DateTime.now(),
              evaluationIds: ids,
            );
          }
        }
      }

      enriched.add(project.copyWith(memberEvaluations: memberEvals));
    }

    setState(() {
      _projects = enriched;
      _isLoading = false;
    });
  } catch (e) {
    setState(() {
      _errorMessage = 'Could not connect to server.';
      _isLoading = false;
    });
  }
}

  Future<void> _openEvaluation(CapstoneProject project) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EvaluationScreen(
          project: project,
          juryId: _user!['user_id'],
        ),
      ),
    );
    // Geri dönünce projeleri yeniden yükle (draft/submit güncellensin)
    _loadProjects();
  }

  Future<void> _openCompletedProject(CapstoneProject project) async {
    // Submit edilmiş proje için dashboard göster.
    // Puanlar memberEvaluations'dan okunur (SharedPreferences'tan gelir).
    final Map<String, Map<String, double?>> confirmedScores = {
      for (final m in project.members)
        m.studentId: project.memberEvaluations[m.studentId]?.scores ??
            {for (final c in _criteriaNames) c: null},
    };

    // Kriter ağırlıklarını backend'den çek
    try {
      final criteriaRes = await http.get(
        Uri.parse('http://localhost:3000/api/criteria'),
      );
      if (criteriaRes.statusCode != 200) return;

      final List cData = jsonDecode(criteriaRes.body);
      final Map<String, double> criteriaWeights = {
        for (final c in cData)
          c['criteria_name'] as String: (c['weight'] as num).toDouble()
      };
      final criteria = cData.map((c) => c['criteria_name'] as String).toList();

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _DashboardPage(
            project: project,
            confirmedScores: confirmedScores,
            criteria: criteria,
            criteriaWeights: criteriaWeights,
            user: _user!,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      drawer: _buildSidebar(context),
      appBar: _buildAppBar(context),
      body: _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final initials = _user != null
        ? _user!['name'].toString().split(' ').map((e) => e[0]).take(2).join()
        : 'JU';
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      shadowColor: Colors.black12,
      surfaceTintColor: Colors.white,
      leading: Builder(
        builder: (ctx) => GestureDetector(
          onTap: () => Scaffold.of(ctx).openDrawer(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: CircleAvatar(
              backgroundColor: ikuRed,
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      ),
      title: const Text(
        'My Evaluations',
        style: TextStyle(
          color: ikuGrey,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(Icons.notifications_outlined, color: ikuGrey),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ikuRed));
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: ikuRed)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProjects,
              style: ElevatedButton.styleFrom(backgroundColor: ikuRed),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildProgressBanner(),
        const SizedBox(height: 16),
        const Text(
          'ASSIGNED PROJECTS',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ikuGrey,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ..._projects.map((project) => _buildProjectCard(project)),
      ],
    );
  }

  Widget _buildProgressBanner() {
    final total = _projects.length;
    final submitted = _projects.where((p) => p.isFullySubmitted).length;
    final inProgress = _projects
        .where((p) => p.overallStatus == ProjectOverallStatus.inProgress)
        .length;
    final notStarted = total - submitted - inProgress;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERVIEW',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade400,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _miniStat(submitted, 'Submitted', statusSubmitted),
              const SizedBox(width: 10),
              _miniStat(inProgress, 'In Progress', statusInProgress),
              const SizedBox(width: 10),
              _miniStat(notStarted, 'Not Started', statusNotStarted),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : submitted / total,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(statusSubmitted),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$submitted of $total projects fully submitted',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(int count, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(CapstoneProject project) {
    final isExpanded = _expandedProjectId == project.id;
    final status = project.overallStatus;
    final statusColor = _colorForStatus(status);

    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedProjectId = isExpanded ? null : project.id;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded ? ikuRed.withOpacity(0.4) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          project.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: ikuGrey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.schedule,
                                size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(project.examDateTime),
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _statusBadge(status),
                      const SizedBox(height: 4),
                      Text(
                        '${project.submittedCount}/${project.members.length} submitted',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: ikuGrey,
                    size: 20,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: project.members.isEmpty
                      ? 0
                      : project.submittedCount / project.members.length,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (isExpanded) _buildExpandedContent(project),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(CapstoneProject project) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(14),
          bottomRight: Radius.circular(14),
        ),
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.description,
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade700, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.school_outlined,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                'Advisor: ',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                project.advisor,
                style: const TextStyle(
                  fontSize: 12,
                  color: ikuGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'PROJECT MEMBERS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade400,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...project.members.map((m) => _buildMemberRow(project, m)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                if (project.isFullySubmitted) {
                  _openCompletedProject(project);
                } else {
                  _openEvaluation(project);
                }
              },
              icon: Icon(
                project.isFullySubmitted ? Icons.visibility : Icons.edit_note,
                size: 18,
              ),
              label: Text(
                project.isFullySubmitted
                    ? 'View Evaluation'
                    : project.overallStatus == ProjectOverallStatus.inProgress
                        ? 'Continue Evaluating'
                        : 'Evaluate Members',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    project.isFullySubmitted ? Colors.grey.shade600 : ikuRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Her üye için mini durum satırı (yeşil ✓ / turuncu draft / gri boş)
  Widget _buildMemberRow(CapstoneProject project, ProjectMember m) {
    final eval = project.memberEvaluations[m.studentId];
    final status = eval?.status ?? MemberEvaluationStatus.notStarted;
    final color = _colorForMemberStatus(status);
    final label = _labelForMemberStatus(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: ikuRed.withOpacity(0.1),
            child: Text(
              m.name.substring(0, 1),
              style: const TextStyle(
                color: ikuRed,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ikuGrey,
                  ),
                ),
                Text(m.studentId,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (status == MemberEvaluationStatus.submitted)
                  Icon(Icons.lock, size: 10, color: color),
                if (status == MemberEvaluationStatus.submitted)
                  const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(ProjectOverallStatus status) {
    final color = _colorForStatus(status);
    final label = _labelForStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color _colorForStatus(ProjectOverallStatus s) {
    switch (s) {
      case ProjectOverallStatus.allSubmitted:
        return statusSubmitted;
      case ProjectOverallStatus.inProgress:
        return statusInProgress;
      case ProjectOverallStatus.notStarted:
        return statusNotStarted;
    }
  }

  String _labelForStatus(ProjectOverallStatus s) {
    switch (s) {
      case ProjectOverallStatus.allSubmitted:
        return 'Submitted';
      case ProjectOverallStatus.inProgress:
        return 'In Progress';
      case ProjectOverallStatus.notStarted:
        return 'Not Started';
    }
  }

  Color _colorForMemberStatus(MemberEvaluationStatus s) {
    switch (s) {
      case MemberEvaluationStatus.submitted:
        return statusSubmitted;
      case MemberEvaluationStatus.inProgress:
        return statusInProgress;
      case MemberEvaluationStatus.notStarted:
        return statusNotStarted;
    }
  }

  String _labelForMemberStatus(MemberEvaluationStatus s) {
    switch (s) {
      case MemberEvaluationStatus.submitted:
        return 'Submitted';
      case MemberEvaluationStatus.inProgress:
        return 'Draft';
      case MemberEvaluationStatus.notStarted:
        return 'Pending';
    }
  }

  Widget _buildSidebar(BuildContext context) {
    final name = _user?['name'] ?? 'Jury Member';
    final initials = name.toString().split(' ').map((e) => e[0]).take(2).join();
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: ikuRed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Computer Engineering',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'PAST EVALUATIONS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade400,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: Text(
                  'No past evaluations',
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                ),
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            ListTile(
              leading: const Icon(Icons.logout, color: ikuRed, size: 20),
              title: const Text(
                'Log Out',
                style: TextStyle(
                  color: ikuRed,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushReplacementNamed('/login');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year}  •  $hour:$minute';
  }
}

class _DashboardPage extends StatelessWidget {
  final CapstoneProject project;
  final Map<String, Map<String, double?>> confirmedScores;
  final List<String> criteria;
  final Map<String, double> criteriaWeights;
  final Map<String, dynamic> user;

  const _DashboardPage({
    required this.project,
    required this.confirmedScores,
    required this.criteria,
    required this.criteriaWeights,
    required this.user,
  });

  
  static const Color ikuGrey = Color(0xFF4A4A49);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: ikuGrey),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          project.title,
          style: const TextStyle(
            color: ikuGrey,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ResultsDashboard(
          project: project,
          confirmedScores: confirmedScores,
          criteria: criteria,
          criteriaWeights: criteriaWeights,
        ),
      ),
    );
  }
}