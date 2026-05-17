import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:capstone_evaluationapp/models/project.dart';
import 'package:capstone_evaluationapp/screens/results_dashboard.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:capstone_evaluationapp/config.dart';

class EvaluationScreen extends StatefulWidget {
  final CapstoneProject project;
  final int juryId;

  const EvaluationScreen({super.key, required this.project, required this.juryId});

  @override
  State<EvaluationScreen> createState() => _EvaluationScreenState();
}

class _EvaluationScreenState extends State<EvaluationScreen> {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);
  static const Color bgColor = Color(0xFFF5F5F7);

  static const Color statusNotStarted = Color(0xFF9E9E9E);
  static const Color statusInProgress = Color(0xFFFF6B35);
  static const Color statusSubmitted = Color(0xFF2ECC71);

  String? _expandedMemberId;
  String? _gradingMemberId;

  Map<String, MemberEvaluation> _evaluations = {};
  List<Map<String, dynamic>> _criteria = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final criteriaResp = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/criteria'),
      );
      if (criteriaResp.statusCode == 200) {
        final List data = jsonDecode(criteriaResp.body);
        _criteria = data.map((c) => {
          'id': c['criteria_id'],
          'name': c['criteria_name'],
          'weight': c['weight'],
        }).toList();
      }

      final criteriaNames = _criteria.map((c) => c['name'] as String).toList();

      final evalResp = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/evaluations/jury/${widget.juryId}/project/${widget.project.id}',
        ),
      );

      final Map<String, MemberEvaluation> evaluations = {
        for (final m in widget.project.members)
          m.studentId: MemberEvaluation.empty(criteriaNames),
      };

      if (evalResp.statusCode == 200) {
        final List backendRows = jsonDecode(evalResp.body);

        final Map<String, List<dynamic>> byStudent = {};
        for (final row in backendRows) {
          final studentUserId = row['student_id'].toString();
          final member = widget.project.members.firstWhere(
            (m) => m.userId.toString() == studentUserId,
            orElse: () => ProjectMember(userId: -1, name: '', studentId: ''),
          );
          if (member.userId == -1) continue;

          byStudent.putIfAbsent(member.studentId, () => []);
          byStudent[member.studentId]!.add(row);
        }

        for (final member in widget.project.members) {
          final rows = byStudent[member.studentId];
          if (rows == null || rows.isEmpty) continue;

          final scores = <String, double?>{};
          final ids    = <int>[];
          for (final r in rows) {
            scores[r['criteria_name'] as String] = (r['score'] as num).toDouble();
            ids.add(r['evaluation_id'] as int);
          }

          final allSubmitted = rows.every((r) => r['is_submitted'] == true);
          final anyUnlocked  = rows.any((r) => r['is_submitted'] == false);

          if (anyUnlocked) {
            evaluations[member.studentId] = MemberEvaluation(
              scores: scores,
              status: MemberEvaluationStatus.inProgress,
              evaluationIds: ids,
            );
          } else if (allSubmitted) {
            evaluations[member.studentId] = MemberEvaluation(
              scores: scores,
              status: MemberEvaluationStatus.submitted,
              submittedAt: DateTime.now(),
              evaluationIds: ids,
            );
          }
        }
      }

      setState(() {
        _evaluations = evaluations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  List<String> get _criteriaNames =>
      _criteria.map((c) => c['name'] as String).toList();

  Map<String, double> get _criteriaWeights => {
    for (final c in _criteria)
      c['name'] as String: (c['weight'] as num).toDouble()
  };

  void _saveDraft(ProjectMember member, Map<String, double?> scores) {
    final hasAny = scores.values.any((v) => v != null);
    final newEval = MemberEvaluation(
      scores: scores,
      status: hasAny
          ? MemberEvaluationStatus.inProgress
          : MemberEvaluationStatus.notStarted,
      evaluationIds: _evaluations[member.studentId]?.evaluationIds ?? [],
    );
    setState(() {
      _evaluations[member.studentId] = newEval;
    });
  }

  Future<bool> _submit(ProjectMember member, Map<String, double?> scores) async {
    for (final c in _criteriaNames) {
      final v = scores[c];
      if (v == null || v < 0 || v > 100) return false;
    }

    try {
      final List<int> collectedIds = [];
      bool anyFailed = false;

      for (final c in _criteria) {
        final score = scores[c['name']];
        final resp = await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/evaluations'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jury_id':    widget.juryId,
            'project_id': int.parse(widget.project.id),
            'criteria_id': c['id'],
            'student_id': member.userId,
            'score':      score,
            'comment':    '',
          }),
        );

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          try {
            final body = jsonDecode(resp.body);
            if (body is Map && body['evaluation_id'] != null) {
              collectedIds.add(body['evaluation_id'] as int);
            }
          } catch (_) {}
        } else {
          anyFailed = true;
          break;
        }
      }

      if (anyFailed) return false;

      setState(() {
        _evaluations[member.studentId] = MemberEvaluation(
          scores: scores,
          status: MemberEvaluationStatus.submitted,
          submittedAt: DateTime.now(),
          evaluationIds: collectedIds,
        );
      });

      final allSubmitted = widget.project.members.every((m) =>
          _evaluations[m.studentId]?.status == MemberEvaluationStatus.submitted);
      if (allSubmitted) {
        await http.post(
          Uri.parse('${AppConfig.baseUrl}/api/results/${widget.project.id}'),
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _allSubmitted => widget.project.members.every((m) =>
      _evaluations[m.studentId]?.status == MemberEvaluationStatus.submitted);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: ikuRed))
          : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: ikuGrey),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Evaluation',
        style: TextStyle(
          color: ikuGrey,
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildProjectHeader(),
        const SizedBox(height: 20),
        Text(
          'STUDENTS',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade400,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        ...widget.project.members.map((m) => _buildMemberCard(m)),
        if (_allSubmitted) ...[
          const SizedBox(height: 20),
          ResultsDashboard(
            project: widget.project,
            confirmedScores: {
              for (final m in widget.project.members)
                m.studentId: _evaluations[m.studentId]?.scores ?? {}
            },
            criteria: _criteriaNames,
            criteriaWeights: _criteriaWeights,
          ),
        ],
      ],
    );
  }

  Widget _buildProjectHeader() {
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
          Row(
            children: [
              Container(
                width: 4, height: 20,
                decoration: BoxDecoration(
                  color: ikuRed,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.project.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: ikuGrey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            widget.project.description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.school_outlined, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text('Advisor: ',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                      fontWeight: FontWeight.w600)),
              Text(widget.project.advisor,
                  style: const TextStyle(
                      fontSize: 12, color: ikuGrey, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.schedule, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(
                _formatDateTime(widget.project.examDateTime),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ThesisSection(projectId: int.parse(widget.project.id)),
        ],
      ),
    );
  }

  Widget _buildMemberCard(ProjectMember member) {
    final isExpanded = _expandedMemberId == member.studentId;
    final isGrading  = _gradingMemberId  == member.studentId;
    final eval       = _evaluations[member.studentId] ?? MemberEvaluation.empty(_criteriaNames);
    final status     = eval.status;
    final isLocked   = status == MemberEvaluationStatus.submitted;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedMemberId = null;
            _gradingMemberId  = null;
          } else {
            _expandedMemberId = member.studentId;
            _gradingMemberId  = null;
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded ? ikuRed.withOpacity(0.35) : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
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
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: ikuRed.withOpacity(0.1),
                        child: Text(
                          member.name.substring(0, 1),
                          style: const TextStyle(
                            color: ikuRed, fontWeight: FontWeight.bold, fontSize: 14,
                          ),
                        ),
                      ),
                      if (isLocked)
                        Positioned(
                          right: -2, bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: statusSubmitted,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.5),
                            ),
                            child: const Icon(Icons.lock, size: 10, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: ikuGrey)),
                        const SizedBox(height: 2),
                        Text(
                          status == MemberEvaluationStatus.inProgress
                              ? 'Draft · ${eval.gradedCount}/${_criteriaNames.length} criteria'
                              : status == MemberEvaluationStatus.submitted
                                  ? 'Submitted ${_formatSubmittedDate(eval.submittedAt)}'
                                  : member.studentId,
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  _memberStatusBadge(status),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: ikuGrey, size: 20,
                  ),
                ],
              ),
            ),
            if (isExpanded) ...[
              if (isLocked)
                _buildLockedView(member, eval)
              else if (isGrading)
                _buildGradingForm(member, eval)
              else
                _buildMemberActions(member, eval),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberStatusBadge(MemberEvaluationStatus status) {
    final color = status == MemberEvaluationStatus.submitted
        ? statusSubmitted
        : status == MemberEvaluationStatus.inProgress
            ? statusInProgress
            : statusNotStarted;
    final label = status == MemberEvaluationStatus.submitted
        ? 'Submitted'
        : status == MemberEvaluationStatus.inProgress
            ? 'Draft'
            : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _buildLockedView(ProjectMember member, MemberEvaluation eval) {
    final canRequestUnlock = eval.evaluationIds.isNotEmpty;

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
          Row(
            children: [
              Icon(Icons.lock, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This evaluation has been submitted and is locked.',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('SCORES',
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.grey.shade400, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          ...eval.scores.entries.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(e.key, style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  Text(
                    e.value != null ? e.value!.toStringAsFixed(1) : '—',
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.grey.shade200),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Need to correct a score? Request unlock from admin.',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: canRequestUnlock
                  ? () => _openUnlockRequestSheet(member, eval)
                  : null,
              icon: const Icon(Icons.lock_open_outlined, size: 16),
              label: Text(canRequestUnlock
                  ? 'Request Unlock'
                  : 'Unlock unavailable (legacy record)'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ikuRed,
                side: BorderSide(
                    color: canRequestUnlock
                        ? ikuRed.withOpacity(0.5)
                        : Colors.grey.shade300),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberActions(ProjectMember member, MemberEvaluation eval) {
    final hasScores = eval.scores.values.any((v) => v != null);

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
          if (hasScores) ...[
            Text('CURRENT DRAFT',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700,
                    color: Colors.grey.shade400, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            ...eval.scores.entries.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.key,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    Text(
                      e.value != null ? e.value!.toStringAsFixed(1) : '—',
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: ikuGrey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _gradingMemberId = member.studentId);
              },
              icon: Icon(hasScores ? Icons.edit : Icons.grade_outlined, size: 17),
              label: Text(hasScores ? 'Continue Grading' : 'Grade Student'),
              style: ElevatedButton.styleFrom(
                backgroundColor: ikuRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradingForm(ProjectMember member, MemberEvaluation eval) {
    final controllers = <String, TextEditingController>{
      for (final c in _criteria)
        c['name'] as String: TextEditingController(
          text: eval.scores[c['name']]?.toString() ?? '',
        ),
    };

    return StatefulBuilder(
      builder: (context, setLocal) {
        bool isSaving = false;

        Map<String, double?> readScores() {
          final scores = <String, double?>{};
          for (final c in _criteria) {
            final name = c['name'] as String;
            final raw  = controllers[name]!.text.trim();
            scores[name] = raw.isEmpty ? null : double.tryParse(raw);
          }
          return scores;
        }

        bool validateRange(Map<String, double?> scores) {
          for (final v in scores.values) {
            if (v != null && (v < 0 || v > 100)) return false;
          }
          return true;
        }

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
              Text('ENTER SCORES  (0 – 100)',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: Colors.grey.shade400, letterSpacing: 0.8)),
              const SizedBox(height: 12),
              ..._criteria.map(
                (criterion) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[criterion['name']],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: criterion['name'],
                      filled: true,
                      fillColor: Colors.white,
                      suffixText: 'pts',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setState(() => _gradingMemberId = null);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ikuGrey,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSaving
                          ? null
                          : () {
                              final scores = readScores();
                              if (!validateRange(scores)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('All scores must be between 0 and 100.'),
                                    backgroundColor: ikuRed,
                                  ),
                                );
                                return;
                              }
                              _saveDraft(member, scores);
                              setState(() => _gradingMemberId = null);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('Draft saved'),
                                  backgroundColor: statusInProgress,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            },
                      icon: const Icon(Icons.save_outlined, size: 16, color: ikuGrey),
                      label: const Text('Save Draft', style: TextStyle(color: ikuGrey)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final scores = readScores();
                              if (!validateRange(scores)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('All scores must be between 0 and 100.'),
                                    backgroundColor: ikuRed,
                                  ),
                                );
                                return;
                              }
                              final allFilled =
                                  _criteriaNames.every((n) => scores[n] != null);
                              if (!allFilled) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('All criteria must be filled before submission.'),
                                    backgroundColor: ikuRed,
                                  ),
                                );
                                return;
                              }
                              _saveDraft(member, scores);
                              await _openReviewSheet(member, scores);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ikuRed,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      child: const Text('Review & Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openReviewSheet(ProjectMember member, Map<String, double?> scores) async {
    double previewScore = 0;
    double totalWeight  = 0;
    for (final c in _criteria) {
      final name   = c['name'] as String;
      final weight = (c['weight'] as num).toDouble();
      final score  = scores[name];
      if (score != null) {
        previewScore += score * weight;
        totalWeight  += weight;
      }
    }
    final weightedAvg = totalWeight == 0 ? 0 : previewScore / totalWeight;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Final Review',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800, color: ikuGrey)),
                  const SizedBox(height: 4),
                  Text(member.name,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: ikuRed.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Weighted Average',
                            style: TextStyle(
                                fontSize: 13, color: ikuGrey, fontWeight: FontWeight.w600)),
                        Text(
                          weightedAvg.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 24, fontWeight: FontWeight.w900, color: ikuRed),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('SCORES BREAKDOWN',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: Colors.grey.shade400, letterSpacing: 0.8)),
                  const SizedBox(height: 8),
                  ...scores.entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                                child: Text(e.key,
                                    style: const TextStyle(fontSize: 13, color: ikuGrey))),
                            Text(
                              e.value != null ? e.value!.toStringAsFixed(1) : '—',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w700, color: ikuGrey),
                            ),
                          ],
                        ),
                      )),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFECB3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFF57C00), size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Once submitted, you cannot edit these scores.',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ikuGrey,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Back to Edit'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                                  setSheet(() => submitting = true);
                                  final ok = await _submit(member, scores);
                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  if (ok) {
                                    setState(() {
                                      _gradingMemberId = null;
                                      _expandedMemberId = null;
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Evaluation submitted and locked.'),
                                        backgroundColor: statusSubmitted,
                                      ),
                                    );
                                  } else {
                                    setSheet(() => submitting = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Submission failed. Try again.'),
                                        backgroundColor: ikuRed,
                                      ),
                                    );
                                  }
                                },
                          icon: submitting
                              ? const SizedBox(
                                  height: 16, width: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.lock, size: 16),
                          label: Text(submitting ? 'Submitting...' : 'Confirm & Submit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ikuRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openUnlockRequestSheet(ProjectMember member, MemberEvaluation eval) async {
    final reasonController = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool submitting = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: EdgeInsets.only(
                left: 20, right: 20, top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ikuRed.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.lock_open_outlined, color: ikuRed, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Request Unlock',
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w800, color: ikuGrey)),
                            SizedBox(height: 2),
                            Text('Admin will review your request',
                                style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('STUDENT',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: Colors.grey.shade500, letterSpacing: 0.6)),
                        const SizedBox(height: 4),
                        Text(member.name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w700, color: ikuGrey)),
                        const SizedBox(height: 2),
                        Text(
                          '${eval.evaluationIds.length} criteria will be unlocked',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('REASON',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: ikuGrey, letterSpacing: 0.6)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonController,
                    maxLines: 3,
                    maxLength: 300,
                    decoration: InputDecoration(
                      hintText: 'Why do you need to re-evaluate?\ne.g. "I mis-entered the Technical Merits score"',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFFECB3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFF57C00), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'This request will be logged and reviewed by admin. '
                            'Your submitted scores remain locked until approved.',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ikuGrey,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: submitting
                              ? null
                              : () async {
                                  final reason = reasonController.text.trim();
                                  if (reason.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Please provide a reason.'),
                                        backgroundColor: ikuRed,
                                      ),
                                    );
                                    return;
                                  }
                                  setSheet(() => submitting = true);
                                  final ok = await _submitUnlockRequest(
                                    member: member,
                                    reason: reason,
                                  );
                                  if (!mounted) return;
                                  Navigator.of(ctx).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Unlock request sent to admin.'
                                          : 'Failed to send request. Try again.'),
                                      backgroundColor: ok
                                          ? const Color(0xFF27AE60)
                                          : ikuRed,
                                    ),
                                  );
                                },
                          icon: submitting
                              ? const SizedBox(
                                  height: 16, width: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.send_outlined, size: 16),
                          label: Text(submitting ? 'Sending...' : 'Send Request'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ikuRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            textStyle: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _submitUnlockRequest({
    required ProjectMember member,
    required String reason,
  }) async {
    try {
      final resp = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/unlock-requests'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'jury_id':    widget.juryId,
          'project_id': int.parse(widget.project.id),
          'student_id': member.userId,
          'reason':     reason,
        }),
      );
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  String _formatDateTime(DateTime dt) {
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month]} ${dt.year}  •  $h:$m';
  }

  String _formatSubmittedDate(DateTime? dt) {
    if (dt == null) return '';
    const months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return 'on ${dt.day} ${months[dt.month]} ${dt.year}';
  }
}

// ════════════════════════════════════════════════════════════
// Thesis Section Widget (Jüri için rapor görüntüleme)
// ════════════════════════════════════════════════════════════
class _ThesisSection extends StatefulWidget {
  final int projectId;
  const _ThesisSection({required this.projectId});

  @override
  State<_ThesisSection> createState() => _ThesisSectionState();
}

class _ThesisSectionState extends State<_ThesisSection> {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);

  List<dynamic> _reports = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/reports/${widget.projectId}'),
      );
      if (res.statusCode == 200) {
        setState(() { _reports = jsonDecode(res.body); _isLoading = false; });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openReport(String filePath) async {
    final url = Uri.parse('${AppConfig.baseUrl}/$filePath');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open file: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator(color: ikuRed, strokeWidth: 2)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.description_outlined, size: 14, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              'THESIS',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade400,
                  letterSpacing: 0.8),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_reports.isEmpty)
          Text(
            'No thesis uploaded yet.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          )
        else
          ..._reports.map((report) {
            final filename = report['filename'] ?? 'thesis.pdf';
            final studentName = report['student_name'] ?? '';
            return GestureDetector(
              onTap: () => _openReport(report['file_path']),
              child: Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: ikuRed.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ikuRed.withOpacity(0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_outlined, color: ikuRed, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(filename,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: ikuGrey),
                              overflow: TextOverflow.ellipsis),
                          if (studentName.isNotEmpty)
                            Text(studentName,
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    Icon(Icons.open_in_new_outlined,
                        size: 14, color: ikuRed.withOpacity(0.7)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}