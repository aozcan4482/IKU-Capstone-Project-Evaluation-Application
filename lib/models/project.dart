// lib/models/project.dart

/// Bir üyenin (öğrencinin) bu jüri tarafından değerlendirilme durumu.
enum MemberEvaluationStatus {
  notStarted,  // Hiç puan girilmemiş
  inProgress,  // Draft — bazı/tüm puanlar var, submit edilmemiş
  submitted,   // Submit edilmiş, locked
}

/// Bir üyenin değerlendirmesinin runtime durumu.
/// SharedPreferences'tan yüklenir ve jüri ekranda çalışırken güncellenir.
class MemberEvaluation {
  final Map<String, double?> scores;
  final MemberEvaluationStatus status;
  final DateTime? submittedAt;
  
  // YENİ: Bu üyeye ait backend evaluation_id'leri (her kriter için bir tane)
  // Sadece submit edilmiş ise dolu olur, SharedPreferences'tan gelmez
  final List<int> evaluationIds;

  const MemberEvaluation({
    required this.scores,
    required this.status,
    this.submittedAt,
    this.evaluationIds = const [],
  });

  int get gradedCount => scores.values.where((v) => v != null).length;

  factory MemberEvaluation.empty(List<String> criteria) {
    return MemberEvaluation(
      scores: {for (final c in criteria) c: null},
      status: MemberEvaluationStatus.notStarted,
    );
  }

  MemberEvaluation copyWith({
    Map<String, double?>? scores,
    MemberEvaluationStatus? status,
    DateTime? submittedAt,
    List<int>? evaluationIds,
  }) {
    return MemberEvaluation(
      scores: scores ?? this.scores,
      status: status ?? this.status,
      submittedAt: submittedAt ?? this.submittedAt,
      evaluationIds: evaluationIds ?? this.evaluationIds,
    );
  }

  Map<String, dynamic> toJson() => {
        'scores': scores,
        'status': status.name,
        'submittedAt': submittedAt?.toIso8601String(),
        'evaluationIds': evaluationIds,
      };

  factory MemberEvaluation.fromJson(Map<String, dynamic> json) {
    final rawScores = json['scores'] as Map<String, dynamic>;
    final rawIds = json['evaluationIds'] as List?;
    return MemberEvaluation(
      scores: rawScores.map((k, v) => MapEntry(k, v == null ? null : (v as num).toDouble())),
      status: MemberEvaluationStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => MemberEvaluationStatus.notStarted,
      ),
      submittedAt: json['submittedAt'] != null ? DateTime.parse(json['submittedAt']) : null,
      evaluationIds: rawIds == null ? const [] : rawIds.map((e) => e as int).toList(),
    );
  }
}

class ProjectMember {
  final int userId;
  final String name;
  final String studentId;

  const ProjectMember({
    required this.userId,
    required this.name,
    required this.studentId,
  });

  factory ProjectMember.fromJson(Map<String, dynamic> json) {
    return ProjectMember(
      userId: json['user_id'],
      name: json['name'],
      studentId: json['cats_username'],
    );
  }
}

/// Proje seviyesinde genel durum (home ekranında kullanılır)
enum ProjectOverallStatus {
  notStarted,   // Hiçbir üyeye dokunulmamış
  inProgress,   // Bazı üyeler draft veya submitted, ama hepsi değil
  allSubmitted, // Tüm üyeler submit edilmiş
}

class CapstoneProject {
  final String id;
  final String title;
  final String description;
  final String advisor;
  final DateTime examDateTime;
  final List<ProjectMember> members;

  /// Bu jüri için her üyenin değerlendirme durumu.
  /// Anahtar: member.studentId (cats_username).
  /// Runtime'da doldurulur (SharedPreferences + backend).
  final Map<String, MemberEvaluation> memberEvaluations;

  const CapstoneProject({
    required this.id,
    required this.title,
    required this.description,
    required this.advisor,
    required this.examDateTime,
    required this.members,
    this.memberEvaluations = const {},
  });

  int get submittedCount => memberEvaluations.values
      .where((e) => e.status == MemberEvaluationStatus.submitted)
      .length;

  int get inProgressCount => memberEvaluations.values
      .where((e) => e.status == MemberEvaluationStatus.inProgress)
      .length;

  ProjectOverallStatus get overallStatus {
    if (submittedCount == members.length) return ProjectOverallStatus.allSubmitted;
    if (submittedCount == 0 && inProgressCount == 0) return ProjectOverallStatus.notStarted;
    return ProjectOverallStatus.inProgress;
  }

  bool get isFullySubmitted => submittedCount == members.length;

  factory CapstoneProject.fromJson(Map<String, dynamic> json) {
    final members = (json['members'] as List)
        .map((m) => ProjectMember.fromJson(m))
        .toList();
    return CapstoneProject(
      id: json['project_id'].toString(),
      title: json['project_name'],
      description: json['description'] ?? '',
      advisor: json['advisor'] ?? 'N/A',
      examDateTime: DateTime.parse(json['exam_datetime']),
      members: members,
    );
  }

  CapstoneProject copyWith({Map<String, MemberEvaluation>? memberEvaluations}) {
    return CapstoneProject(
      id: id,
      title: title,
      description: description,
      advisor: advisor,
      examDateTime: examDateTime,
      members: members,
      memberEvaluations: memberEvaluations ?? this.memberEvaluations,
    );
  }
}