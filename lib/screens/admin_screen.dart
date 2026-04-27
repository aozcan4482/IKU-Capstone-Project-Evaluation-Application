import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> with SingleTickerProviderStateMixin {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);
  static const Color bgColor = Color(0xFFF5F5F7);

  static const String _apiBase = 'http://localhost:3000';

  Map<String, dynamic>? _user;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
      titleSpacing: 12,
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: ikuRed,
            radius: 16,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: ikuGrey,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: ikuRed.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ADMIN',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: ikuRed,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed('/login'),
          icon: const Icon(Icons.logout, color: ikuRed, size: 18),
          label: const Text(
            'Log Out',
            style: TextStyle(color: ikuRed, fontSize: 13),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(49),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: ikuRed,
            unselectedLabelColor: Colors.grey.shade500,
            indicatorColor: ikuRed,
            indicatorWeight: 3,
            labelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            unselectedLabelStyle:
                const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            tabs: const [
              Tab(
                icon: Icon(Icons.insights_outlined, size: 18),
                text: 'Statistics',
                iconMargin: EdgeInsets.only(bottom: 2),
              ),
              Tab(
                icon: Icon(Icons.history, size: 18),
                text: 'Audit Log',
                iconMargin: EdgeInsets.only(bottom: 2),
              ),
              Tab(
                icon: Icon(Icons.lock_open_outlined, size: 18),
                text: 'Unlock Requests',
                iconMargin: EdgeInsets.only(bottom: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// TAB 1: STATISTICS (kompakt)
// ════════════════════════════════════════════════════════════

class _StatisticsTab extends StatefulWidget {
  final int adminId;
  final String apiBase;

  const _StatisticsTab({required this.adminId, required this.apiBase});

  @override
  State<_StatisticsTab> createState() => _StatisticsTabState();
}

class _StatisticsTabState extends State<_StatisticsTab>
    with AutomaticKeepAliveClientMixin {
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await http.get(Uri.parse(
          '${widget.apiBase}/api/admin/statistics?admin_user_id=${widget.adminId}'));
      if (res.statusCode == 200) {
        setState(() {
          _stats = jsonDecode(res.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load statistics.';
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Could not connect to server.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: ikuRed));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: ikuRed)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(backgroundColor: ikuRed),
              child: const Text('Retry', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
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
        gradient: const LinearGradient(
          colors: [ikuRed, Color(0xFFB30E14)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: ikuRed.withOpacity(0.22),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.shield_outlined,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Administrator Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Full system oversight & integrity control',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade500,
          letterSpacing: 0.8,
        ),
      );

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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: s.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(s.icon, size: 14, color: s.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${s.value}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: s.color,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
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
        color: hasOverrides
            ? const Color(0xFFFFF8E1)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasOverrides
              ? const Color(0xFFFFB300)
              : const Color(0xFF27AE60),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasOverrides
                ? Icons.warning_amber_rounded
                : Icons.verified_outlined,
            color: hasOverrides
                ? const Color(0xFFF57C00)
                : const Color(0xFF27AE60),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasOverrides
                      ? '$overrideCount Legacy Override${overrideCount == 1 ? '' : 's'}'
                      : 'No Admin Overrides',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: hasOverrides
                        ? const Color(0xFFE65100)
                        : const Color(0xFF1B5E20),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasOverrides
                      ? 'Historical records from the old override flow.'
                      : 'Evaluation integrity is intact.',
                  style: TextStyle(
                    fontSize: 11,
                    color: hasOverrides
                        ? const Color(0xFF795548)
                        : Colors.green.shade800,
                  ),
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
// TAB 2: AUDIT LOG
// ════════════════════════════════════════════════════════════

class _AuditLogTab extends StatefulWidget {
  final int adminId;
  final String apiBase;

  const _AuditLogTab({required this.adminId, required this.apiBase});

  @override
  State<_AuditLogTab> createState() => _AuditLogTabState();
}

class _AuditLogTabState extends State<_AuditLogTab>
    with AutomaticKeepAliveClientMixin {
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      var url = '${widget.apiBase}/api/admin/audit-log'
          '?admin_user_id=${widget.adminId}';
      if (_filterAction != 'ALL') {
        url += '&action_type=$_filterAction';
      }
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() {
          _logs = jsonDecode(res.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load audit log.';
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Could not connect to server.';
        _isLoading = false;
      });
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
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: ikuRed)))
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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('ALL', 'All'),
                  const SizedBox(width: 6),
                  _filterChip('CREATE', 'Create'),
                  const SizedBox(width: 6),
                  _filterChip('UPDATE', 'Update'),
                  const SizedBox(width: 6),
                  _filterChip('UNLOCK_REQUESTED', 'Unlock Req'),
                  const SizedBox(width: 6),
                  _filterChip('UNLOCK_APPROVED', 'Approved'),
                  const SizedBox(width: 6),
                  _filterChip('UNLOCK_DENIED', 'Denied'),
                  const SizedBox(width: 6),
                  _filterChip('RESUBMIT', 'Resubmit'),
                  const SizedBox(width: 6),
                  _filterChip('ADMIN_OVERRIDE', 'Legacy'),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh, size: 20, color: Colors.grey.shade700),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final isSelected = _filterAction == value;
    return GestureDetector(
      onTap: () {
        if (_filterAction != value) {
          setState(() => _filterAction = value);
          _load();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? ikuRed : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(
            'No audit records found',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _logCard(dynamic log) {
    final action = log['action_type'] as String;
    final (color, icon) = _actionStyle(action);
    final actorName = log['actor_name'] ?? 'Unknown';
    final actorRole = log['actor_role'] ?? '';
    final studentName = log['student_name'] ?? 'Unknown';
    final projectName = log['project_name'] ?? 'Unknown';
    final criteriaName = log['criteria_name'] ?? 'Unknown';
    final oldScore = log['old_score'];
    final newScore = log['new_score'];
    final comment = log['comment'];
    final ts = DateTime.parse(log['timestamp']).toLocal();

    final isScoreAction = action == 'CREATE' ||
        action == 'UPDATE' ||
        action == 'ADMIN_OVERRIDE' ||
        action == 'RESUBMIT';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 11, color: color),
                    const SizedBox(width: 4),
                    Text(
                      _actionLabel(action),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _formatTs(ts),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: color.withOpacity(0.1),
                child: Text(
                  actorName.toString().substring(0, 1),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            actorName,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: ikuGrey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            actorRole.toString().toUpperCase(),
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(text: _actionVerb(action)),
                          TextSpan(
                            text: studentName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: ikuGrey),
                          ),
                          const TextSpan(text: ' on '),
                          TextSpan(
                            text: criteriaName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: ikuGrey),
                          ),
                          const TextSpan(text: '\n'),
                          TextSpan(
                            text: projectName,
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isScoreAction) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (oldScore != null) ...[
                    Text(
                      '${oldScore.toString()}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade500,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward,
                        size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '${newScore?.toString() ?? '—'}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isScoreAction && comment != null && comment.toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                comment.toString(),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  (Color, IconData) _actionStyle(String action) {
    switch (action) {
      case 'CREATE':
        return (const Color(0xFF27AE60), Icons.add_circle_outline);
      case 'UPDATE':
        return (const Color(0xFFFF6B35), Icons.edit_outlined);
      case 'ADMIN_OVERRIDE':
        return (ikuRed, Icons.shield_outlined);
      case 'UNLOCK_REQUESTED':
        return (const Color(0xFF2E86DE), Icons.mail_outline);
      case 'UNLOCK_APPROVED':
        return (const Color(0xFF27AE60), Icons.check_circle_outline);
      case 'UNLOCK_DENIED':
        return (ikuRed, Icons.cancel_outlined);
      case 'RESUBMIT':
        return (const Color(0xFFFF6B35), Icons.refresh);
      default:
        return (Colors.grey, Icons.help_outline);
    }
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'UNLOCK_REQUESTED':
        return 'UNLOCK REQ';
      case 'UNLOCK_APPROVED':
        return 'APPROVED';
      case 'UNLOCK_DENIED':
        return 'DENIED';
      case 'ADMIN_OVERRIDE':
        return 'LEGACY';
      default:
        return action;
    }
  }

  String _actionVerb(String action) {
    switch (action) {
      case 'CREATE':
        return 'Scored ';
      case 'UPDATE':
        return 'Updated score for ';
      case 'ADMIN_OVERRIDE':
        return 'Overrode score for ';
      case 'UNLOCK_REQUESTED':
        return 'Requested unlock for ';
      case 'UNLOCK_APPROVED':
        return 'Approved unlock for ';
      case 'UNLOCK_DENIED':
        return 'Denied unlock for ';
      case 'RESUBMIT':
        return 'Re-submitted score for ';
      default:
        return 'Action on ';
    }
  }

  String _formatTs(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} $h:$m';
  }
}

// ════════════════════════════════════════════════════════════
// TAB 3: UNLOCK REQUESTS
// ════════════════════════════════════════════════════════════

class _UnlockRequestsTab extends StatefulWidget {
  final int adminId;
  final String apiBase;

  const _UnlockRequestsTab({required this.adminId, required this.apiBase});

  @override
  State<_UnlockRequestsTab> createState() => _UnlockRequestsTabState();
}

class _UnlockRequestsTabState extends State<_UnlockRequestsTab>
    with AutomaticKeepAliveClientMixin {
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      var url = '${widget.apiBase}/api/admin/unlock-requests'
          '?admin_user_id=${widget.adminId}'
          '&status=$_filterStatus';
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        setState(() {
          _requests = jsonDecode(res.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load unlock requests.';
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _error = 'Could not connect to server.';
        _isLoading = false;
      });
    }
  }

  Future<void> _review(dynamic request, bool approve) async {
    final commentController = TextEditingController();
    bool submitting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: approve
                          ? const Color(0xFF27AE60).withOpacity(0.12)
                          : ikuRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      approve
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined,
                      color: approve ? const Color(0xFF27AE60) : ikuRed,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    approve ? 'Approve Unlock' : 'Deny Unlock',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: ikuGrey),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kv('Jury', request['jury_name']),
                        _kv('Student', request['student_name']),
                        _kv('Criteria', request['criteria_name']),
                        _kv('Current score',
                            request['score']?.toString()),
                        _kv('Reason', request['reason']),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: approve
                          ? 'Admin note (optional)'
                          : 'Reason for denial (optional)',
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: approve
                          ? const Color(0xFFE8F5E9)
                          : const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: approve
                              ? const Color(0xFF27AE60).withOpacity(0.3)
                              : const Color(0xFFFFECB3)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          approve
                              ? Icons.info_outline
                              : Icons.warning_amber_rounded,
                          color: approve
                              ? const Color(0xFF27AE60)
                              : const Color(0xFFF57C00),
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            approve
                                ? 'Approval unlocks this evaluation. The jury will re-enter the score.'
                                : 'Denial keeps the evaluation locked. The original score stands.',
                            style: TextStyle(
                                fontSize: 10,
                                color: approve
                                    ? Colors.green.shade900
                                    : Colors.orange.shade900,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel',
                      style: TextStyle(color: ikuGrey)),
                ),
                ElevatedButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialog(() => submitting = true);
                          final ok = await _performReview(
                            requestId: request['request_id'],
                            approve: approve,
                            comment: commentController.text.trim(),
                          );
                          if (!mounted) return;
                          Navigator.of(ctx).pop(ok);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        approve ? const Color(0xFF27AE60) : ikuRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(approve ? 'Approve' : 'Deny',
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve
              ? 'Unlock approved. Jury can now re-submit.'
              : 'Unlock denied.'),
          backgroundColor:
              approve ? const Color(0xFF27AE60) : Colors.grey.shade700,
        ),
      );
      _load();
    }
  }

  Widget _kv(String k, String? v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(k,
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(v ?? '—',
                style: const TextStyle(
                    fontSize: 12,
                    color: ikuGrey,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<bool> _performReview({
    required int requestId,
    required bool approve,
    required String comment,
  }) async {
    try {
      final res = await http.put(
        Uri.parse(
            '${widget.apiBase}/api/admin/unlock-requests/$requestId'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'decision': approve ? 'APPROVE' : 'DENY',
          'admin_comment': comment,
          'admin_user_id': widget.adminId,
        }),
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
                  ? Center(
                      child: Text(_error!,
                          style: const TextStyle(color: ikuRed)))
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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _chip('PENDING', 'Pending'),
                  const SizedBox(width: 6),
                  _chip('APPROVED', 'Approved'),
                  const SizedBox(width: 6),
                  _chip('DENIED', 'Denied'),
                  const SizedBox(width: 6),
                  _chip('ALL', 'All'),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: _load,
            icon: Icon(Icons.refresh, size: 20, color: Colors.grey.shade700),
            tooltip: 'Refresh',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _chip(String value, String label) {
    final isSelected = _filterStatus == value;
    return GestureDetector(
      onTap: () {
        if (_filterStatus != value) {
          setState(() => _filterStatus = value);
          _load();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? ikuRed : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isSelected ? Colors.white : Colors.grey.shade700,
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text(
            _filterStatus == 'PENDING'
                ? 'No pending unlock requests'
                : 'No unlock requests found',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(dynamic request) {
    final status = request['status'] as String;
    final (color, icon, label) = _statusStyle(status);
    final requesterName = request['jury_name'] ?? 'Unknown';
    final studentName = request['student_name'] ?? 'Unknown';
    final criteriaName = request['criteria_name'] ?? 'Unknown';
    final projectName = request['project_name'] ?? 'Unknown';
    final reason = request['reason'] ?? '';
    final currentScore = request['score'];
    final adminComment = request['admin_comment'];
    final createdAt = DateTime.parse(request['created_at']).toLocal();
    final isPending = status == 'PENDING';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 11, color: color),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _formatTs(createdAt),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: ikuRed.withOpacity(0.1),
                child: Text(
                  requesterName.toString().substring(0, 1),
                  style: const TextStyle(
                    color: ikuRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requesterName,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: ikuGrey),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                        children: [
                          const TextSpan(text: 'Requests unlock for '),
                          TextSpan(
                            text: studentName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: ikuGrey),
                          ),
                          const TextSpan(text: ' — '),
                          TextSpan(
                            text: criteriaName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, color: ikuGrey),
                          ),
                          const TextSpan(text: '\n'),
                          TextSpan(
                            text: projectName,
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (currentScore != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'Score',
                        style: TextStyle(
                            fontSize: 8,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                      Text(
                        currentScore.toString(),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: ikuGrey),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REASON',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade500,
                      letterSpacing: 0.6),
                ),
                const SizedBox(height: 3),
                Text(
                  reason.toString(),
                  style: const TextStyle(
                      fontSize: 12, color: ikuGrey, height: 1.4),
                ),
              ],
            ),
          ),
          if (!isPending && adminComment != null && adminComment.toString().isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ADMIN NOTE',
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: color,
                        letterSpacing: 0.6),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    adminComment.toString(),
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                        height: 1.4,
                        fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _review(request, false),
                    icon: const Icon(Icons.cancel_outlined, size: 15),
                    label: const Text('Deny'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: ikuRed,
                      side: BorderSide(color: ikuRed.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _review(request, true),
                    icon: const Icon(Icons.check_circle_outline, size: 15),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF27AE60),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  (Color, IconData, String) _statusStyle(String status) {
    switch (status) {
      case 'PENDING':
        return (const Color(0xFFFF6B35), Icons.hourglass_empty, 'PENDING');
      case 'APPROVED':
        return (const Color(0xFF27AE60), Icons.check_circle_outline, 'APPROVED');
      case 'DENIED':
        return (ikuRed, Icons.cancel_outlined, 'DENIED');
      default:
        return (Colors.grey, Icons.help_outline, status);
    }
  }

  String _formatTs(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} $h:$m';
  }
}