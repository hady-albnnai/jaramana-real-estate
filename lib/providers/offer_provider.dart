import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/offer_model.dart';
import '../models/user_model.dart';
import '../core/network/supabase_service.dart';
import '../core/constants/db_constants.dart';
import '../core/services/local_cache_service.dart';
import '../core/services/business_service.dart';
import '../core/utils/error_utils.dart';

class OfferProvider with ChangeNotifier {
  List<OfferModel> _offers = [];
  bool _isLoading = false;
  String? _error;
  bool _fromCache = false;
  StreamSubscription? _realtimeSub;

  // تتبع ما إذا كانت القائمة الحالية ناتجة عن بحث
  bool _isSearching = false;

  // 📄 Pagination — مرجع: docs/LOGIC_SPEC.md §4.2
  static const int pageSize = 20;
  int _currentPage = 0;
  bool _hasMore = true;
  bool _loadingMore = false;

  bool get hasMore => _hasMore;
  bool get loadingMore => _loadingMore;

  List<OfferModel> get offers => _offers;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get fromCache => _fromCache;

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setError(Object? error) {
    _error = ErrorUtils.arabicMessage(error);
  }

  /// 📌 ترتيب العروض حسب الأولوية (مثبّت أولاً، ثم مميّز، ثم Boost، ثم الأحدث)
  void _sortByPriority() {
    _offers.sort((a, b) {
      // i_pin تنازلي (1=مثبّت قبل 0)
      if (a.iPin != b.iPin) return b.iPin.compareTo(a.iPin);
      // i_fms تنازلي
      if (a.iFms != b.iFms) return b.iFms.compareTo(a.iFms);
      // i_bst تنازلي
      if (a.iBst != b.iBst) return b.iBst.compareTo(a.iBst);
      // الأحدث أولاً
      return b.tsCrt.compareTo(a.tsCrt);
    });
  }

  /// 🏢 إثراء قائمة العروض بتسميات الملاك المهنية (هوية المكتب).
  /// يجلب الملاك في استعلام واحد batch، ثم يحقن ownerLabel في كل عرض.
  /// مرجع: docs/LOGIC_SPEC.md §1
  Future<void> _enrichOwnerLabels(List<OfferModel> offers) async {
    if (offers.isEmpty) return;
    try {
      final ownerIds = offers
          .map((o) => o.usrId)
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (ownerIds.isEmpty) return;

      final res = await SupabaseService()
          .client
          .from(DbTables.usersPublic)
          .select('id, nm, role, brk, bg, vrf, ts_crt')
          .inFilter('id', ownerIds);

      final Map<String, UserModel> ownersMap = {};
      for (final row in (res as List)) {
        final m = Map<String, dynamic>.from(row);
        ownersMap[m['id'] as String] = UserModel.fromSupabase(m, m['id'] as String);
      }

      final bs = BusinessService();
      for (final o in offers) {
        final owner = ownersMap[o.usrId];
        if (owner != null) {
          o.ownerLabel = bs.getUserPublicLabel(owner);
        }
      }
    } catch (e) {
      _setError(e);
    }
  }

  Future<void> fetchOffers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // 1) عرض الكاش فوراً (دعم العمل دون اتصال)
    if (_offers.isEmpty) {
      final cached = LocalCacheService().getOffers();
      if (cached.isNotEmpty) {
        _offers = cached
            .map((d) => OfferModel.fromSupabase(d, d['id'] as String))
            .toList();
        _sortByPriority(); // ترتيب: المثبّت أولاً
        _fromCache = true;
        notifyListeners();
      }
    }

    // 2) جلب من السيرفر
    try {
      final response = await SupabaseService().client
          .from(DbTables.offers)
          .select(kOfferPublicColumns)
          .eq('i_del', 0)
          .eq('i_pub', 1)
          .order('i_pin', ascending: false) // المثبّتة أولاً
          .order('i_fms', ascending: false) // ثم المميّزة
          .order('i_bst', ascending: false) // ثم Boost
          .order('ts_crt', ascending: false);
      _offers = (response as List)
          .map((d) =>
              OfferModel.fromSupabase(Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
      _fromCache = false;
      // 🏢 إثراء بهوية المكتب
      await _enrichOwnerLabels(_offers);
      // حفظ في الكاش
      await LocalCacheService()
          .saveOffers(_offers.map((o) => {'id': o.id, ...o.toMap()}).toList());
    } catch (e) {
      // عند الفشل: إن كان عندنا كاش نكمل به بدون خطأ صريح
      if (_offers.isEmpty) {
        _error = 'فشل في جلب العروض. تحقق من الاتصال.';
      } else {
        _fromCache = true;
        _setError(e);
      }
    }
    // 📄 إعادة ضبط حالة pagination بعد fetch جديد
    _currentPage = (_offers.length / pageSize).ceil();
    _hasMore = _offers.length >= pageSize;
    _isLoading = false;
    notifyListeners();
  }

  /// 📄 تحميل صفحة تالية من العروض (Pagination).
  /// تُستدعى عند وصول المستخدم لأسفل القائمة (Infinite scroll).
  /// مرجع: docs/LOGIC_SPEC.md §4.2
  Future<void> loadMoreOffers() async {
    if (_loadingMore || !_hasMore || _isSearching) return;
    _loadingMore = true;
    notifyListeners();

    try {
      final from = _currentPage * pageSize;
      final to = from + pageSize - 1;
      final response = await SupabaseService().client
          .from(DbTables.offers)
          .select(kOfferPublicColumns)
          .eq('i_del', 0)
          .eq('i_pub', 1)
          .order('i_pin', ascending: false)
          .order('i_fms', ascending: false)
          .order('i_bst', ascending: false)
          .order('ts_crt', ascending: false)
          .range(from, to);

      final newOffers = (response as List)
          .map((d) => OfferModel.fromSupabase(
              Map<String, dynamic>.from(d), d['id'] as String))
          .toList();

      if (newOffers.isEmpty || newOffers.length < pageSize) {
        _hasMore = false;
      }
      if (newOffers.isNotEmpty) {
        // تجنب التكرار: استبعاد العروض الموجودة مسبقاً
        final existingIds = _offers.map((o) => o.id).toSet();
        final unique =
            newOffers.where((o) => !existingIds.contains(o.id)).toList();
        await _enrichOwnerLabels(unique);
        _offers.addAll(unique);
        _currentPage++;
      }
    } catch (e) {
      _setError(e);
    }
    _loadingMore = false;
    notifyListeners();
  }

  /// تفعيل التحديث الفوري (Realtime) لقائمة العروض المنشورة
  void subscribeRealtime() {
    _realtimeSub?.cancel();
    try {
      _realtimeSub = SupabaseService()
          .client
          .from(DbTables.offers)
          .stream(primaryKey: ['id'])
          .order('ts_crt', ascending: false)
          .listen((data) {
        final published = data
            .where((row) =>
                (row['i_pub'] ?? 0) == 1 && (row['i_del'] ?? 0) == 0)
            .map((row) =>
                OfferModel.fromSupabase(Map<String, dynamic>.from(row), row['id'] as String))
            .toList();
        
        if (published.isNotEmpty) {
          // تحديث القائمة فقط إذا لم يكن المستخدم في وضع البحث
          if (!_isSearching) {
            _offers = published;
            _sortByPriority(); // ترتيب: المثبّت أولاً (الـ stream ما بيدعم sort ب i_pin)
            _fromCache = false;
            // 🏢 إثراء بهوية المكتب (fire-and-forget لا يعطل التدفق)
            _enrichOwnerLabels(_offers).then((_) => notifyListeners());
            LocalCacheService()
                .saveOffers(_offers.map((o) => {'id': o.id, ...o.toMap()}).toList());
            notifyListeners();
          } else {}
        }
      });} catch (e) {
      _setError(e);
    }
  }

  void unsubscribeRealtime() {
    _realtimeSub?.cancel();
    _realtimeSub = null;
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// فحص ما إذا كان العرض مكرراً (يُستخدم عند الإضافة أو التعديل)
  Future<bool> checkDuplicate({
    required String title,
    required double price,
    required Map<String, dynamic> loc,
    required String userId,
  }) async {
    try {
      final response = await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'check_duplicate',
          'title': title,
          'price': price,
          'loc': loc,
          'usr_id': userId,
        },
      );
      final data = response.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) return false;
      return data['is_duplicate'] == true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  Future<List<OfferModel>> fetchUserOffers(String userId) async {
    try {
      final response = await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'list',
          'user_uid': userId,
        },
      );
      final data = response.data;
      if (data == null || data['success'] != true) throw Exception(data?['error'] ?? 'Unknown error');
      final rawList = data['offers'] as List;
      final list = rawList
          .map((d) => OfferModel.fromSupabase(
              Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
      await _enrichOwnerLabels(list);
      return list;
    } catch (e) {
      _setError(e);
      return [];
    }
  }

        Future<OfferModel?> fetchOfferById(String offerId, {String? userId}) async {
        try {
          /// 🛡️ المحاولة الأولى: مباشرة من الجدول (لأي مستخدم مسجل)
          /// RLS يسمح للمنشور و لأصحاب العرض و للإدارة (role >= 2)
          if (userId != null && userId.isNotEmpty) {
            final directRow = await SupabaseService().client
                .from(DbTables.offers)
                .select(kOfferPublicColumns)
                .eq('id', offerId)
                .maybeSingle();
            if (directRow != null) {
              final offer = OfferModel.fromSupabase(Map<String, dynamic>.from(directRow), directRow['id'] as String);
              await _enrichOwnerLabels([offer]);
              return offer;
            }
          }

          /// 🛡️ المحاولة الثانية: عبر Edge Function (للمستخدمين العاديين)
          /// الدالة get_offer_by_id_internal ترجع SETOF offers (مصفوفة)
          final response = await SupabaseService().invokeFunction(
            'user-offers',
            body: {
              'action': 'get_by_id',
              'offer_id': offerId,
              'user_uid': userId,
            },
          );
          final data = response.data;
          if (data != null && data['success'] == true) {
            final offerRaw = data['offer'];
            // الدالة ترجع مصفوفة (SETOF) — نأخذ أول عنصر
            if (offerRaw is List) {
              if (offerRaw.isNotEmpty) {
                final row = Map<String, dynamic>.from(offerRaw.first as Map);
                final offer = OfferModel.fromSupabase(row, row['id'] as String);
                await _enrichOwnerLabels([offer]);
                return offer;
              }
            } else if (offerRaw is Map) {
              // في حال غيّرنا Edge Function لترجع كائن مباشرة
              final row = Map<String, dynamic>.from(offerRaw);
              final offer = OfferModel.fromSupabase(row, row['id'] as String);
              await _enrichOwnerLabels([offer]);
              return offer;
            }
          }

          // 🛡️ Fallback أخير — لأي حالة
          try {
            final q = SupabaseService().client
                .from(DbTables.offers)
                .select(kOfferPublicColumns)
                .eq('id', offerId)
                .eq('i_del', 0);
            if (userId == null || userId.isEmpty) {
              q.eq('i_pub', 1);
            }
            final fallbackRow = await q.maybeSingle();
            if (fallbackRow != null) {
              final offer = OfferModel.fromSupabase(Map<String, dynamic>.from(fallbackRow), fallbackRow['id'] as String);
              await _enrichOwnerLabels([offer]);
              return offer;
            }
          } catch (_) {}

          return null;
        } catch (e) {
          _setError(e);
          return null;
        }
  }

  Future<OfferModel?> addOffer(OfferModel offer) async {
    try {
      final res = await SupabaseService().invokeFunction('user-offers', body: {'action': 'create', 'user_uid': offer.usrId, 'offer': offer.toMap()}); final data = res.data as Map; final response = data['offer_id'];
      if (response == null || (response is! List) || response.isEmpty) return null;
      final row = Map<String, dynamic>.from(response.first as Map);
      final created = OfferModel.fromSupabase(row, row['id'] as String);
      _offers.insert(0, created);
      _sortByPriority(); // ترتيب: المثبّت أولاً حتى لو أُضيف عرض جديد
      
      notifyListeners();
      return created;
    } catch (e) {
      _setError(e);
      return null;
    }
  }

  Future<bool> updateOffer(String offerId, Map<String, dynamic> data, {required String userUid}) async {
    try {
      // 2026-07-27: الحفظ عبر الإيدج — قناة PATCH المباشرة بصلاحية anon كانت مرفوضة
      // خادمياً (42501 بعد سحب RLS) فما كان أي تعديل ينحفظ إطلاقاً.
      // الإيدج يفرض: الجلسة + الملكية + whitelist + إعادة العرض تلقائياً للمراجعة.
      final cleaned = Map<String, dynamic>.from(data)
        ..removeWhere((k, _) => const {'sts', 'i_pub', 'ts_pub', 'i_del', 'usr_id', 'id', 'ts_ren'}.contains(k));
      final res = await SupabaseService().invokeFunction('user-offers', body: {
        'action': 'update_offer',
        'user_uid': userUid,
        'offer_id': offerId,
        'data': cleaned,
      });
      final m = res.data;
      if (m is! Map || m['success'] != true) {
        _setError(Exception(m is Map ? (m['error'] ?? 'UPDATE_FAILED') : 'UPDATE_FAILED'));
        return false;
      }

      final index = _offers.indexWhere((o) => o.id == offerId);
      if (index != -1) {
        final updated = await fetchOfferById(offerId);
        if (updated != null) _offers[index] = updated;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  Future<bool> softDeleteOffer(String offerId, {required String userUid}) async {
    try {
      // 2026-07-27: الحذف عبر الإيدج (نفس قناة التعديل الموثقة)
      final res = await SupabaseService().invokeFunction('user-offers', body: {
        'action': 'delete_offer',
        'user_uid': userUid,
        'offer_id': offerId,
      });
      final m = res.data;
      if (m is! Map || m['success'] != true) {
        _setError(Exception(m is Map ? (m['error'] ?? 'DELETE_FAILED') : 'DELETE_FAILED'));
        return false;
      }
      _offers.removeWhere((o) => o.id == offerId);
      notifyListeners();
      return true;
    } catch (e) {
      _setError(e);
      return false;
    }
  }

  Future<void> incrementViews(String offerId, {String? viewerUid}) async {
    try {
      await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'increment_views',
          'offer_id': offerId,
          if (viewerUid != null) 'viewer_uid': viewerUid,
        },
      );
    } catch (e) {
      _setError(e);
    }
  }

  Future<List<OfferModel>> searchOffers({
    String? query, int? type, int? transaction, int? category,
    double? minPrice, double? maxPrice, int? currency,
  }) async {
    _isSearching = true; // تفعيل حالة البحث
    try {
      var q = SupabaseService().client.from(DbTables.offers)
          .select(kOfferPublicColumns).eq('i_del', 0).eq('i_pub', 1);
      if (query != null && query.isNotEmpty) q = q.ilike('ttl', '%$query%');
      if (type != null) q = q.eq('typ', type);
      if (transaction != null) q = q.eq('trx', transaction);
      if (category != null) q = q.eq('cat', category);
      if (currency != null) q = q.eq('cur', currency);
      if (minPrice != null) q = q.gte('prc', minPrice);
      if (maxPrice != null) q = q.lte('prc', maxPrice);
      final response = await q.order('ts_crt', ascending: false);
      final results = (response as List).map((d) =>
          OfferModel.fromSupabase(Map<String, dynamic>.from(d), d['id'] as String)).toList();

      await _enrichOwnerLabels(results);
      _offers = results;
      notifyListeners();
      return results;
    } catch (e) {
      _setError(e);
      return [];
    }
  }

  void listenToNewOffers(Function(OfferModel) onNewOffer) {
    SupabaseService().client.from(DbTables.offers)
        .stream(primaryKey: ['id'])
        .order('ts_crt', ascending: false)
        .listen((data) {
      for (var row in data) {
        if ((row['i_pub'] ?? 0) == 1 && (row['i_del'] ?? 0) == 0) {
          onNewOffer(OfferModel.fromSupabase(
              Map<String, dynamic>.from(row), row['id'] as String));
        }
      }
    });
  }

  OfferModel? getOfferById(String id) {
    try { return _offers.firstWhere((o) => o.id == id); } catch (_) { return null; }
  }
}
