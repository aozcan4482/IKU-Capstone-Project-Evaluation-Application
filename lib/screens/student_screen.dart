import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  bool _isEditing = false;
  bool _isSaving = false;

  late TextEditingController _nameController;
  late TextEditingController _descController;

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
        Uri.parse('http://localhost:3000/api/student/$studentId/project'),
      );
      final resultRes = await http.get(
        Uri.parse('http://localhost:3000/api/student/$studentId/result'),
      );

      if (projectRes.statusCode == 200) {
        final project = jsonDecode(projectRes.body);
        _nameController = TextEditingController(text: project['project_name']);
        _descController = TextEditingController(text: project['description']);
        setState(() => _project = project);
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

  Future<void> _saveChanges() async {
    if (_user == null || _project == null) return;
    setState(() => _isSaving = true);
    try {
      final studentId = _user!['user_id'];
      final response = await http.put(
        Uri.parse('http://localhost:3000/api/student/$studentId/project'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'project_name': _nameController.text.trim(),
          'description': _descController.text.trim(),
        }),
      );
      if (response.statusCode == 200) {
        final updated = jsonDecode(response.body);
        setState(() {
          _project!['project_name'] = updated['project_name'];
          _project!['description'] = updated['description'];
          _isEditing = false;
        });
      }
    } catch (e) {
      // hata
    } finally {
      setState(() => _isSaving = false);
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
          // Final skor kartı
          _buildScoreCard(),
          const SizedBox(height: 20),
          // Proje bilgi kartı
          _buildProjectCard(),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              if (!_isEditing)
                GestureDetector(
                  onTap: () => setState(() => _isEditing = true),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: ikuRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.edit_outlined, color: ikuRed, size: 14),
                        SizedBox(width: 4),
                        Text('Edit',
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
          if (_isEditing) ...[
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Project Name',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Description',
                filled: true,
                fillColor: Colors.grey[50],
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _isEditing = false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: ikuGrey),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(color: ikuGrey)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveChanges,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ikuRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Save',
                            style:
                                TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ] else ...[
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
        ],
      ),
    );
  }
}