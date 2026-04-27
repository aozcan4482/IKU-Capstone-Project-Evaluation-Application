// lib/widgets/report_version_card.dart
import 'package:flutter/material.dart';
import '../models/report_version.dart';
import '../services/report_export_service.dart';

class ReportVersionCard extends StatelessWidget {
  final ReportVersion report;
  final VoidCallback? onTap;
  final VoidCallback? onCompare;
  
  const ReportVersionCard({
    Key? key,
    required this.report,
    this.onTap,
    this.onCompare,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: report.getStatusColor().withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      report.getStatusText(),
                      style: TextStyle(
                        color: report.getStatusColor(),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      report.reportType.toString().split('.').last,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (report.isFinalApproved)
                    const Icon(Icons.verified, color: Colors.green, size: 20),
                  if (report.canBeDownloaded)
                    IconButton(
                      icon: const Icon(Icons.download, size: 20),
                      onPressed: () => _downloadReport(context),
                      tooltip: 'Download',
                    ),
                  if (onCompare != null)
                    IconButton(
                      icon: const Icon(Icons.compare_arrows, size: 20),
                      onPressed: onCompare,
                      tooltip: 'Compare',
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Version ${report.versionNumber}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Created: ${_formatDate(report.createdAt)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              Text(
                'By: ${report.createdByName}',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              if (report.modifiedAt != null)
                Text(
                  'Modified: ${_formatDate(report.modifiedAt!)}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              if (report.approvedAt != null)
                Text(
                  'Approved: ${_formatDate(report.approvedAt!)}',
                  style: const TextStyle(color: Colors.green, fontSize: 12),
                ),
              const SizedBox(height: 8),
              if (report.changes.isNotEmpty)
                Wrap(
                  children: report.changes.map((change) => Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 4),
                    child: Chip(
                      label: Text(change, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.grey[200],
                    ),
                  )).toList(),
                ),
              if (report.juryComments != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Jury Comments:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(report.juryComments!, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  
  Future<void> _downloadReport(BuildContext context) async {
    try {
      final file = await ReportExportService.exportReport(report);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report saved to: ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}