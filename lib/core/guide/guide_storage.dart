import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/services/local_cache_service.dart';
import 'guide_models.dart';

/// Local persistence for guide state.
///
/// Guide state is deliberately stored as a namespaced JSON string in the
/// existing Hive-backed LocalCacheService. This keeps guide data separate from
/// offers, favorites, and config, and lets us discard a corrupt guide value
/// without clearing the rest of the app cache.
class GuideStorage {
  GuideStorage({LocalCacheService? cache}) : _cache = cache ?? LocalCacheService();

  static const String contentVersion = 'guide.v1';
  final LocalCacheService _cache;

  /// Increments whenever the help-window state changes, so the temporary `?`
  /// affordance can re-read and show/hide itself without a full rebuild.
  static final ValueNotifier<int> helpRevision = ValueNotifier<int>(0);

  String runKey({required GuideScope scope, String uid = ''}) {
    final normalizedUid = uid.trim();
    if (scope == GuideScope.visitor) return '$contentVersion.visitor.run';
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'A registered guide needs a uid');
    }
    return '$contentVersion.${scope.key}.$normalizedUid.run';
  }

  String helpUntilKey({required GuideScope scope, String uid = ''}) {
    final normalizedUid = uid.trim();
    if (scope == GuideScope.visitor) {
      return '$contentVersion.visitor.help_until';
    }
    if (normalizedUid.isEmpty) {
      throw ArgumentError.value(uid, 'uid', 'A registered guide needs a uid');
    }
    return '$contentVersion.${scope.key}.$normalizedUid.help_until';
  }

  GuideRunState? readRun({required GuideScope scope, String uid = ''}) {
    try {
      final raw = _cache.get(runKey(scope: scope, uid: uid));
      if (raw is! String || raw.isEmpty) return null;
      return GuideRunState.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (_) {
      // Remove only the damaged guide record; never clear the shared cache.
      _deleteQuietly(scope: scope, uid: uid);
      return null;
    }
  }

  Future<bool> saveRun(GuideRunState state) async {
    if (!_cache.isReady) return false;
    try {
      await _cache.put(
        runKey(scope: state.scope, uid: state.uid),
        state.encode(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> deleteRun({required GuideScope scope, String uid = ''}) async {
    try {
      await _cache.remove(runKey(scope: scope, uid: uid));
    } catch (_) {
      // Guide persistence must never block the application.
    }
  }

  DateTime? readHelpUntil({required GuideScope scope, String uid = ''}) {
    try {
      final raw = _cache.get(helpUntilKey(scope: scope, uid: uid));
      if (raw is! String || raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toLocal();
    } catch (_) {
      _deleteHelpQuietly(scope: scope, uid: uid);
      return null;
    }
  }

  Future<bool> saveHelpUntil({
    required GuideScope scope,
    String uid = '',
    required DateTime until,
  }) async {
    if (!_cache.isReady) return false;
    try {
      await _cache.put(
        helpUntilKey(scope: scope, uid: uid),
        until.toUtc().toIso8601String(),
      );
      helpRevision.value++;
      return true;
    } catch (_) {
      return false;
    }
  }

  bool isHelpActive({required GuideScope scope, String uid = ''}) {
    final until = readHelpUntil(scope: scope, uid: uid);
    return until != null && until.isAfter(DateTime.now());
  }

  Future<void> _deleteQuietly({required GuideScope scope, String uid = ''}) async {
    try {
      await _cache.remove(runKey(scope: scope, uid: uid));
    } catch (_) {}
  }

  Future<void> _deleteHelpQuietly({required GuideScope scope, String uid = ''}) async {
    try {
      await _cache.remove(helpUntilKey(scope: scope, uid: uid));
      helpRevision.value++;
    } catch (_) {}
  }
}
