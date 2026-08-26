import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// خدمة التخزين المحلي (Hive) — للكاش + دعم العمل دون اتصال
///
/// تُستخدم لتخزين:
/// - إعدادات التطبيق (Config) للعمل offline
/// - كاش العروض الأخيرة
/// - المفضلة المحلية
/// - حالة المهام اليومية (Streak / المهام)
class LocalCacheService {
  LocalCacheService._internal();
  static final LocalCacheService _instance = LocalCacheService._internal();
  factory LocalCacheService() => _instance;

  static const String _boxName = 'app_cache';
  static const String _kConfig = 'config_main';
  static const String _kConfigTs = 'config_ts';
  static const String _kOffers = 'offers_cache';
  static const String _kFavorites = 'favorites';

  Box? _box;
  bool _ready = false;

  /// تهيئة Hive — تُستدعى مرة واحدة في main()
  static Future<void> initialize() async {
    try {
      await Hive.initFlutter();
      final box = await Hive.openBox(_boxName);
      _instance._box = box;
      _instance._ready = true;} catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  bool get isReady => _ready && _box != null;

  /// مُستمع حي لمفتاح المفضلة — أي كتابة عليه تُشعِر الواجهات فوراً
  /// (حل مزامنة القلب بين بطاقات القوائم وشاشة التفاصيل — 2026-07-27)
  ValueListenable<Box>? get favoritesListenable =>
      isReady ? _box!.listenable(keys: const [_kFavorites]) : null;

  // ═══════════════════════════════════════
  // Config
  // ═══════════════════════════════════════
  Future<void> saveConfig(Map<String, dynamic> config) async {
    if (!isReady) return;
    try {
      await _box!.put(_kConfig, jsonEncode(config));
      await _box!.put(_kConfigTs, DateTime.now().toIso8601String());
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  Map<String, dynamic>? getConfig() {
    if (!isReady) return null;
    try {
      final raw = _box!.get(_kConfig);
      if (raw is String && raw.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    return null;
  }

  DateTime? getConfigTimestamp() {
    if (!isReady) return null;
    final raw = _box!.get(_kConfigTs);
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  // ═══════════════════════════════════════
  // Offers cache (offline support)
  // ═══════════════════════════════════════
  Future<void> saveOffers(List<Map<String, dynamic>> offers) async {
    if (!isReady) return;
    try {
      await _box!.put(_kOffers, jsonEncode(offers));
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
  }

  List<Map<String, dynamic>> getOffers() {
    if (!isReady) return [];
    try {
      final raw = _box!.get(_kOffers);
      if (raw is String && raw.isNotEmpty) {
        return (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    return [];
  }

  // ═══════════════════════════════════════
  // Favorites (محلية)
  // ═══════════════════════════════════════
  List<String> getFavorites() {
    if (!isReady) return [];
    try {
      final raw = _box!.get(_kFavorites);
      if (raw is List) return raw.cast<String>();
    } catch (_) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    return [];
  }

  Future<void> setFavorites(List<String> ids) async {
    if (!isReady) return;
    await _box!.put(_kFavorites, ids);
  }

  Future<bool> toggleFavorite(String offerId) async {
    final favs = getFavorites();
    bool added;
    if (favs.contains(offerId)) {
      favs.remove(offerId);
      added = false;
    } else {
      favs.add(offerId);
      added = true;
    }
    await setFavorites(favs);
    return added;
  }

  bool isFavorite(String offerId) => getFavorites().contains(offerId);

  // ═══════════════════════════════════════
  // عام
  // ═══════════════════════════════════════
  Future<void> put(String key, dynamic value) async {
    if (!isReady) return;
    await _box!.put(key, value);
  }

  dynamic get(String key) {
    if (!isReady) return null;
    return _box!.get(key);
  }

  Future<void> remove(String key) async {
    if (!isReady) return;
    await _box!.delete(key);
  }

  Future<void> clear() async {
    if (!isReady) return;
    await _box!.clear();
  }
}
