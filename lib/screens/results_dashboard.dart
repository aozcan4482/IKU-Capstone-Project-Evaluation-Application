import 'package:flutter/material.dart';
import 'package:capstone_evaluationapp/models/project.dart';

class ResultsDashboard extends StatelessWidget {
  final CapstoneProject project;
  final Map<String, Map<String, double?>> confirmedScores;
  final List<String> criteria;
  final Map<String, double> criteriaWeights;

  const ResultsDashboard({
    super.key,
    required this.project,
    required this.confirmedScores,
    required this.criteria,
    required this.criteriaWeights,
  });

  static const Color _ikuRed  = Color(0xFFD31018);
  static const Color _ikuGrey = Color(0xFF4A4A49);

  double _weightedAverage(Map<String, double?> scores) {
    double total = 0;
    double totalWeight = 0;
    for (final c in criteria) {
      final score = scores[c];
      final weight = criteriaWeights[c] ?? 0;
      if (score != null) {
        total += score * weight;
        totalWeight += weight;
      }
    }
    if (totalWeight == 0) return 0;
    return total / totalWeight;
  }

  @override
  Widget build(BuildContext context) {
    final gradedEntries = confirmedScores.entries.toList();
    if (gradedEntries.isEmpty) return const SizedBox.shrink();

    final Map<String, double> averages = {};
    for (final entry in gradedEntries) {
      averages[entry.key] = _weightedAverage(entry.value);
    }

    final ranked = averages.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final nameById = {
      for (final m in project.members) m.studentId: m.name,
    };

    final allGraded = gradedEntries.length == project.members.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(allGraded, gradedEntries.length),
        const SizedBox(height: 14),
        _rankingCard(ranked, nameById, averages),
        const SizedBox(height: 12),
        _juryEvaluationsCard(ranked, nameById, averages),
        const SizedBox(height: 12),
        _finalScoresCard(ranked, nameById, averages),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _header(bool allGraded, int gradedCount) {
    return Row(
      children: [
        Container(
          width: 4, height: 18,
          decoration: BoxDecoration(
            color: _ikuRed, borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'RESULTS DASHBOARD',
          style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800,
            color: _ikuGrey, letterSpacing: 0.6,
          ),
        ),
        const Spacer(),
        if (allGraded)
          _pill('All Graded', const Color(0xFF27AE60))
        else
          Text(
            '$gradedCount/${project.members.length} graded',
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: Colors.grey.shade400,
            ),
          ),
      ],
    );
  }

  Widget _rankingCard(
    List<MapEntry<String, double>> ranked,
    Map<String, String> nameById,
    Map<String, double> averages,
  ) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('RANKING'),
          const SizedBox(height: 10),
          ...ranked.asMap().entries.map((e) {
            final rank      = e.key + 1;
            final studentId = e.value.key;
            final avg       = e.value.value;
            final name      = nameById[studentId] ?? studentId;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  _rankBadge(rank),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: _ikuGrey,
                        )),
                        Text(studentId, style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade400,
                        )),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(avg.toStringAsFixed(1), style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800, color: _scoreColor(avg),
                      )),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 100,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: avg / 100,
                            minHeight: 5,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(_scoreColor(avg)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _juryEvaluationsCard(
    List<MapEntry<String, double>> ranked,
    Map<String, String> nameById,
    Map<String, double> averages,
  ) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('JURY EVALUATIONS'),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder(
                horizontalInside: BorderSide(color: Colors.grey.shade100, width: 1),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: Colors.grey.shade50),
                  children: [
                    _tHeader('Student'),
                    ...criteria.map(_tHeader),
                    _tHeader('Weighted Avg'),
                  ],
                ),
                ...ranked.map((e) {
                  final studentId = e.key;
                  final name   = nameById[studentId] ?? studentId;
                  final scores = confirmedScores[studentId]!;
                  final avg    = averages[studentId]!;

                  return TableRow(children: [
                    _tCell(name.split(' ').first, style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: _ikuGrey,
                    )),
                    ...criteria.map((c) {
                      final val = scores[c];
                      return _tCell(
                        val != null ? val.toStringAsFixed(0) : '—',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: val != null ? _scoreColor(val) : Colors.grey.shade400,
                        ),
                      );
                    }),
                    _tCell(avg.toStringAsFixed(1), style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: _scoreColor(avg),
                    )),
                  ]);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _finalScoresCard(
    List<MapEntry<String, double>> ranked,
    Map<String, String> nameById,
    Map<String, double> averages,
  ) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('FINAL SCORES'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: ranked.asMap().entries.map((e) {
              final rank      = e.key + 1;
              final studentId = e.value.key;
              final name      = nameById[studentId] ?? studentId;
              final avg       = averages[studentId]!;
              final color     = _scoreColor(avg);

              return Container(
                width: 140,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: _ikuGrey,
                            )),
                        ),
                        Text('#$rank', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: color,
                        )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(avg.toStringAsFixed(1), style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900, color: color,
                    )),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: avg / 100, minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_scoreLabel(avg), style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: color,
                    )),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        child: child,
      );

  Widget _sectionLabel(String label) => Text(
        label,
        style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: Colors.grey.shade400, letterSpacing: 0.8,
        ),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, color: color,
        )),
      );

  Widget _rankBadge(int rank) {
    final colors = {
      1: const Color(0xFFFFC107),
      2: const Color(0xFF9E9E9E),
      3: const Color(0xFFCD7F32),
    };
    final color = colors[rank] ?? _ikuGrey.withOpacity(0.5);
    return Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), shape: BoxShape.circle,
      ),
      child: Center(
        child: rank <= 3
            ? Icon(Icons.emoji_events_outlined, size: 16, color: color)
            : Text('$rank', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color,
              )),
      ),
    );
  }

  Widget _tHeader(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: Colors.grey.shade500, letterSpacing: 0.5,
            )),
      );

  Widget _tCell(String text, {required TextStyle style}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Text(text, textAlign: TextAlign.center, style: style),
      );

  Color _scoreColor(double s) {
    if (s >= 70) return const Color(0xFF27AE60);
    if (s >= 50) return const Color(0xFFE55A00);
    return _ikuRed;
  }

  String _scoreLabel(double s) {
    if (s >= 85) return 'Excellent';
    if (s >= 70) return 'Good';
    if (s >= 55) return 'Satisfactory';
    if (s >= 50) return 'Passing';
    return 'Failing';
  }
}