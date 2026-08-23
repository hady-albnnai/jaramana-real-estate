import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/broker_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/theme/app_theme.dart';

/// 📈 إحصائيات الوسيط التفصيلية — أرقام + رسوم بسيطة (بدون مكتبات خارجية)
class BrokerStatsScreen extends StatefulWidget {
  const BrokerStatsScreen({super.key});

  @override
  State<BrokerStatsScreen> createState() => _BrokerStatsScreenState();
}

class _BrokerStatsScreenState extends State<BrokerStatsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    final id = context.read<AuthProvider>().userModel?.uid ?? '';
    if (id.isNotEmpty) {
      await context.read<BrokerProvider>().fetchBrokerStats(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final broker = context.watch<BrokerProvider>();
    final s = broker.stats;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('الإحصائيات'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: broker.isLoading && s.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : broker.error != null && s.isEmpty
              ? _error()
              : RefreshIndicator(
              color: AppTheme.primaryGold,
              onRefresh: () async => _load(),
              child: ListView(
                padding: AppTheme.paddingAllLarge,
                children: [
                  _section('📊 نظرة عامة'),
                  Row(
                    children: [
                      Expanded(
                          child: _miniStat('العروض', '${s['totalOffers'] ?? 0}',
                              Icons.home_work)),
                      AppTheme.gapWidthMedium,
                      Expanded(
                          child: _miniStat('المشاهدات',
                              '${s['totalViews'] ?? 0}', Icons.visibility)),
                    ],
                  ),
                  AppTheme.gapHeightMedium,
                  Row(
                    children: [
                      Expanded(
                          child: _miniStat('المفضلة', '${s['totalFavs'] ?? 0}',
                              Icons.favorite)),
                      AppTheme.gapWidthMedium,
                      Expanded(
                          child: _miniStat('المواعيد',
                              '${s['totalAppointments'] ?? 0}',
                              Icons.calendar_today)),
                    ],
                  ),

                  AppTheme.gapHeightXXL,
                  _section('🏠 حالة العروض'),
                  _bar('منشورة', _toInt(s['publishedOffers']),
                      _toInt(s['totalOffers']), AppTheme.successGreen),
                  _bar(
                      'غير منشورة',
                      _toInt(s['totalOffers']) - _toInt(s['publishedOffers']),
                      _toInt(s['totalOffers']),
                      AppTheme.warningOrange),

                  AppTheme.gapHeightXXL,
                  _section('📅 المواعيد'),
                  _bar('مكتملة', _toInt(s['completedAppointments']),
                      _toInt(s['totalAppointments']), AppTheme.primaryGold),
                  _bar(
                      'غير مكتملة',
                      _toInt(s['totalAppointments']) -
                          _toInt(s['completedAppointments']),
                      _toInt(s['totalAppointments']),
                      AppTheme.textGrey),

                  AppTheme.gapHeightXXL,
                  _section('🤝 الصفقات والعمولات'),
                  _bar('صفقات مكتملة', _toInt(s['completedDeals']),
                      _toInt(s['totalDeals']), AppTheme.successGreen),
                  AppTheme.gapHeightMedium,
                  _bigMetric('إجمالي قيمة الصفقات',
                      '${_toDouble(s['totalDealsValue']).toStringAsFixed(0)} \$'),
                  AppTheme.gapHeightMedium,
                  _bigMetric('إجمالي العمولات المحققة',
                      '${_toDouble(s['totalCommission']).toStringAsFixed(0)} \$',
                      gold: true),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _error() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppTheme.errorRed),
            AppTheme.gapHeightLarge,
            const Text('تعذر تحميل إحصائيات الوسيط',
                style: TextStyle(color: AppTheme.textGrey)),
            AppTheme.gapHeightMedium,
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );

  int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  double _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(title,
            style: const TextStyle(
                color: AppTheme.primaryGold,
                fontSize: AppTheme.fontSizeSubtitle,
                fontWeight: FontWeight.bold)),
      );

  Widget _miniStat(String label, String value, IconData icon) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppTheme.primaryGold, size: 26),
          AppTheme.gapHeightSmall,
          Text(value,
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
        ],
      ),
    );
  }

  /// شريط نسبة بسيط مرسوم بـ widgets أصلية
  Widget _bar(String label, int value, int total, Color color) {
    final pct = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
              Text('$value (${(pct * 100).toStringAsFixed(0)}%)',
                  style: TextStyle(color: color, fontSize: AppTheme.fontSizeSmall)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: AppTheme.radiusSmall,
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: AppTheme.surfaceBlack,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigMetric(String label, String value, {bool gold = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(
            color: (gold ? AppTheme.primaryGold : Colors.white12)
                .withOpacity(gold ? 0.5 : 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
          const SizedBox(height: 6),
          Text(value,
              style: TextStyle(
                  color: gold ? AppTheme.primaryGold : AppTheme.textWhite,
                  fontSize: AppTheme.fontSizeLarge,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
