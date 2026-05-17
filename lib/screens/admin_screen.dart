import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:url_launcher/url_launcher.dart';
import 'package:capstone_evaluationapp/config.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);
  static const Color bgColor = Color(0xFFF5F5F7);
  static final String _apiBase = AppConfig.baseUrl;

  Map<String, dynamic>? _user;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map<String, dynamic>) {
      _user = args;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_user == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: ikuRed)),
      );
    }
    final adminId = _user!['user_id'] as int;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ProjectsTab(adminId: adminId, apiBase: _apiBase),
          _StatisticsTab(adminId: adminId, apiBase: _apiBase),
          _AuditLogTab(adminId: adminId, apiBase: _apiBase),
          _UnlockRequestsTab(adminId: adminId, apiBase: _apiBase),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final name = _user?['name'] ?? 'Admin';
    final initials = name.toString().split(' ').map((e) => e[0]).take(2).join();

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      automaticallyImplyLeading: false,
      titleSpacing: 16,
      toolbarHeight: 64,
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: ikuRed,
            radius: 18,
            child: Text(initials,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name,
                    style: const TextStyle(color: ikuGrey, fontWeight: FontWeight.w700, fontSize: 15),
                    overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: ikuRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('ADMIN',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: ikuRed, letterSpacing: 0.8)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
            icon: const Icon(Icons.logout, color: ikuRed, size: 18),
            label: const Text('Log Out', style: TextStyle(color: ikuRed, fontSize: 13)),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(49),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade200, width: 1)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: ikuRed,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: ikuRed,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(icon: Icon(Icons.folder_outlined, size: 18), text: 'Projects', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.insights_outlined, size: 18), text: 'Statistics', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.history, size: 18), text: 'Audit Log', iconMargin: EdgeInsets.only(bottom: 2)),
              Tab(icon: Icon(Icons.lock_open_outlined, size: 18), text: 'Unlock Requests', iconMargin: EdgeInsets.only(bottom: 2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// TAB 1: PROJECTS
// ════════════════════════════════════════════════════════════
class _ProjectsTab extends StatefulWidget {
  final int adminId;
  final String apiBase;
  const _ProjectsTab({required this.adminId, required this.apiBase});

  @override
  State<_ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends State<_ProjectsTab> with AutomaticKeepAliveClientMixin {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  List<dynamic> _projects = [];
  List<dynamic> _juryUsers = [];
  List<dynamic> _studentUsers = [];
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final results = await Future.wait([
        http.get(Uri.parse('${widget.apiBase}/api/projects')),
        http.get(Uri.parse('${widget.apiBase}/api/users/role/Jury')),
        http.get(Uri.parse('${widget.apiBase}/api/users/role/Student')),
      ]);
      setState(() {
        _projects     = jsonDecode(results[0].body);
        _juryUsers    = jsonDecode(results[1].body);
        _studentUsers = jsonDecode(results[2].body);
        _isLoading    = false;
      });
    } catch (_) {
      setState(() { _error = 'Could not connect to server.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: ikuRed));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: ikuRed)));

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProject,
        backgroundColor: ikuRed,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Project', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: ikuRed,
        onRefresh: _load,
        child: _projects.isEmpty
            ? const Center(child: Text('No projects yet.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                itemCount: _projects.length,
                itemBuilder: (_, i) => _projectCard(_projects[i]),
              ),
      ),
    );
  }

  Future<void> _createProject() async {
    try {
      final res = await http.post(
        Uri.parse('${widget.apiBase}/api/projects'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'project_name': '', 'student_id': null}),
      );
      if (res.statusCode == 201) {
        await _load();
        final newProject = jsonDecode(res.body);
        if (!mounted) return;
        _openProjectDetail(newProject);
      }
    } catch (_) {}
  }

  Widget _projectCard(dynamic project) {
    final status = project['status'] ?? 'Pending';
    final members = (project['members'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: ikuRed.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.folder_outlined, color: ikuRed, size: 20),
        ),
        title: Text(project['project_name'] ?? 'Unnamed Project',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ikuGrey)),
        subtitle: Text('${members.length} member${members.length != 1 ? 's' : ''}  •  $status',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: () => _openProjectDetail(project),
      ),
    );
  }

  void _openProjectDetail(dynamic project) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _ProjectDetailScreen(
        project: project,
        juryUsers: _juryUsers,
        studentUsers: _studentUsers,
        apiBase: widget.apiBase,
        onRefresh: _load,
        adminId: widget.adminId,
      ),
    ));
  }
}

// ────────────────────────────────────────────────────────────
// Project Detail Screen
// ────────────────────────────────────────────────────────────
class _ProjectDetailScreen extends StatefulWidget {
  final dynamic project;
  final List<dynamic> juryUsers;
  final List<dynamic> studentUsers;
  final String apiBase;
  final VoidCallback onRefresh;
  final int adminId;

  const _ProjectDetailScreen({
    required this.project,
    required this.juryUsers,
    required this.studentUsers,
    required this.apiBase,
    required this.onRefresh,
    required this.adminId,
  });

  @override
  State<_ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<_ProjectDetailScreen> {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  late dynamic _project;
  List<dynamic> _members = [];
  List<dynamic> _assignments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        http.get(Uri.parse('${widget.apiBase}/api/projects/${_project['project_id']}')),
        http.get(Uri.parse('${widget.apiBase}/api/projects/${_project['project_id']}/members')),
        http.get(Uri.parse('${widget.apiBase}/api/assignments/project/${_project['project_id']}')),
      ]);
      setState(() {
        _project     = jsonDecode(results[0].body);
        _members     = jsonDecode(results[1].body);
        _assignments = jsonDecode(results[2].body);
        _isLoading   = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

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
          onPressed: () {
            widget.onRefresh();
            Navigator.of(context).pop();
          },
        ),
        title: Text(_project['project_name'] ?? 'Project',
            style: const TextStyle(color: ikuGrey, fontWeight: FontWeight.w700, fontSize: 16),
            overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: ikuRed))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard(title: 'ADVISOR', icon: Icons.school_outlined, child: _advisorSection()),
                const SizedBox(height: 12),
                _sectionCard(title: 'JURY MEMBERS', icon: Icons.people_outline, child: _jurySection()),
                const SizedBox(height: 12),
                _sectionCard(title: 'STUDENTS', icon: Icons.person_outline, child: _studentsSection()),
                const SizedBox(height: 12),
                _sectionCard(title: 'RESULTS', icon: Icons.grade_outlined, child: _publishSection()),
              ],
            ),
    );
  }

  Widget _sectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: ikuRed),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _advisorSection() {
    final advisorId   = _project['advisor_id'];
    final advisorName = _project['advisor'];

    return Row(
      children: [
        Expanded(
          child: advisorId != null
              ? Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: ikuRed.withOpacity(0.1),
                      child: Text((advisorName ?? '?').toString().substring(0, 1),
                          style: const TextStyle(color: ikuRed, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 10),
                    Text(advisorName ?? 'Unknown',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ikuGrey)),
                  ],
                )
              : Text('No advisor assigned', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ),
        TextButton.icon(
          onPressed: _assignAdvisor,
          icon: Icon(advisorId != null ? Icons.swap_horiz : Icons.add, size: 16, color: ikuRed),
          label: Text(advisorId != null ? 'Change' : 'Assign',
              style: const TextStyle(color: ikuRed, fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _assignAdvisor() async {
    final selected = await _showUserPickerDialog(
      title: 'Select Advisor', users: widget.juryUsers, allowCreate: true, createRole: 'Jury',
    );
    if (selected == null) return;

    try {
      final res = await http.put(
        Uri.parse('${widget.apiBase}/api/projects/${_project['project_id']}/advisor'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'advisor_id': selected['user_id']}),
      );

      if (res.statusCode == 200) {
        final projectRes = await http.get(
          Uri.parse('${widget.apiBase}/api/projects/${_project['project_id']}'),
        );
        if (projectRes.statusCode == 200) {
          setState(() => _project = jsonDecode(projectRes.body));
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Advisor assigned.'), backgroundColor: Color(0xFF27AE60)),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: ${res.body}'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _jurySection() {
    if (_assignments.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('No jury assigned', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          _addButton('Add Jury', _addJury),
        ],
      );
    }
    return Column(
      children: [
        ..._assignments.map((a) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: ikuRed.withOpacity(0.1),
                child: Text((a['jury_name'] ?? '?').toString().substring(0, 1),
                    style: const TextStyle(color: ikuRed, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(a['jury_name'] ?? 'Unknown',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ikuGrey))),
              GestureDetector(
                onTap: () => _removeJury(a['assignment_id']),
                child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey.shade400),
              ),
            ],
          ),
        )),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerRight, child: _addButton('Add Jury', _addJury)),
      ],
    );
  }

  Future<void> _addJury() async {
    final selected = await _showUserPickerDialog(
      title: 'Select Jury Member', users: widget.juryUsers, allowCreate: true, createRole: 'Jury',
    );
    if (selected == null) return;
    try {
      await http.post(
        Uri.parse('${widget.apiBase}/api/assignments'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'jury_id': selected['user_id'], 'project_id': _project['project_id']}),
      );
      _load();
    } catch (_) {}
  }

  Future<void> _removeJury(int assignmentId) async {
    try {
      await http.delete(Uri.parse('${widget.apiBase}/api/assignments/$assignmentId'));
      _load();
    } catch (_) {}
  }

  Widget _studentsSection() {
    if (_members.isEmpty) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('No students added', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          _addButton('Add Student', _addStudent),
        ],
      );
    }
    return Column(
      children: [
        ..._members.map((m) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: ikuRed.withOpacity(0.1),
                child: Text((m['name'] ?? '?').toString().substring(0, 1),
                    style: const TextStyle(color: ikuRed, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m['name'] ?? 'Unknown',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ikuGrey)),
                    Text(m['cats_username'] ?? '',
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _removeStudent(m['user_id']),
                child: Icon(Icons.remove_circle_outline, size: 18, color: Colors.grey.shade400),
              ),
            ],
          ),
        )),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerRight, child: _addButton('Add Student', _addStudent)),
      ],
    );
  }

  Future<void> _addStudent() async {
    final selected = await _showUserPickerDialog(
      title: 'Select Student', users: widget.studentUsers, allowCreate: true, createRole: 'Student',
    );
    if (selected == null) return;
    try {
      await http.post(
        Uri.parse('${widget.apiBase}/api/projects/${_project['project_id']}/members'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'student_id': selected['user_id']}),
      );
      _load();
    } catch (_) {}
  }

  Future<void> _removeStudent(int userId) async {
    try {
      await http.delete(Uri.parse('${widget.apiBase}/api/projects/${_project['project_id']}/members/$userId'));
      _load();
    } catch (_) {}
  }

  Widget _addButton(String label, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.add, size: 16, color: ikuRed),
      label: Text(label, style: const TextStyle(color: ikuRed, fontSize: 12)),
    );
  }

  Future<Map<String, dynamic>?> _showUserPickerDialog({
    required String title,
    required List<dynamic> users,
    required bool allowCreate,
    required String createRole,
  }) async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _UserPickerDialog(
        title: title, users: users, allowCreate: allowCreate,
        createRole: createRole, apiBase: widget.apiBase,
      ),
    );
  }

  Widget _publishSection() {
      final status = _project['status'] ?? 'Pending';
      final isFinalized = status == 'Finalized';
      final isPublished = _project['results_published'] == true;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Durum göstergesi ──
          if (isPublished)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF27AE60).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF27AE60).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF27AE60), size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Results published — students can see their scores.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF27AE60), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            )
          else if (!isFinalized)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, size: 14, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Project must be Finalized before publishing results.\nCurrent status: $status',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),

          // ── İki bağımsız buton yan yana ──
          Row(
            children: [
              // 1) Publish Results
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (!isFinalized || isPublished) ? null : _publishResults,
                  icon: Icon(
                    isPublished ? Icons.check_circle : Icons.send_outlined,
                    size: 16,
                  ),
                  label: Text(isPublished ? 'Published' : 'Publish Results'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPublished ? const Color(0xFF27AE60) : ikuRed,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isPublished
                        ? const Color(0xFF27AE60).withOpacity(0.7)
                        : Colors.grey.shade300,
                    disabledForegroundColor: isPublished
                        ? Colors.white
                        : Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 2) Export PDF (her zaman aktif)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                  label: const Text('Export PDF'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ikuRed,
                    side: BorderSide(color: ikuRed.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

  Future<void> _publishResults() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Publish Results',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ikuGrey)),
          content: const Text(
            'Students will be able to see their final scores. This action cannot be undone.',
            style: TextStyle(fontSize: 13, color: ikuGrey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: ikuGrey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: ikuRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Publish'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      try {
        // 1) Önce final skorları hesaplat
        await http.post(
          Uri.parse('${widget.apiBase}/api/results/${_project['project_id']}'),
        );

        // 2) Sonra publish et
        final res = await http.put(
          Uri.parse('${widget.apiBase}/api/projects/${_project['project_id']}/publish-results'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'admin_user_id': widget.adminId}),
        );
        if (res.statusCode == 200) {
          await _load();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Results published. Students can now see their scores.'),
              backgroundColor: Color(0xFF27AE60),
            ),
          );
        }
      } catch (_) {}
    }

  // _exportPdf metodu _ProjectDetailScreenState içinde — widget ve _project'e erişebilir
  Future<void> _exportPdf() async {
    final url = Uri.parse(
      '${widget.apiBase}/api/reports/export/${_project['project_id']}',
    );
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open PDF: $e'), backgroundColor: Colors.red),
      );
    }
  }
}

// ────────────────────────────────────────────────────────────
// User Picker Dialog
// ────────────────────────────────────────────────────────────
class _UserPickerDialog extends StatefulWidget {
  final String title;
  final List<dynamic> users;
  final bool allowCreate;
  final String createRole;
  final String apiBase;

  const _UserPickerDialog({
    required this.title, required this.users, required this.allowCreate,
    required this.createRole, required this.apiBase,
  });

  @override
  State<_UserPickerDialog> createState() => _UserPickerDialogState();
}

class _UserPickerDialogState extends State<_UserPickerDialog> {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  bool _creating = false;
  bool _saving   = false;

  final _nameController     = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController    = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      title: Text(widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ikuGrey)),
      content: SizedBox(width: double.maxFinite, child: _creating ? _createForm() : _selectList()),
      actions: _creating ? _createActions() : _selectActions(),
    );
  }

  Widget _selectList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.users.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No users found.', style: TextStyle(color: Colors.grey.shade500)),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: widget.users.length,
              itemBuilder: (_, i) {
                final u = widget.users[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: ikuRed.withOpacity(0.1),
                    child: Text((u['name'] ?? '?').toString().substring(0, 1),
                        style: const TextStyle(color: ikuRed, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(u['name'] ?? '',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ikuGrey)),
                  subtitle: Text(u['cats_username'] ?? '',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  onTap: () => Navigator.of(context).pop(Map<String, dynamic>.from(u)),
                );
              },
            ),
          ),
      ],
    );
  }

  List<Widget> _selectActions() {
    return [
      if (widget.allowCreate)
        TextButton.icon(
          onPressed: () => setState(() => _creating = true),
          icon: const Icon(Icons.person_add_outlined, size: 16, color: ikuRed),
          label: const Text('Create New', style: TextStyle(color: ikuRed)),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel', style: TextStyle(color: ikuGrey)),
      ),
    ];
  }

  Widget _createForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Full Name', filled: true, fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _usernameController,
          decoration: InputDecoration(
            labelText: 'Student/Staff ID (cats_username)', filled: true, fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: 'Email', filled: true, fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  List<Widget> _createActions() {
    return [
      TextButton(
        onPressed: () => setState(() => _creating = false),
        child: const Text('Back', style: TextStyle(color: ikuGrey)),
      ),
      ElevatedButton(
        onPressed: _saving ? null : _saveNewUser,
        style: ElevatedButton.styleFrom(
          backgroundColor: ikuRed, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: _saving
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Text('Create & Select'),
      ),
    ];
  }

  Future<void> _saveNewUser() async {
    final name     = _nameController.text.trim();
    final username = _usernameController.text.trim();
    final email    = _emailController.text.trim();

    if (name.isEmpty || username.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All fields are required.'), backgroundColor: ikuRed),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('${widget.apiBase}/api/users'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'cats_username': username, 'name': name, 'email': email, 'role': widget.createRole}),
      );
      if (res.statusCode == 201) {
        final newUser = jsonDecode(res.body);
        if (!mounted) return;
        Navigator.of(context).pop(Map<String, dynamic>.from(newUser));
      } else {
        setState(() => _saving = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(jsonDecode(res.body)['error'] ?? 'Failed to create user.'),
            backgroundColor: ikuRed,
          ),
        );
      }
    } catch (_) {
      setState(() => _saving = false);
    }
  }
}

// ════════════════════════════════════════════════════════════
// TAB 2: STATISTICS
// ════════════════════════════════════════════════════════════
class _StatisticsTab extends StatefulWidget {
  final int adminId;
  final String apiBase;
  const _StatisticsTab({required this.adminId, required this.apiBase});

  @override
  State<_StatisticsTab> createState() => _StatisticsTabState();
}

class _StatisticsTabState extends State<_StatisticsTab> with AutomaticKeepAliveClientMixin {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await http.get(Uri.parse(
          '${widget.apiBase}/api/admin/statistics?admin_user_id=${widget.adminId}'));
      if (res.statusCode == 200) {
        setState(() { _stats = jsonDecode(res.body); _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load statistics.'; _isLoading = false; });
      }
    } catch (_) {
      setState(() { _error = 'Could not connect to server.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: ikuRed));
    if (_error != null) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(_error!, style: const TextStyle(color: ikuRed)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load,
              style: ElevatedButton.styleFrom(backgroundColor: ikuRed),
              child: const Text('Retry', style: TextStyle(color: Colors.white))),
        ],
      ));
    }

    final s = _stats!;
    return RefreshIndicator(
      color: ikuRed,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          _sectionTitle('SYSTEM OVERVIEW'),
          const SizedBox(height: 8),
          _compactRow([
            _MiniStat('Projects', s['total_projects'], Icons.folder_outlined, ikuRed),
            _MiniStat('Evaluations', s['total_evaluations'], Icons.assignment_outlined, const Color(0xFF2E86DE)),
            _MiniStat('Final', s['total_final_results'], Icons.grade_outlined, const Color(0xFF27AE60)),
          ]),
          const SizedBox(height: 8),
          _compactRow([
            _MiniStat('Jury', s['total_jury'], Icons.people_outline, ikuGrey),
            _MiniStat('Students', s['total_students'], Icons.school_outlined, ikuGrey),
            _MiniStat('Audit', s['total_audit_records'], Icons.history, const Color(0xFFFF6B35)),
          ]),
          const SizedBox(height: 16),
          _sectionTitle('INTEGRITY'),
          const SizedBox(height: 8),
          _overrideCard(s['total_admin_overrides']),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [ikuRed, Color(0xFFB30E14)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: ikuRed.withOpacity(0.22), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.shield_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Administrator Dashboard',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Full system oversight & integrity control',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.8));

  Widget _compactRow(List<_MiniStat> stats) {
    return Row(
      children: [
        for (int i = 0; i < stats.length; i++) ...[
          Expanded(child: _miniStatCard(stats[i])),
          if (i < stats.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _miniStatCard(_MiniStat s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: s.color.withOpacity(0.12), borderRadius: BorderRadius.circular(7)),
            child: Icon(s.icon, size: 14, color: s.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${s.value}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: s.color, height: 1.0)),
                const SizedBox(height: 1),
                Text(s.label,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overrideCard(dynamic overrideCount) {
    final hasOverrides = (overrideCount as int) > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasOverrides ? const Color(0xFFFFF8E1) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: hasOverrides ? const Color(0xFFFFB300) : const Color(0xFF27AE60), width: 1),
      ),
      child: Row(
        children: [
          Icon(hasOverrides ? Icons.warning_amber_rounded : Icons.verified_outlined,
              color: hasOverrides ? const Color(0xFFF57C00) : const Color(0xFF27AE60), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasOverrides ? '$overrideCount Legacy Override${overrideCount == 1 ? '' : 's'}' : 'No Admin Overrides',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                      color: hasOverrides ? const Color(0xFFE65100) : const Color(0xFF1B5E20)),
                ),
                const SizedBox(height: 2),
                Text(
                  hasOverrides ? 'Historical records from the old override flow.' : 'Evaluation integrity is intact.',
                  style: TextStyle(fontSize: 11, color: hasOverrides ? const Color(0xFF795548) : Colors.green.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat {
  final String label;
  final dynamic value;
  final IconData icon;
  final Color color;
  const _MiniStat(this.label, this.value, this.icon, this.color);
}

// ════════════════════════════════════════════════════════════
// TAB 3: AUDIT LOG
// ════════════════════════════════════════════════════════════
class _AuditLogTab extends StatefulWidget {
  final int adminId;
  final String apiBase;
  const _AuditLogTab({required this.adminId, required this.apiBase});

  @override
  State<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<_AuditLogTab> with AutomaticKeepAliveClientMixin {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  List<dynamic> _logs = [];
  bool _isLoading = true;
  String? _error;
  String _filterAction = 'ALL';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      var url = '${widget.apiBase}/api/admin/audit-log?admin_user_id=${widget.adminId}';
      if (_filterAction != 'ALL') url += '&action_type=$_filterAction';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() { _logs = jsonDecode(res.body); _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load audit log.'; _isLoading = false; });
      }
    } catch (_) {
      setState(() { _error = 'Could not connect to server.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: ikuRed))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: ikuRed)))
                  : _logs.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          color: ikuRed,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _logs.length,
                            itemBuilder: (_, i) => _logCard(_logs[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('ALL', 'All'), const SizedBox(width: 6),
                  _filterChip('CREATE', 'Create'), const SizedBox(width: 6),
                  _filterChip('UPDATE', 'Update'), const SizedBox(width: 6),
                  _filterChip('UNLOCK_REQUESTED', 'Unlock Req'), const SizedBox(width: 6),
                  _filterChip('UNLOCK_APPROVED', 'Approved'), const SizedBox(width: 6),
                  _filterChip('UNLOCK_DENIED', 'Denied'), const SizedBox(width: 6),
                  _filterChip('RESUBMIT', 'Resubmit'), const SizedBox(width: 6),
                  _filterChip('ADMIN_OVERRIDE', 'Legacy'),
                ],
              ),
            ),
          ),
          IconButton(onPressed: _load, icon: Icon(Icons.refresh, size: 20, color: Colors.grey.shade700),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final isSelected = _filterAction == value;
    return GestureDetector(
      onTap: () { if (_filterAction != value) { setState(() => _filterAction = value); _load(); } },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? ikuRed : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : Colors.grey.shade700)),
      ),
    );
  }

  Widget _emptyState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.history_toggle_off, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 10),
      Text('No audit records found', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ],
  ));

  Widget _logCard(dynamic log) {
    final action      = log['action_type'] as String;
    final (color, icon) = _actionStyle(action);
    final actorName   = log['actor_name'] ?? 'Unknown';
    final actorRole   = log['actor_role'] ?? '';
    final studentName = log['student_name'] ?? 'Unknown';
    final projectName = log['project_name'] ?? 'Unknown';
    final criteriaName= log['criteria_name'] ?? 'Unknown';
    final oldScore    = log['old_score'];
    final newScore    = log['new_score'];
    final comment     = log['comment'];
    final ts          = DateTime.parse(log['timestamp']).toLocal();
    final isScoreAction = ['CREATE','UPDATE','ADMIN_OVERRIDE','RESUBMIT'].contains(action);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 11, color: color), const SizedBox(width: 4),
                  Text(_actionLabel(action),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
                ]),
              ),
              const Spacer(),
              Text(_formatTs(ts), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 14, backgroundColor: color.withOpacity(0.1),
                  child: Text(actorName.toString().substring(0, 1),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12))),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(actorName,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ikuGrey),
                        overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(3)),
                      child: Text(actorRole.toString().toUpperCase(),
                          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                    ),
                  ]),
                  const SizedBox(height: 3),
                  Text.rich(TextSpan(
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4),
                    children: [
                      TextSpan(text: _actionVerb(action)),
                      TextSpan(text: studentName, style: const TextStyle(fontWeight: FontWeight.w600, color: ikuGrey)),
                      const TextSpan(text: ' on '),
                      TextSpan(text: criteriaName, style: const TextStyle(fontWeight: FontWeight.w600, color: ikuGrey)),
                      const TextSpan(text: '\n'),
                      TextSpan(text: projectName,
                          style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey.shade500)),
                    ],
                  )),
                ]),
              ),
            ],
          ),
          if (isScoreAction) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (oldScore != null) ...[
                  Text('${oldScore.toString()}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                          color: Colors.grey.shade500, decoration: TextDecoration.lineThrough)),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 8),
                ],
                Text('${newScore?.toString() ?? '—'}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
              ]),
            ),
          ],
          if (!isScoreAction && comment != null && comment.toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)),
              child: Text(comment.toString(),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic)),
            ),
          ],
        ],
      ),
    );
  }

  (Color, IconData) _actionStyle(String action) {
    switch (action) {
      case 'CREATE':           return (const Color(0xFF27AE60), Icons.add_circle_outline);
      case 'UPDATE':           return (const Color(0xFFFF6B35), Icons.edit_outlined);
      case 'ADMIN_OVERRIDE':   return (const Color(0xFFD31018), Icons.shield_outlined);
      case 'UNLOCK_REQUESTED': return (const Color(0xFF2E86DE), Icons.mail_outline);
      case 'UNLOCK_APPROVED':  return (const Color(0xFF27AE60), Icons.check_circle_outline);
      case 'UNLOCK_DENIED':    return (const Color(0xFFD31018), Icons.cancel_outlined);
      case 'RESUBMIT':         return (const Color(0xFFFF6B35), Icons.refresh);
      default:                 return (Colors.grey, Icons.help_outline);
    }
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'UNLOCK_REQUESTED': return 'UNLOCK REQ';
      case 'UNLOCK_APPROVED':  return 'APPROVED';
      case 'UNLOCK_DENIED':    return 'DENIED';
      case 'ADMIN_OVERRIDE':   return 'LEGACY';
      default:                 return action;
    }
  }

  String _actionVerb(String action) {
    switch (action) {
      case 'CREATE':           return 'Scored ';
      case 'UPDATE':           return 'Updated score for ';
      case 'ADMIN_OVERRIDE':   return 'Overrode score for ';
      case 'UNLOCK_REQUESTED': return 'Requested unlock for ';
      case 'UNLOCK_APPROVED':  return 'Approved unlock for ';
      case 'UNLOCK_DENIED':    return 'Denied unlock for ';
      case 'RESUBMIT':         return 'Re-submitted score for ';
      default:                 return 'Action on ';
    }
  }

  String _formatTs(DateTime dt) {
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} $h:$m';
  }
}

// ════════════════════════════════════════════════════════════
// TAB 4: UNLOCK REQUESTS
// ════════════════════════════════════════════════════════════
class _UnlockRequestsTab extends StatefulWidget {
  final int adminId;
  final String apiBase;
  const _UnlockRequestsTab({required this.adminId, required this.apiBase});

  @override
  State<_UnlockRequestsTab> createState() => _UnlockRequestsTabState();
}

class _UnlockRequestsTabState extends State<_UnlockRequestsTab> with AutomaticKeepAliveClientMixin {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  List<dynamic> _requests = [];
  bool _isLoading = true;
  String? _error;
  String _filterStatus = 'PENDING';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final url = '${widget.apiBase}/api/admin/unlock-requests?admin_user_id=${widget.adminId}&status=$_filterStatus';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() { _requests = jsonDecode(res.body); _isLoading = false; });
      } else {
        setState(() { _error = 'Failed to load unlock requests.'; _isLoading = false; });
      }
    } catch (_) {
      setState(() { _error = 'Could not connect to server.'; _isLoading = false; });
    }
  }

  Future<void> _review(dynamic request, bool approve) async {
    final commentController = TextEditingController();
    bool submitting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: approve ? const Color(0xFF27AE60).withOpacity(0.12) : ikuRed.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(approve ? Icons.check_circle_outline : Icons.cancel_outlined,
                    color: approve ? const Color(0xFF27AE60) : ikuRed, size: 18),
              ),
              const SizedBox(width: 10),
              Text(approve ? 'Approve Unlock' : 'Deny Unlock',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ikuGrey)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _kv('Jury',    request['jury_name']),
                  _kv('Student', request['student_name']),
                  _kv('Project', request['project_name']),
                  _kv('Reason',  request['reason']),
                ]),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: approve ? 'Admin note (optional)' : 'Reason for denial (optional)',
                  filled: true, fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: approve ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: approve ? const Color(0xFF27AE60).withOpacity(0.3) : const Color(0xFFFFECB3)),
                ),
                child: Row(children: [
                  Icon(approve ? Icons.info_outline : Icons.warning_amber_rounded,
                      color: approve ? const Color(0xFF27AE60) : const Color(0xFFF57C00), size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    approve ? 'Approval unlocks this evaluation. The jury will re-enter the score.'
                            : 'Denial keeps the evaluation locked. The original score stands.',
                    style: TextStyle(fontSize: 10,
                        color: approve ? Colors.green.shade900 : Colors.orange.shade900,
                        fontWeight: FontWeight.w500),
                  )),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: ikuGrey)),
            ),
            ElevatedButton(
              onPressed: submitting ? null : () async {
                setDialog(() => submitting = true);
                final ok = await _performReview(
                  requestId: request['request_id'], approve: approve,
                  comment: commentController.text.trim(),
                );
                if (!mounted) return;
                Navigator.of(ctx).pop(ok);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: approve ? const Color(0xFF27AE60) : ikuRed,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: submitting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(approve ? 'Approve' : 'Deny',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(approve ? 'Unlock approved. Jury can now re-submit.' : 'Unlock denied.'),
        backgroundColor: approve ? const Color(0xFF27AE60) : Colors.grey.shade700,
      ));
      _load();
    }
  }

  Widget _kv(String k, String? v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text(k,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(v ?? '—',
            style: const TextStyle(fontSize: 12, color: ikuGrey, fontWeight: FontWeight.w700))),
      ]),
    );
  }

  Future<bool> _performReview({required int requestId, required bool approve, required String comment}) async {
    try {
      final res = await http.put(
        Uri.parse('${widget.apiBase}/api/admin/unlock-requests/$requestId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'decision': approve ? 'APPROVE' : 'DENY', 'admin_comment': comment, 'admin_user_id': widget.adminId}),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: ikuRed))
              : _error != null
                  ? Center(child: Text(_error!, style: const TextStyle(color: ikuRed)))
                  : _requests.isEmpty
                      ? _emptyState()
                      : RefreshIndicator(
                          color: ikuRed,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _requests.length,
                            itemBuilder: (_, i) => _requestCard(_requests[i]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _chip('PENDING', 'Pending'), const SizedBox(width: 6),
                _chip('APPROVED', 'Approved'), const SizedBox(width: 6),
                _chip('DENIED', 'Denied'), const SizedBox(width: 6),
                _chip('ALL', 'All'),
              ]),
            ),
          ),
          IconButton(onPressed: _load, icon: Icon(Icons.refresh, size: 20, color: Colors.grey.shade700),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () { if (_filterStatus != value) { setState(() => _filterStatus = value); _load(); } },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? ikuRed : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.grey.shade700)),
      ),
    );
  }

  Widget _emptyState() => Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
      const SizedBox(height: 10),
      Text(_filterStatus == 'PENDING' ? 'No pending unlock requests' : 'No unlock requests found',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
    ],
  ));

  Widget _requestCard(dynamic request) {
    final status        = request['status'] as String;
    final (color, icon, label) = _statusStyle(status);
    final requesterName = request['jury_name']    ?? 'Unknown';
    final studentName   = request['student_name'] ?? 'Unknown';
    final projectName   = request['project_name'] ?? 'Unknown';
    final reason        = request['reason']        ?? '';
    final adminComment  = request['admin_comment'];
    final createdAt     = DateTime.parse(request['created_at']).toLocal();
    final isPending     = status == 'PENDING';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2))],
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 11, color: color), const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5)),
              ]),
            ),
            const Spacer(),
            Text(_formatTs(createdAt), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 14, backgroundColor: ikuRed.withOpacity(0.1),
                child: Text(requesterName.toString().substring(0, 1),
                    style: const TextStyle(color: ikuRed, fontWeight: FontWeight.bold, fontSize: 12))),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(requesterName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ikuGrey)),
              const SizedBox(height: 3),
              Text.rich(TextSpan(
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600, height: 1.4),
                children: [
                  const TextSpan(text: 'Requests unlock for '),
                  TextSpan(text: studentName, style: const TextStyle(fontWeight: FontWeight.w600, color: ikuGrey)),
                  const TextSpan(text: '\n'),
                  TextSpan(text: projectName,
                      style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.grey.shade500)),
                ],
              )),
            ])),
          ]),
          const SizedBox(height: 10),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('REASON', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade500, letterSpacing: 0.6)),
              const SizedBox(height: 3),
              Text(reason.toString(), style: const TextStyle(fontSize: 12, color: ikuGrey, height: 1.4)),
            ]),
          ),
          if (!isPending && adminComment != null && adminComment.toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ADMIN NOTE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.6)),
                const SizedBox(height: 3),
                Text(adminComment.toString(),
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.4, fontStyle: FontStyle.italic)),
              ]),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _review(request, false),
                icon: const Icon(Icons.cancel_outlined, size: 15),
                label: const Text('Deny'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ikuRed, side: BorderSide(color: ikuRed.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              )),
              const SizedBox(width: 8),
              Expanded(child: ElevatedButton.icon(
                onPressed: () => _review(request, true),
                icon: const Icon(Icons.check_circle_outline, size: 15),
                label: const Text('Approve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27AE60), foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              )),
            ]),
          ],
        ],
      ),
    );
  }

  (Color, IconData, String) _statusStyle(String status) {
    switch (status) {
      case 'PENDING':  return (const Color(0xFFFF6B35), Icons.hourglass_empty, 'PENDING');
      case 'APPROVED': return (const Color(0xFF27AE60), Icons.check_circle_outline, 'APPROVED');
      case 'DENIED':   return (const Color(0xFFD31018), Icons.cancel_outlined, 'DENIED');
      default:         return (Colors.grey, Icons.help_outline, status);
    }
  }

  String _formatTs(DateTime dt) {
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} $h:$m';
  }
}