// lib/services/report_version_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:math';
import '../models/report_version.dart';

class ReportVersionService {
  static final ReportVersionService _instance = ReportVersionService._internal();
  factory ReportVersionService() => _instance;
  ReportVersionService._internal();

  List<ReportVersion> _reports = [];

  Future<List<ReportVersion>> getProjectReports(String projectId) async {
    await _loadReports();
    final filtered = _reports.where((r) => r.projectId == projectId).toList();
    filtered.sort((a, b) => b.versionNumber.compareTo(a.versionNumber));
    return filtered;
  }

  Future<ReportVersion?> getLatestReportByType(String projectId, ReportType type) async {
    final reports = await getProjectReports(projectId);
    for (var report in reports) {
      if (report.reportType == type) {
        return report;
      }
    }
    return null;
  }

  Future<List<ReportVersion>> getReportHistory({
    String? projectId,
    String? createdBy,
    ReportType? reportType,
    ReportStatus? status,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    await _loadReports();
    var filtered = List<ReportVersion>.from(_reports);
    
    if (projectId != null) {
      filtered = filtered.where((r) => r.projectId == projectId).toList();
    }
    if (createdBy != null) {
      filtered = filtered.where((r) => r.createdBy == createdBy).toList();
    }
    if (reportType != null) {
      filtered = filtered.where((r) => r.reportType == reportType).toList();
    }
    if (status != null) {
      filtered = filtered.where((r) => r.status == status).toList();
    }
    if (fromDate != null) {
      filtered = filtered.where((r) => r.createdAt.isAfter(fromDate)).toList();
    }
    if (toDate != null) {
      filtered = filtered.where((r) => r.createdAt.isBefore(toDate)).toList();
    }
    
    filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return filtered;
  }

  Future<ReportVersion> createReportVersion({
    required String projectId,
    required String projectName,
    required ReportType reportType,
    required String createdBy,
    required String createdByName,
    required File reportFile,
    required List<String> changes,
    required Map<String, dynamic> metadata,
    List<String> reviewers = const [],
  }) async {
    await _loadReports();
    
    // Calculate version number
    int versionNumber = 1;
    final existingVersions = _reports.where((r) => r.projectId == projectId);
    if (existingVersions.isNotEmpty) {
      int maxVersion = 0;
      for (var r in existingVersions) {
        if (r.versionNumber > maxVersion) {
          maxVersion = r.versionNumber;
        }
      }
      versionNumber = maxVersion + 1;
    }

    // Calculate simple file hash (avoid crypto issues)
    final fileBytes = await reportFile.readAsBytes();
    final String fileHash = _calculateSimpleHash(fileBytes);
    final int fileSize = await reportFile.length();

    final String id = DateTime.now().millisecondsSinceEpoch.toString();
    final DateTime now = DateTime.now();
    
    // Create temporary report to generate filename
    final tempReport = ReportVersion(
      id: id,
      projectId: projectId,
      projectName: projectName,
      versionNumber: versionNumber,
      reportType: reportType,
      status: ReportStatus.draft,
      createdAt: now,
      createdBy: createdBy,
      createdByName: createdByName,
      filePath: reportFile.path,
      fileName: '',
      fileHash: fileHash,
      fileSize: fileSize,
      metadata: metadata,
      changes: changes,
      reviewers: reviewers,
    );

    final String fileName = tempReport.getFormattedFileName();
    
    // Create directory
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory reportsDir = Directory('${appDocDir.path}/reports/$projectId');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    
    final String newFilePath = '${reportsDir.path}/$fileName';
    await reportFile.copy(newFilePath);
    
    final savedReportVersion = ReportVersion(
      id: id,
      projectId: projectId,
      projectName: projectName,
      versionNumber: versionNumber,
      reportType: reportType,
      status: ReportStatus.draft,
      createdAt: now,
      createdBy: createdBy,
      createdByName: createdByName,
      filePath: newFilePath,
      fileName: fileName,
      fileHash: fileHash,
      fileSize: fileSize,
      metadata: metadata,
      changes: changes,
      reviewers: reviewers,
    );

    _reports.add(savedReportVersion);
    await _saveReports();
    
    return savedReportVersion;
  }

  Future<void> submitForReview(String reportId) async {
    final index = _findReportIndex(reportId);
    if (index != -1) {
      final report = _reports[index];
      final updatedReport = ReportVersion(
        id: report.id,
        projectId: report.projectId,
        projectName: report.projectName,
        versionNumber: report.versionNumber,
        reportType: report.reportType,
        status: ReportStatus.submitted,
        createdAt: report.createdAt,
        modifiedAt: DateTime.now(),
        approvedAt: report.approvedAt,
        createdBy: report.createdBy,
        createdByName: report.createdByName,
        filePath: report.filePath,
        fileName: report.fileName,
        fileHash: report.fileHash,
        fileSize: report.fileSize,
        metadata: report.metadata,
        changes: report.changes,
        juryComments: report.juryComments,
        reviewers: report.reviewers,
        signatures: report.signatures,
      );
      _reports[index] = updatedReport;
      await _saveReports();
    }
  }

  Future<void> approveReport(String reportId, String juryComment, Map<String, String> signatures) async {
    final index = _findReportIndex(reportId);
    if (index != -1) {
      final report = _reports[index];
      
      final ReportType newReportType = report.reportType == ReportType.final_ 
          ? ReportType.approved_final 
          : report.reportType;
      
      final updatedReport = ReportVersion(
        id: report.id,
        projectId: report.projectId,
        projectName: report.projectName,
        versionNumber: report.versionNumber,
        reportType: newReportType,
        status: ReportStatus.approved,
        createdAt: report.createdAt,
        modifiedAt: DateTime.now(),
        approvedAt: DateTime.now(),
        createdBy: report.createdBy,
        createdByName: report.createdByName,
        filePath: report.filePath,
        fileName: report.fileName,
        fileHash: report.fileHash,
        fileSize: report.fileSize,
        metadata: report.metadata,
        changes: report.changes,
        juryComments: juryComment,
        reviewers: report.reviewers,
        signatures: signatures,
      );
      _reports[index] = updatedReport;
      await _saveReports();
      
      await _archivePreviousApprovedVersion(report.projectId, reportId);
    }
  }

  Future<void> requestRevisions(String reportId, String comments) async {
    final index = _findReportIndex(reportId);
    if (index != -1) {
      final report = _reports[index];
      final updatedReport = ReportVersion(
        id: report.id,
        projectId: report.projectId,
        projectName: report.projectName,
        versionNumber: report.versionNumber,
        reportType: report.reportType,
        status: ReportStatus.revisions_needed,
        createdAt: report.createdAt,
        modifiedAt: DateTime.now(),
        approvedAt: report.approvedAt,
        createdBy: report.createdBy,
        createdByName: report.createdByName,
        filePath: report.filePath,
        fileName: report.fileName,
        fileHash: report.fileHash,
        fileSize: report.fileSize,
        metadata: report.metadata,
        changes: report.changes,
        juryComments: comments,
        reviewers: report.reviewers,
        signatures: report.signatures,
      );
      _reports[index] = updatedReport;
      await _saveReports();
    }
  }

  Future<void> _archivePreviousApprovedVersion(String projectId, String newApprovedId) async {
    final projectReports = await getProjectReports(projectId);
    for (var report in projectReports) {
      if (report.id != newApprovedId && 
          (report.reportType == ReportType.approved_final || report.status == ReportStatus.approved)) {
        final index = _findReportIndex(report.id);
        if (index != -1) {
          final archivedReport = ReportVersion(
            id: report.id,
            projectId: report.projectId,
            projectName: report.projectName,
            versionNumber: report.versionNumber,
            reportType: ReportType.archive,
            status: ReportStatus.archived,
            createdAt: report.createdAt,
            modifiedAt: DateTime.now(),
            approvedAt: report.approvedAt,
            createdBy: report.createdBy,
            createdByName: report.createdByName,
            filePath: report.filePath,
            fileName: report.fileName,
            fileHash: report.fileHash,
            fileSize: report.fileSize,
            metadata: report.metadata,
            changes: report.changes,
            juryComments: report.juryComments,
            reviewers: report.reviewers,
            signatures: report.signatures,
          );
          _reports[index] = archivedReport;
        }
      }
    }
    await _saveReports();
  }

  Future<Map<String, dynamic>> compareVersions(String reportId1, String reportId2) async {
    ReportVersion? report1;
    ReportVersion? report2;
    
    for (var r in _reports) {
      if (r.id == reportId1) report1 = r;
      if (r.id == reportId2) report2 = r;
    }
    
    if (report1 == null || report2 == null) {
      throw Exception('Report not found');
    }
    
    return {
      'version1': {
        'version': report1.versionNumber,
        'createdAt': report1.createdAt,
        'size': report1.fileSize,
        'changes': report1.changes,
      },
      'version2': {
        'version': report2.versionNumber,
        'createdAt': report2.createdAt,
        'size': report2.fileSize,
        'changes': report2.changes,
      },
      'difference': {
        'versionGap': (report2.versionNumber - report1.versionNumber).abs(),
        'timeGap': report2.createdAt.difference(report1.createdAt).inDays,
      },
    };
  }

  Future<List<Map<String, dynamic>>> getVersionTimeline(String projectId) async {
    final reports = await getProjectReports(projectId);
    List<Map<String, dynamic>> timeline = [];
    for (var report in reports) {
      timeline.add({
        'version': report.versionNumber,
        'type': report.reportType.toString(),
        'status': report.status.toString(),
        'date': report.createdAt,
        'author': report.createdByName,
        'isApproved': report.isApproved,
        'isFinal': report.isFinalApproved,
      });
    }
    return timeline;
  }

  int _findReportIndex(String reportId) {
    for (int i = 0; i < _reports.length; i++) {
      if (_reports[i].id == reportId) {
        return i;
      }
    }
    return -1;
  }

  String _calculateSimpleHash(List<int> bytes) {
    // Simple hash without crypto package
    int hash = 0;
    for (int i = 0; i < bytes.length && i < 1000; i++) {
      hash = (hash * 31 + bytes[i]) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  Future<void> _loadReports() async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final File file = File('${appDocDir.path}/report_versions.json');
      if (await file.exists()) {
        final String contents = await file.readAsString();
        final List<dynamic> jsonList = jsonDecode(contents);
        _reports = [];
        for (var json in jsonList) {
          _reports.add(ReportVersion.fromJson(json));
        }
      }
    } catch (e) {
      print('Error loading reports: $e');
      _reports = [];
    }
  }

  Future<void> _saveReports() async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final File file = File('${appDocDir.path}/report_versions.json');
      List<Map<String, dynamic>> jsonList = [];
      for (var report in _reports) {
        jsonList.add(report.toJson());
      }
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Error saving reports: $e');
    }
  }
}