// lib/screens/report_history_screen.dart
import 'package:flutter/material.dart';
import '../services/report_version_service.dart';
import '../models/report_version.dart';
import '../widgets/report_version_card.dart';
import '../services/report_export_service.dart';

class ReportHistoryScreen extends StatefulWidget {
  final String? projectId;
  final String? juryId;
  
  const ReportHistoryScreen({Key? key, this.projectId, this.juryId}) : super(key: key);

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  final ReportVersionService _service = ReportVersionService();
  List<ReportVersion> _reports = [];
  bool _isLoading = true;
  String _filterType = 'all';
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _isLoading = true);
    
    if (widget.projectId != null) {
      _reports = await _service.getProjectReports(widget.projectId!);
    } else if (widget.juryId != null) {
      final allReports = await _service.getReportHistory();
      _reports = allReports.where((r) => r.reviewers.contains(widget.juryId)).toList();
    } else {
      _reports = await _service.getReportHistory();
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _showFilterDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReports,
          ),
          if (widget.projectId != null)
            IconButton(
              icon: const Icon(Icons.archive),
              onPressed: () => _exportAllReports(),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildReportList(),
    );
  }

  Widget _buildReportList() {
    var filteredReports = _reports;
    
    if (_filterType != 'all') {
      filteredReports = filteredReports.where((r) => 
        r.reportType.toString().toLowerCase().contains(_filterType.toLowerCase())).toList();
    }
    
    if (_filterStatus != 'all') {
      filteredReports = filteredReports.where((r) => 
        r.getStatusText().toLowerCase().contains(_filterStatus.toLowerCase())).toList();
    }
    
    if (filteredReports.isEmpty) {
      return const Center(child: Text('No reports found'));
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredReports.length,
      itemBuilder: (context, index) {
        final report = filteredReports[index];
        return ReportVersionCard(
          report: report,
          onCompare: () => _showComparisonDialog(report),
        );
      },
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Reports'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _filterType,
              decoration: const InputDecoration(labelText: 'Report Type'),
              items: ['all', 'interim', 'preliminary', 'final', 'approved_final']
                  .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                  .toList(),
              onChanged: (value) {
                setState(() => _filterType = value!);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _filterStatus,
              decoration: const InputDecoration(labelText: 'Status'),
              items: ['all', 'draft', 'submitted', 'under review', 'approved', 'rejected']
                  .map((status) => DropdownMenuItem(value: status, child: Text(status)))
                  .toList(),
              onChanged: (value) {
                setState(() => _filterStatus = value!);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showComparisonDialog(ReportVersion report) async {
    final otherReports = await _service.getProjectReports(report.projectId);
    otherReports.removeWhere((r) => r.id == report.id);
    
    if (otherReports.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other versions to compare')),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Compare with version'),
        content: SizedBox(
          width: double.maxFinite,
          child: DropdownButton<ReportVersion>(
            isExpanded: true,
            hint: const Text('Select version'),
            items: otherReports.map((r) => DropdownMenuItem(
              value: r,
              child: Text('Version ${r.versionNumber} - ${_formatDate(r.createdAt)}'),
            )).toList(),
            onChanged: (selected) async {
              Navigator.pop(context);
              final comparison = await _service.compareVersions(report.id, selected!.id);
              _showComparisonResult(comparison);
            },
          ),
        ),
      ),
    );
  }

  void _showComparisonResult(Map<String, dynamic> comparison) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Version Comparison'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version ${comparison['version1']['version']} vs Version ${comparison['version2']['version']}'),
              const Divider(),
              Text('Version Gap: ${comparison['difference']['versionGap']}'),
              Text('Time Gap: ${comparison['difference']['timeGap']} days'),
              const SizedBox(height: 8),
              const Text('Changes in newer version:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ...(comparison['version2']['changes'] as List).map((change) => 
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 4),
                  child: Text('• $change'),
                )
              ).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAllReports() async {
    if (widget.projectId == null) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );
    
    try {
      final file = await ReportExportService.exportProjectReportPackage(widget.projectId!, _reports);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Package exported to: ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error exporting: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}