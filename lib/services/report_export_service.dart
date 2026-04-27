// lib/services/report_export_service.dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/report_version.dart';

class ReportExportService {
  static Future<File> exportReport(ReportVersion report) async {
    final File sourceFile = File(report.filePath);
    if (!await sourceFile.exists()) {
      throw Exception('Report file not found: ${report.filePath}');
    }
    
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final Directory exportDir = Directory('${appDocDir.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    
    final String exportFileName = report.getFormattedFileName();
    final File exportFile = File('${exportDir.path}/$exportFileName');
    await sourceFile.copy(exportFile.path);
    
    return exportFile;
  }
  
  static Future<File> exportProjectReportPackage(String projectId, List<ReportVersion> reports) async {
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    final String tempDirPath = '${appDocDir.path}/temp_${DateTime.now().millisecondsSinceEpoch}';
    final Directory tempDir = Directory(tempDirPath);
    await tempDir.create(recursive: true);
    
    // Copy all report files to temp directory
    for (var report in reports) {
      final File sourceFile = File(report.filePath);
      if (await sourceFile.exists()) {
        final String destPath = '${tempDir.path}/${report.getFormattedFileName()}';
        await sourceFile.copy(destPath);
      }
    }
    
    // Create a simple text file listing all reports
    final File manifestFile = File('${tempDir.path}/MANIFEST.txt');
    String manifestContent = 'Project Report Package\n';
    manifestContent += 'Exported: ${DateTime.now()}\n';
    manifestContent += 'Total Reports: ${reports.length}\n\n';
    for (var report in reports) {
      manifestContent += 'Version ${report.versionNumber}: ${report.getFormattedFileName()} (${report.getStatusText()})\n';
    }
    await manifestFile.writeAsString(manifestContent);
    
    // Create exports directory
    final Directory exportsDir = Directory('${appDocDir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    
    // Create a simple zip alternative (just copy the folder)
    final String sanitizedName = _sanitizeFileName(projectId);
    final String exportFolderPath = '${exportsDir.path}/${sanitizedName}_REPORT_PACKAGE_${DateTime.now().millisecondsSinceEpoch}';
    final Directory exportFolder = Directory(exportFolderPath);
    await exportFolder.create();
    
    // Copy all files from temp to export folder
    await _copyDirectory(tempDir, exportFolder);
    
    // Cleanup temp directory
    await tempDir.delete(recursive: true);
    
    return File(exportFolderPath);
  }
  
  static Future<File> exportApprovedReportWithCertificate(ReportVersion report, Map<String, String> signatures) async {
    final File exportedReport = await exportReport(report);
    final Directory appDocDir = await getApplicationDocumentsDirectory();
    
    final Directory exportsDir = Directory('${appDocDir.path}/exports');
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    
    final String certFileName = report.getFormattedFileName().replaceAll('.pdf', '_certificate.txt');
    final File certFile = File('${exportsDir.path}/$certFileName');
    
    String certificateContent = 'CERTIFICATE OF APPROVAL\n';
    certificateContent += '=' * 50 + '\n';
    certificateContent += 'Report ID: ${report.id}\n';
    certificateContent += 'Project: ${report.projectName}\n';
    certificateContent += 'Version: ${report.versionNumber}\n';
    certificateContent += 'Approval Date: ${report.approvedAt?.toIso8601String() ?? DateTime.now().toIso8601String()}\n';
    certificateContent += 'Status: ${report.getStatusText()}\n\n';
    certificateContent += 'Signatures:\n';
    signatures.forEach((key, value) {
      certificateContent += '  $key: $value\n';
    });
    certificateContent += '\n';
    certificateContent += 'This document certifies that the above report has been officially approved.\n';
    certificateContent += '=' * 50 + '\n';
    
    await certFile.writeAsString(certificateContent);
    
    return exportedReport;
  }
  
  static Future<void> _copyDirectory(Directory source, Directory destination) async {
    final List<FileSystemEntity> files = await source.list().toList();
    for (var entity in files) {
      if (entity is File) {
        final String fileName = entity.path.split('/').last;
        await entity.copy('${destination.path}/$fileName');
      }
    }
  }
  
  static String _sanitizeFileName(String name) {
    String sanitized = name.toUpperCase();
    sanitized = sanitized.replaceAll(RegExp(r'[^A-Z0-9]'), '_');
    return sanitized;
  }
}