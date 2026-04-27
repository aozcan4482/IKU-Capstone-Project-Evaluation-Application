// lib/services/evaluation_storage.dart

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:capstone_evaluationapp/models/project.dart';

/// Jüri bazlı evaluation draft'larını ve submit durumlarını saklar.
/// Anahtar formatı: "eval_<juryId>_<projectId>_<studentId>"
class EvaluationStorage {
  static String _key(int juryId, String projectId, String studentId) =>
      'eval_${juryId}_${projectId}_$studentId';

  /// Bir üye için evaluation kaydet (draft veya submitted)
  static Future<void> save({
    required int juryId,
    required String projectId,
    required String studentId,
    required MemberEvaluation evaluation,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(juryId, projectId, studentId), jsonEncode(evaluation.toJson()));
  }

  /// Bir üye için evaluation'ı getir (yoksa null)
  static Future<MemberEvaluation?> load({
    required int juryId,
    required String projectId,
    required String studentId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(juryId, projectId, studentId));
    if (raw == null) return null;
    try {
      return MemberEvaluation.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  /// Bir projedeki tüm üyelerin evaluation'larını yükle.
  /// Geri dönen Map'in anahtarı: studentId
  static Future<Map<String, MemberEvaluation>> loadForProject({
    required int juryId,
    required String projectId,
    required List<ProjectMember> members,
    required List<String> criteria,
  }) async {
    final Map<String, MemberEvaluation> result = {};
    for (final m in members) {
      final stored = await load(juryId: juryId, projectId: projectId, studentId: m.studentId);
      result[m.studentId] = stored ?? MemberEvaluation.empty(criteria);
    }
    return result;
  }

  /// Submit edilmiş bir üyeyi silme (iptal / yeniden değerlendirme için)
  static Future<void> clear({
    required int juryId,
    required String projectId,
    required String studentId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(juryId, projectId, studentId));
  }
}