// lib/models/report_version.dart
enum ReportType {
  interim,           // Interim report
  preliminary,       // Preliminary results
  final_,            // Final results (before approval)
  approved_final,    // Approved final version
  archive            // Archived version
}

enum ReportStatus {
  draft,             // Work in progress
  submitted,         // Submitted for review
  under_review,      // Being reviewed by jury
  revisions_needed,  // Changes required
  approved,          // Approved by jury
  rejected,          // Rejected by jury
  archived           // Archived version
}

class ReportVersion {
  final String id;
  final String projectId;
  final String projectName;
  final int versionNumber;
  final ReportType reportType;
  final ReportStatus status;
  final DateTime createdAt;
  final DateTime? modifiedAt;
  final DateTime? approvedAt;
  final String createdBy; // User ID
  final String createdByName;
  final String filePath;
  final String fileName;
  final String fileHash; // For integrity check
  final int fileSize;
  final Map<String, dynamic> metadata;
  final List<String> changes; // Description of changes from previous version
  final String? juryComments;
  final List<String> reviewers; // Jury member IDs
  final Map<String, String>? signatures; // Digital signatures from jury

  ReportVersion({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.versionNumber,
    required this.reportType,
    required this.status,
    required this.createdAt,
    this.modifiedAt,
    this.approvedAt,
    required this.createdBy,
    required this.createdByName,
    required this.filePath,
    required this.fileName,
    required this.fileHash,
    required this.fileSize,
    required this.metadata,
    required this.changes,
    this.juryComments,
    required this.reviewers,
    this.signatures,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'projectId': projectId,
    'projectName': projectName,
    'versionNumber': versionNumber,
    'reportType': reportType.toString(),
    'status': status.toString(),
    'createdAt': createdAt.toIso8601String(),
    'modifiedAt': modifiedAt?.toIso8601String(),
    'approvedAt': approvedAt?.toIso8601String(),
    'createdBy': createdBy,
    'createdByName': createdByName,
    'filePath': filePath,
    'fileName': fileName,
    'fileHash': fileHash,
    'fileSize': fileSize,
    'metadata': metadata,
    'changes': changes,
    'juryComments': juryComments,
    'reviewers': reviewers,
    'signatures': signatures,
  };

  factory ReportVersion.fromJson(Map<String, dynamic> json) => ReportVersion(
    id: json['id'],
    projectId: json['projectId'],
    projectName: json['projectName'],
    versionNumber: json['versionNumber'],
    reportType: _parseReportType(json['reportType']),
    status: _parseReportStatus(json['status']),
    createdAt: DateTime.parse(json['createdAt']),
    modifiedAt: json['modifiedAt'] != null ? DateTime.parse(json['modifiedAt']) : null,
    approvedAt: json['approvedAt'] != null ? DateTime.parse(json['approvedAt']) : null,
    createdBy: json['createdBy'],
    createdByName: json['createdByName'],
    filePath: json['filePath'],
    fileName: json['fileName'],
    fileHash: json['fileHash'],
    fileSize: json['fileSize'],
    metadata: json['metadata'],
    changes: List<String>.from(json['changes']),
    juryComments: json['juryComments'],
    reviewers: List<String>.from(json['reviewers']),
    signatures: json['signatures'] != null ? Map<String, String>.from(json['signatures']) : null,
  );

  static ReportType _parseReportType(String type) {
    switch (type) {
      case 'ReportType.interim': return ReportType.interim;
      case 'ReportType.preliminary': return ReportType.preliminary;
      case 'ReportType.final_': return ReportType.final_;
      case 'ReportType.approved_final': return ReportType.approved_final;
      case 'ReportType.archive': return ReportType.archive;
      default: return ReportType.interim;
    }
  }

  static ReportStatus _parseReportStatus(String status) {
    switch (status) {
      case 'ReportStatus.draft': return ReportStatus.draft;
      case 'ReportStatus.submitted': return ReportStatus.submitted;
      case 'ReportStatus.under_review': return ReportStatus.under_review;
      case 'ReportStatus.revisions_needed': return ReportStatus.revisions_needed;
      case 'ReportStatus.approved': return ReportStatus.approved;
      case 'ReportStatus.rejected': return ReportStatus.rejected;
      case 'ReportStatus.archived': return ReportStatus.archived;
      default: return ReportStatus.draft;
    }
  }

  String getFormattedFileName() {
    // Standardized naming: PROJECTNAME_TYPE_VV_YYYYMMDD
    String typeCode = '';
    switch (reportType) {
      case ReportType.interim:
        typeCode = 'INT';
        break;
      case ReportType.preliminary:
        typeCode = 'PRE';
        break;
      case ReportType.final_:
        typeCode = 'FIN';
        break;
      case ReportType.approved_final:
        typeCode = 'APR';
        break;
      case ReportType.archive:
        typeCode = 'ARC';
        break;
    }
    
    String versionStr = 'V${versionNumber.toString().padLeft(2, '0')}';
    String dateStr = createdAt.toString().split(' ')[0].replaceAll('-', '');
    
    return '${_sanitizeFileName(projectName)}_${typeCode}_${versionStr}_${dateStr}.pdf';
  }

  String _sanitizeFileName(String name) {
    return name.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '_');
  }

  bool get isApproved => status == ReportStatus.approved;
  bool get isFinalApproved => reportType == ReportType.approved_final;
  bool get canBeDownloaded => status == ReportStatus.approved || 
                               status == ReportStatus.archived ||
                               reportType == ReportType.approved_final;
}