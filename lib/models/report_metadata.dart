// lib/models/report_metadata.dart
class ReportMetadata {
  final String reportId;
  final Map<String, dynamic> customFields;
  final Map<String, dynamic> evaluationScores;
  final Map<String, String> attachments;
  final List<String> keywords;
  final String? abstract;
  final String? conclusion;
  final Map<String, dynamic> versionHistory;

  ReportMetadata({
    required this.reportId,
    required this.customFields,
    required this.evaluationScores,
    required this.attachments,
    required this.keywords,
    this.abstract,
    this.conclusion,
    required this.versionHistory,
  });

  Map<String, dynamic> toJson() => {
    'reportId': reportId,
    'customFields': customFields,
    'evaluationScores': evaluationScores,
    'attachments': attachments,
    'keywords': keywords,
    'abstract': abstract,
    'conclusion': conclusion,
    'versionHistory': versionHistory,
  };

  factory ReportMetadata.fromJson(Map<String, dynamic> json) => ReportMetadata(
    reportId: json['reportId'],
    customFields: json['customFields'],
    evaluationScores: json['evaluationScores'],
    attachments: Map<String, String>.from(json['attachments']),
    keywords: List<String>.from(json['keywords']),
    abstract: json['abstract'],
    conclusion: json['conclusion'],
    versionHistory: json['versionHistory'],
  );
}