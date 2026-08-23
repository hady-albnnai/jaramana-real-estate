import 'package:flutter/foundation.dart';
import '../models/appointment_model.dart';
import '../models/offer_model.dart';
import '../models/deal_model.dart';
import '../core/network/supabase_service.dart';

/// Provider خاص بلوحة الوسيط/السمسار (دور role = 1)
/// يجمع كل عمليات السمسار: المواعيد، العروض، الصفقات، الإحصائيات
class BrokerProvider with ChangeNotifier {
  bool _isLoading = false;
  String? _error;

  List<AppointmentModel> _appointments = [];
  List<OfferModel> _offers = [];
  List<DealModel> _deals = [];
  Map<String, dynamic> _stats = {};

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<AppointmentModel> get appointments => _appointments;
  List<OfferModel> get offers => _offers;
  List<DealModel> get deals => _deals;
  Map<String, dynamic> get stats => _stats;

  Future<void> fetchBrokerAppointments(String brokerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _appointments = await getBrokerAppointments(brokerId);
    } catch (e) {
      _error = 'فشل جلب المواعيد: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<List<AppointmentModel>> getBrokerAppointments(String brokerId) async {
    try {
      final response = await SupabaseService().invokeFunction(
        'user-appointments',
        body: {
          'action': 'list_broker_appointments',
          'user_uid': brokerId,
        },
      );
      final data = response.data;
      if (data == null || data['success'] != true) throw Exception(data?['error'] ?? 'Unknown error');
      final list = data['appointments'] as List;
      return list
          .map((d) => AppointmentModel.fromSupabase(
              Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
    } catch (e) {
      // لا نحول فشل الشبكة أو الصلاحية إلى قائمة فارغة؛ الشاشة تحتاج
      // التفريق بين «لا توجد مواعيد» و«تعذر التحميل».
      rethrow;
    }
  }

  Future<bool> handleAppointment(String brokerUid, String apptId, int feedback) async {
    try {
      final action = feedback == 1
          ? 'confirm'
          : feedback == 2
              ? 'reject'
              : 'pending';
      if (action == 'pending') return false;

      // ✅ Secure via user-appointments Edge Function (broker_handle action)
      final response = await SupabaseService().invokeFunction(
        'user-appointments',
        body: {
          'action': 'broker_handle',
          'user_uid': brokerUid,
          'appointment_id': apptId,
          'handle_action': action,
        },
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) return false;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> completeAppointment(String brokerUid, String apptId) async {
    try {
      // ✅ Secure via user-appointments Edge Function (broker_handle action)
      final response = await SupabaseService().invokeFunction(
        'user-appointments',
        body: {
          'action': 'broker_handle',
          'user_uid': brokerUid,
          'appointment_id': apptId,
          'handle_action': 'complete',
        },
      );
      final data = response.data;
      if (data is! Map || data['success'] != true) return false;
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> fetchBrokerOffers(String brokerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'broker_offers',
          'user_uid': brokerId,
        },
      );
      final data = response.data;
      if (data == null || data['success'] != true) throw Exception('Error');
      _offers = (data['offers'] as List)
          .map((d) =>
              OfferModel.fromSupabase(Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
    } catch (e) {
      _error = 'فشل جلب العروض: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchBrokerDeals(String brokerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final response = await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'broker_deals',
          'user_uid': brokerId,
        },
      );
      final data = response.data;
      if (data == null || data['success'] != true) throw Exception('Error');
      _deals = (data['deals'] as List)
          .map((d) =>
              DealModel.fromSupabase(Map<String, dynamic>.from(d), d['id'] as String))
          .toList();
    } catch (e) {
      _error = 'فشل جلب الصفقات: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchBrokerStats(String brokerId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final offersRes = await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'broker_offers',
          'user_uid': brokerId,
        },
      );
      final offersData = offersRes.data;
      if (offersData is! Map || offersData['success'] != true || offersData['offers'] is! List) {
        throw Exception('BROKER_OFFERS_STATS_FAILED');
      }
      final offersList = offersData['offers'] as List;
      final totalOffers = offersList.length;
      final publishedOffers =
          offersList.where((o) => (o['sts'] ?? 0) == 2).length;
      final totalViews = offersList.fold<int>(
          0, (sum, o) => sum + _asInt((o as Map)['vws']));
      final totalFavs = offersList.fold<int>(
          0, (sum, o) => sum + _asInt((o as Map)['fvs']));

      final apptRes = await SupabaseService().invokeFunction(
        'user-appointments',
        body: {
          'action': 'list_broker_appointments',
          'user_uid': brokerId,
        },
      );
      final apptData = apptRes.data;
      if (apptData is! Map || apptData['success'] != true || apptData['appointments'] is! List) {
        throw Exception('BROKER_APPOINTMENTS_STATS_FAILED');
      }
      final apptList = apptData['appointments'] as List;
      final totalAppointments = apptList.length;
      final completedAppointments =
          apptList.where((a) => (a['sts'] ?? 0) == 2).length;

      final dealsRes = await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'broker_deals',
          'user_uid': brokerId,
        },
      );
      final dealsData = dealsRes.data;
      if (dealsData is! Map || dealsData['success'] != true || dealsData['deals'] is! List) {
        throw Exception('BROKER_DEALS_STATS_FAILED');
      }
      final dealsList = dealsData['deals'] as List;
      final totalDeals = dealsList.length;
      final completedDeals =
          dealsList.where((d) => (d['sts'] ?? 0) == 1).length;
      final totalCommission = dealsList
          .where((d) => (d['sts'] ?? 0) == 1)
          .fold<double>(0,
              (sum, d) => sum + (((d['com_val'] ?? 0) as num).toDouble()));
      final totalDealsValue = dealsList
          .where((d) => (d['sts'] ?? 0) == 1)
          .fold<double>(0,
              (sum, d) => sum + (((d['fin_prc'] ?? 0) as num).toDouble()));

      _stats = {
        'totalOffers': totalOffers,
        'publishedOffers': publishedOffers,
        'totalViews': totalViews,
        'totalFavs': totalFavs,
        'totalAppointments': totalAppointments,
        'completedAppointments': completedAppointments,
        'totalDeals': totalDeals,
        'completedDeals': completedDeals,
        'totalCommission': totalCommission,
        'totalDealsValue': totalDealsValue,
      };
    } catch (e) {
      _error = 'فشل جلب الإحصائيات: $e';
    }
    _isLoading = false;
    notifyListeners();
  }

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
