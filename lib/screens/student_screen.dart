import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http_parser/http_parser.dart';
import 'package:capstone_evaluationapp/config.dart';

class StudentScreen extends StatefulWidget {
  const StudentScreen({super.key});

  @override
  State<StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends State<StudentScreen> {
  static const Color ikuRed = Color(0xFFD31018);
  static const Color ikuGrey = Color(0xFF4A4A49);
  static const Color bgColor = Color(0xFFF5F5F7);

  Map<String, dynamic>? _user;
  Map<String, dynamic>? _project;
  double? _finalScore;
  bool _isLoading = true;

  // Tez yükleme state
  List<dynamic> _reports = [];
  bool _isUploading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map<String, dynamic>) {
      _user = args;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    if (_user == null) return;
    setState(() => _isLoading = true);
    try {
      final studentId = _user!['user_id'];

      final projectRes = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/student/$studentId/project'),
      );
      final resultRes = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/student/$studentId/result'),
      );

      if (projectRes.statusCode == 200) {
        final project = jsonDecode(projectRes.body);
        setState(() => _project = project);

        // Raporları da çek
        await _loadReports(project['project_id']);
      }

      if (resultRes.statusCode == 200) {
        final result = jsonDecode(resultRes.body);
        setState(() => _finalScore = result['score']?.toDouble());
      }
    } catch (e) {
      // hata
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadReports(int projectId) async {
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/reports/$projectId'),
      );
      if (res.statusCode == 200) {
        setState(() => _reports = jsonDecode(res.body));
      }
    } catch (_) {}
  }

    Future<void> _pickAndUpload() async {
      if (_project == null) return;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,  // ← path yerine bytes kullan
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      setState(() => _isUploading = true);

      try {
        final studentId = _user!['user_id'];
        final projectId = _project!['project_id'];

        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}/api/reports/$projectId'),
        );
        request.fields['student_id'] = studentId.toString();
        request.files.add(
          http.MultipartFile.fromBytes(
            'report',
            file.bytes!,
            filename: file.name,
            contentType: MediaType('application', 'pdf'),
          ),
        );

        final response = await request.send();

        if (response.statusCode == 201) {
          await _loadReports(projectId);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Thesis uploaded successfully.'),
              backgroundColor: Color(0xFF27AE60),
            ),
          );
        } else {
          final respBody = await response.stream.bytesToString();
          debugPrint('Upload failed: ${response.statusCode} - $respBody');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload failed. Please try again.'),
              backgroundColor: Color(0xFFD31018),
            ),
          );
        }
      } catch (e) {
        debugPrint('Upload error: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Upload failed. Please try again.'),
            backgroundColor: Color(0xFFD31018),
          ),
        );
      } finally {
        setState(() => _isUploading = false);
      }
    }
    Future<void> _openReport(String filePath) async {
      final url = Uri.parse('${AppConfig.baseUrl}/$filePath');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: ikuRed))
          : _buildBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final name = _user?['name'] ?? 'Student';
    final initials =
        name.toString().split(' ').map((e) => e[0]).take(2).join();
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.white,
      automaticallyImplyLeading: false,
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
          Text(
            name,
            style: const TextStyle(
              color: ikuGrey,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).pushReplacementNamed('/login');
          },
          icon: const Icon(Icons.logout, color: ikuRed, size: 18),
          label: const Text('Log Out',
              style: TextStyle(color: ikuRed, fontSize: 13)),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.grey.shade200),
      ),
    );
  }

  Widget _buildBody() {
    if (_project == null) {
      return const Center(child: Text('No project found.'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScoreCard(),
          const SizedBox(height: 20),
          _buildProjectCard(),
          const SizedBox(height: 20),
          _buildThesisCard(),
        ],
      ),
    );
  }

  Widget _buildScoreCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ikuRed,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: ikuRed.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'FINAL SCORE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          _finalScore == null
              ? const Text(
                  'Not evaluated yet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : Text(
                  '${_finalScore!.toStringAsFixed(1)} / 100',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildProjectCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          const Text(
            'MY PROJECT',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: ikuGrey,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _project!['project_name'],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ikuGrey,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _project!['description'] ?? '',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.school_outlined,
                  size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text(
                'Advisor: ',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _project!['advisor'] ?? 'N/A',
                style: const TextStyle(
                  fontSize: 13,
                  color: ikuGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThesisCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'THESIS / REPORT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: ikuGrey,
                  letterSpacing: 0.8,
                ),
              ),
              GestureDetector(
                onTap: _isUploading ? null : _pickAndUpload,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: ikuRed.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              color: ikuRed, strokeWidth: 2),
                        )
                      : const Row(
                          children: [
                            Icon(Icons.upload_file_outlined,
                                color: ikuRed, size: 14),
                            SizedBox(width: 4),
                            Text('Upload PDF',
                                style: TextStyle(
                                    color: ikuRed,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_reports.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.grey.shade200, style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  Icon(Icons.description_outlined,
                      size: 36, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text(
                    'No thesis uploaded yet',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upload your thesis as a PDF file',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
                ],
              ),
            )
          else
            ..._reports.map((report) => _buildReportTile(report)),
        ],
      ),
    );
  }

  Widget _buildReportTile(dynamic report) {
    final filename = report['filename'] ?? 'thesis.pdf';
    final uploadedAt = report['uploaded_at'] != null
        ? DateTime.parse(report['uploaded_at']).toLocal()
        : null;
    final fileSizeKb = report['file_size'] != null
        ? (report['file_size'] as int) ~/ 1024
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ikuRed.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.picture_as_pdf_outlined,
                color: ikuRed, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  filename,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ikuGrey),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (fileSizeKb != null) '${fileSizeKb} KB',
                    if (uploadedAt != null) _formatDate(uploadedAt),
                  ].join('  •  '),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _openReport(report['file_path']),
            icon: const Icon(Icons.open_in_new_outlined,
                color: ikuRed, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month]} ${dt.year}';
  }
}