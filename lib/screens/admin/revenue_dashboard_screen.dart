import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_utils.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';

/// الواردات فقط — للمدير الرئيسي حصراً. لا يحسب المصاريف أو صافي الربح.
class RevenueDashboardScreen extends StatefulWidget {
  const RevenueDashboardScreen({super.key});

  @override
  State<RevenueDashboardScreen> createState() => _RevenueDashboardScreenState();
}

class _RevenueDashboardScreenState extends State<RevenueDashboardScreen> {
  String _period = 'month';
  bool _loading = true;
  Map<String, dynamic> _report = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final token = await AuthService().getStaffSessionToken();
      final res = await SupabaseService().invokeFunction('admin-dashboard', body: {
        'action': 'revenue_report',
        'admin_uid': uid,
        'staff_session_token': token,
        'period': _period,
      });
      final data = res.data as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          _report = data?['success'] == true ? data! : {};
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  num _n(Map<String, dynamic> map, String key) => (map[key] as num?) ?? 0;
  String _money(num value) => value.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');

  Future<void> _markLawyerPaid(Map<String, dynamic> lawyer) async {
    final payable = (lawyer['payable'] as num?) ?? 0;
    if (payable <= 0) return;
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تسجيل دفع مستحقات المحامي',
            style: TextStyle(color: AppTheme.primaryGold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${lawyer['lawyer_name']} — ${_money(payable)} ل.س',
              style: const TextStyle(color: AppTheme.textWhite,
                  fontWeight: FontWeight.bold)),
          AppTheme.gapHeightMedium,
          TextField(
            controller: noteCtrl,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(
              labelText: 'ملاحظة أو طريقة الدفع (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد الدفع الكامل')),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true || !mounted) return;
    try {
      final uid = context.read<AuthProvider>().userModel?.uid ?? '';
      final token = await AuthService().getStaffSessionToken();
      final res = await SupabaseService().invokeFunction('admin-dashboard', body: {
        'action': 'mark_lawyer_paid',
        'admin_uid': uid,
        'staff_session_token': token,
        'lawyer_uid': (lawyer['lawyer_uid'] ?? '').toString(),
        'note': note,
      });
      // 🩹 م6: قراءة محصَّنة للرد — أي خطأ يُعرض نصاً واضحاً بدل شاشة حمراء
      final data = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      final ok = data['success'] == true;
      final amount = (data['amount'] as num?) ?? payable;
      AppTheme.showSnackBar(context, SnackBar(
        content: Text(ok
            ? '✅ تم تسجيل دفع ${_money(amount)} ل.س'
            : 'تعذّر تسجيل الدفع: ${(data['error'] ?? 'خطأ غير معروف')}'),
      ));
      if (ok) {
        try { await _load(); } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(context,
            SnackBar(content: Text('تعذّر تسجيل الدفع: ${ErrorUtils.arabicMessage(e)}')));
      }
    }
  }

  /// تنسيق النطاق الزمني (from/to) من السيرفر
  String _fmtRange(dynamic ts) {
    final dt = DateTime.tryParse(ts?.toString() ?? '')?.toLocal();
    if (dt == null) return (ts ?? '—').toString();
    return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final payments = _report['payments_syp'] is Map
        ? Map<String, dynamic>.from(_report['payments_syp'] as Map)
        : <String, dynamic>{};
    final channels = (_report['channels'] as List?) ?? const [];
    final daily = (_report['daily'] as List?) ?? const [];
    final deals = (_report['deal_commissions'] as List?) ?? const [];
    final lawyers = (_report['lawyers'] as List?) ?? const [];

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        title: const Text('واردات الشركة'),
        actions: [IconButton(
          icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
          onPressed: _load,
        )],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppTheme.primaryGold))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.primaryGold,
              child: ListView(
                padding: AppTheme.paddingAllLarge,
                children: [
                  Wrap(spacing: 7, children: [
                    _periodChip('اليوم', 'today'),
                    _periodChip('7 أيام', '7days'),
                    _periodChip('هذا الشهر', 'month'),
                    _periodChip('كل الفترة', 'all'),
                  ]),
                  AppTheme.gapHeightSmall,
                  // 🩹 م6 (2026-08-20): عرض النطاق الفعلي الذي أعاده السيرفر —
                  // كان اختيار الفلتر بلا أي دليل مرئي فيبدو «لا يعمل».
                  if (_report['from'] != null && _report['to'] != null)
                    Text(
                      'الفترة: ${_fmtRange(_report['from'])} ← ${_fmtRange(_report['to'])}',
                      style: const TextStyle(
                          color: AppTheme.infoBlue,
                          fontSize: AppTheme.fontSizeCaption,
                          fontWeight: FontWeight.w600),
                    ),
                  AppTheme.gapHeightLarge,
                  const Text('المبالغ المقبوضة عبر التطبيق — ليرة سورية',
                      style: TextStyle(color: AppTheme.textGrey,
                          fontSize: 12)),
                  AppTheme.gapHeightSmall,
                  _mainMetric('إجمالي المقبوض', _n(payments, 'gross'),
                      AppTheme.primaryGold),
                  AppTheme.gapHeightSmall,
                  Row(children: [
                    Expanded(child: _smallMetric('حصة المحامين',
                        _n(payments, 'lawyer_share'), AppTheme.warningOrange)),
                    AppTheme.gapWidthSmall,
                    Expanded(child: _smallMetric('صافي حصة المكتب',
                        _n(payments, 'office_net'), AppTheme.successGreen)),
                  ]),
                  AppTheme.gapHeightLarge,
                  _section('تفصيل الواردات'),
                  _line('الباقات', _n(payments, 'packages')),
                  _line('الإعلانات المميزة', _n(payments, 'featured')),
                  _line('الاستشارات — إجمالي', _n(payments, 'legal_gross')),
                  _line('دفعات معلقة وليست واردات', _n(payments, 'pending'),
                      color: AppTheme.warningOrange),
                  _line('دفعات معكوسة', _n(payments, 'reversed'),
                      color: AppTheme.errorRed),
                  AppTheme.gapHeightLarge,
                  _section('حسب قناة الدفع'),
                  ...channels.map((raw) {
                    final c = Map<String, dynamic>.from(raw as Map);
                    return _line('${c['channel']} (${c['operations']})',
                        (c['amount'] as num?) ?? 0);
                  }),
                  AppTheme.gapHeightLarge,
                  _section('الوارد اليومي'),
                  if (daily.isEmpty)
                    const Text('لا توجد واردات في الفترة',
                        style: TextStyle(color: AppTheme.textGrey))
                  else
                    ...daily.map((raw) {
                      final d = Map<String, dynamic>.from(raw as Map);
                      return _line((d['day'] ?? '—').toString(),
                          (d['office_net'] as num?) ?? 0,
                          suffix: 'صافي المكتب');
                    }),
                  AppTheme.gapHeightLarge,
                  _section('مستحقات المحامين'),
                  if (lawyers.isEmpty)
                    const Text('لا توجد مستحقات محامين',
                        style: TextStyle(color: AppTheme.textGrey))
                  else
                    ...lawyers.map((raw) {
                      final l = Map<String, dynamic>.from(raw as Map);
                      final payable = (l['payable'] as num?) ?? 0;
                      return Card(
                        color: AppTheme.surfaceBlack,
                        child: ListTile(
                          title: Text((l['lawyer_name'] ?? 'محامٍ').toString(),
                              style: const TextStyle(color: AppTheme.textWhite,
                                  fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'قيد الاستحقاق: ${_money((l['pending'] as num?) ?? 0)} • '
                            'له عندك: ${_money(payable)} • '
                            'مدفوع: ${_money((l['paid'] as num?) ?? 0)} ل.س',
                            style: const TextStyle(color: AppTheme.textGrey,
                                fontSize: 11),
                          ),
                          trailing: payable > 0
                              ? TextButton(
                                  onPressed: () => _markLawyerPaid(l),
                                  child: const Text('تسجيل الدفع'))
                              : null,
                        ),
                      );
                    }),
                  AppTheme.gapHeightLarge,
                  _section('عمولات الصفقات المسجلة'),
                  const Text(
                    'تظهر منفصلة حسب العملة لأنها عمولة مسجلة على الصفقة وليست دفعة مقبوضة عبر payments.',
                    style: TextStyle(color: AppTheme.textGrey,
                        fontSize: 11, height: 1.4),
                  ),
                  if (deals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('لا توجد عمولات صفقات في الفترة',
                          style: TextStyle(color: AppTheme.textGrey)),
                    )
                  else
                    ...deals.map((raw) {
                      final d = Map<String, dynamic>.from(raw as Map);
                      final currency = d['currency'] == 1 ? 'ل.س' : 'دولار';
                      return _line('${d['deals']} صفقة — $currency',
                          (d['amount'] as num?) ?? 0,
                          currency: currency);
                    }),
                ],
              ),
            ),
    );
  }

  Widget _periodChip(String label, String value) => ChoiceChip(
    selected: _period == value,
    label: Text(label),
    selectedColor: AppTheme.primaryGold,
    onSelected: (_) {
      setState(() => _period = value);
      _load();
    },
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(color: AppTheme.primaryGold,
        fontSize: 15, fontWeight: FontWeight.bold)),
  );

  Widget _mainMetric(String label, num amount, Color color) => Container(
    width: double.infinity,
    padding: AppTheme.paddingAllLarge,
    decoration: BoxDecoration(color: color.withOpacity(0.1),
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(color: color.withOpacity(0.4))),
    child: Column(children: [
      Text(label, style: TextStyle(color: color)),
      Text('${_money(amount)} ل.س', style: TextStyle(color: color,
          fontSize: 25, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _smallMetric(String label, num amount, Color color) => Container(
    padding: AppTheme.paddingAllMedium,
    decoration: BoxDecoration(color: color.withOpacity(0.08),
        borderRadius: AppTheme.radiusSmall),
    child: Column(children: [
      Text(label, textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 10)),
      Text(_money(amount), style: TextStyle(color: color,
          fontSize: 17, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _line(String label, num amount,
      {Color color = AppTheme.textWhite, String currency = 'ل.س',
      String suffix = ''}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: 12))),
      Text('${_money(amount)} $currency${suffix.isEmpty ? '' : ' — $suffix'}',
          style: TextStyle(color: color, fontWeight: FontWeight.bold,
              fontSize: 12)),
    ]),
  );
}
