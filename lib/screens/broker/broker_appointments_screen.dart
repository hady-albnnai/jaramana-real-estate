import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/broker_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/appointment_model.dart';
import '../../models/offer_model.dart';
import '../../core/network/supabase_service.dart';
import '../../core/constants/db_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/office_logo_placeholder.dart';
import '../../widgets/bottom_nav_bar.dart';

/// شاشة طلبات المعاينة للسمسار — مع فلترة بالحالة + تفاصيل العميل
/// + إجراءات: قبول / رفض / إكمال المعاينة + اتصال/واتساب
class BrokerAppointmentsScreen extends StatefulWidget {
  const BrokerAppointmentsScreen({super.key});

  @override
  State<BrokerAppointmentsScreen> createState() =>
      _BrokerAppointmentsScreenState();
}

class _BrokerAppointmentsScreenState extends State<BrokerAppointmentsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<AppointmentModel> _all = [];
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;
  final Set<String> _busyAppointments = <String>{};

  final Map<String, OfferModel> _offers = {};
  // _requesters حُذف — القاعدة الذهبية: لا نجلب بيانات طالب الحجز أبداً

  // فلاتر: -1=الكل, 0=قيد الانتظار, 1=مؤكد, 2=مكتمل, 4=مرفوض, 3=ملغي, 5=لم يحضر
  static const _tabs = [
    ('قيد الانتظار', 0),
    ('مؤكد', 1),
    ('مكتمل', 2),
    ('الكل', -1),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = context.read<AuthProvider>();
    final broker = context.read<BrokerProvider>();
    final brokerId = auth.userModel?.uid ?? '';
    if (brokerId.isEmpty) {
      if (mounted && generation == _loadGeneration) {
        setState(() { _loading = false; _error = 'انتهت جلسة الوسيط'; });
      }
      return;
    }

    try {
      final list = await broker.getBrokerAppointments(brokerId);
      if (!mounted || generation != _loadGeneration) return;

      // اجلب العروض المرتبطة، مع إبقاء فشل الإثراء منفصلاً عن فشل المواعيد.
      final offIds = list.map((a) => a.offId).where((e) => e.isNotEmpty).toSet();
      if (offIds.isNotEmpty) {
        try {
          final offData = await SupabaseService()
              .client
              .from(DbTables.offers)
              .select(kOfferPublicColumns)
              .inFilter('id', offIds.toList());
          if (!mounted || generation != _loadGeneration) return;
          for (final o in offData as List) {
            final m = Map<String, dynamic>.from(o as Map);
            final id = m['id']?.toString();
            if (id != null && id.isNotEmpty) {
              _offers[id] = OfferModel.fromSupabase(m, id);
            }
          }
        } catch (_) {
          // يبقى الموعد قابلاً للإدارة حتى لو تعذر إثراء بيانات العرض.
        }
      }

      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل طلبات المعاينة. تحقق من الاتصال وحاول مرة أخرى.';
      });
    }
  }

  List<AppointmentModel> _byStatus(int s) =>
      s == -1 ? _all : _all.where((a) => a.sts == s).toList();

  Future<void> _accept(AppointmentModel a) async {
    if (_busyAppointments.contains(a.id)) return;
    setState(() => _busyAppointments.add(a.id));
    final broker = context.read<BrokerProvider>();
    final brokerUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final ok = await broker.handleAppointment(brokerUid, a.id, 1);
    if (!mounted) return;
    setState(() => _busyAppointments.remove(a.id));
    if (ok) {
      _snack('✅ تم قبول الموعد');
      _load();
    } else {
      _snack('فشل القبول');
    }
  }

  Future<void> _reject(AppointmentModel a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('رفض الموعد',
            style: TextStyle(color: AppTheme.textWhite)),
        content: const Text('هل أنت متأكد من رفض هذا الموعد؟',
            style: TextStyle(color: AppTheme.textGrey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child:
                const Text('رفض', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (_busyAppointments.contains(a.id)) return;
    setState(() => _busyAppointments.add(a.id));
    final broker = context.read<BrokerProvider>();
    final brokerUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final ok = await broker.handleAppointment(brokerUid, a.id, 2);
    if (!mounted) return;
    setState(() => _busyAppointments.remove(a.id));
    if (ok) {
      _snack('تم رفض الموعد');
      _load();
    } else {
      _snack('فشل الرفض');
    }
  }

  Future<void> _complete(AppointmentModel a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('إكمال المعاينة',
            style: TextStyle(color: AppTheme.textWhite)),
        content: const Text(
          'هل تم تنفيذ المعاينة فعلياً؟\nسيتم تسجيلها كمعاينة مكتملة (يمكن لاحقاً تسجيل صفقة منها).',
          style: TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('إكمال',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (_busyAppointments.contains(a.id)) return;
    setState(() => _busyAppointments.add(a.id));
    final broker = context.read<BrokerProvider>();
    final brokerUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final ok = await broker.completeAppointment(brokerUid, a.id);
    if (!mounted) return;
    setState(() => _busyAppointments.remove(a.id));
    if (ok) {
      _snack('✅ تم تسجيل المعاينة كمكتملة');
      _load();
    } else {
      _snack('فشل الإكمال');
    }
  }

  // ignore: unused_element
  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ignore: unused_element
  Future<void> _whatsapp(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _snack(String m) =>
      AppTheme.showSnackBar(context, SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 2),
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('طلبات المعاينة'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: AppTheme.primaryGold,
          labelColor: AppTheme.primaryGold,
          unselectedLabelColor: AppTheme.textGrey,
          tabs: _tabs
              .map((t) => Tab(text: '${t.$1} (${_byStatus(t.$2).length})'))
              .toList(),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : _error != null && _all.isEmpty
              ? _errorState()
              : TabBarView(
                  controller: _tab,
                  children: _tabs.map((t) => _list(_byStatus(t.$2))).toList(),
                ),
    );
  }

  Widget _errorState() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppTheme.errorRed),
            AppTheme.gapHeightLarge,
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.textGrey)),
            AppTheme.gapHeightMedium,
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );

  Widget _list(List<AppointmentModel> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_busy,
                size: 80, color: Color.fromRGBO(212, 175, 55, 0.5)),
            AppTheme.gapHeightXL,
            const Text('لا توجد طلبات في هذه الفئة',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppTheme.primaryGold,
      onRefresh: _load,
      child: ListView.builder(
        padding: AppTheme.paddingAllMedium,
        itemCount: items.length,
        itemBuilder: (_, i) => _card(items[i]),
      ),
    );
  }

  Widget _card(AppointmentModel a) {
    final offer = _offers[a.offId];
    final status = _statusInfo(a.sts);
    final isPending = a.sts == 0;
    final isAccepted = a.sts == 1;
    final isBusy = _busyAppointments.contains(a.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: status.$2.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // شريط الحالة
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: status.$2.withOpacity(0.15),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Icon(status.$3, color: status.$2, size: 16),
                const SizedBox(width: 6),
                Text(status.$1,
                    style: TextStyle(
                        color: status.$2,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontSizeSmall)),
                const Spacer(),
                Text(
                  '${a.dt.day}/${a.dt.month}/${a.dt.year} - ${a.dt.hour.toString().padLeft(2, '0')}:${a.dt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                      color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                ),
              ],
            ),
          ),

          Padding(
            padding: AppTheme.paddingAllMedium,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // العرض
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: AppTheme.radiusSmall,
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: (offer?.imgs.isNotEmpty == true)
                            ? Image.network(offer!.imgs.first.toString(),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    _imgPlaceholder())
                            : _imgPlaceholder(),
                      ),
                    ),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            offer?.ttl ?? 'عرض رقم #${offer?.offerNumber ?? 0}',
                            style: const TextStyle(
                                color: AppTheme.textWhite,
                                fontWeight: FontWeight.bold,
                                fontSize: AppTheme.fontSizeMedium),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (offer != null)
                            Text(
                              '${offer.prc.toStringAsFixed(0)} ${offer.cur == 0 ? '\$' : 'ل.س'} • ${(offer.loc['d'] ?? '').toString()}',
                              style: const TextStyle(
                                  color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
                            ),
                        ],
                      ),
                    ),
                    if (offer != null)
                      IconButton(
                        icon: const Icon(Icons.open_in_new,
                            color: AppTheme.primaryGold, size: 18),
                        onPressed: () => context.push('/offer/${offer.id}'),
                      ),
                  ],
                ),

                const Divider(color: AppTheme.textGrey, height: 18),

                // القاعدة الذهبية: لا تظهر أي معلومة عن طالب الحجز
                // التواصل يتم فقط عبر إدارة المكتب
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGold.withOpacity(0.07),
                    borderRadius: AppTheme.radiusSmall,
                    border: Border.all(
                        color: AppTheme.primaryGold.withOpacity(0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.business_center,
                        color: AppTheme.primaryGold, size: 16),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: Text(
                        'يوجد طلب حجز موعد — التواصل مع الطالب يتم عبر إدارة المكتب حصراً.',
                        style: TextStyle(
                            color: AppTheme.primaryGold,
                            fontSize: AppTheme.fontSizeSmall,
                            height: 1.4),
                      ),
                    ),
                  ]),
                ),

                // ملاحظة الإلغاء
                if (a.cnlRsn != null && a.cnlRsn!.isNotEmpty) ...[
                  AppTheme.gapHeightSmall,
                  Container(
                    padding: AppTheme.paddingAllSmall,
                    decoration: BoxDecoration(
                      color: const Color.fromRGBO(255, 0, 0, 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppTheme.errorRed, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'سبب الإلغاء: ${a.cnlRsn}',
                            style: const TextStyle(
                                color: AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // أزرار الإجراءات
          if (isPending)
            _actionRow([
              _actionBtn('رفض', Icons.close, AppTheme.errorRed,
                  isBusy ? () {} : () => _reject(a)),
              _actionBtn(
                  'قبول', Icons.check, AppTheme.successGreen,
                  isBusy ? () {} : () => _accept(a)),
            ])
          else if (isAccepted)
            _actionRow([
              _actionBtn('إكمال المعاينة', Icons.done_all, Colors.teal,
                  isBusy ? () {} : () => _complete(a)),
            ]),
        ],
      ),
    );
  }

  Widget _actionRow(List<Widget> children) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.deepBlack)),
      ),
      child: Row(
        children: children
            .expand((w) => [
                  Expanded(child: w),
                  if (w != children.last)
                    Container(
                        width: 1, height: 36, color: AppTheme.deepBlack),
                ])
            .toList(),
      ),
    );
  }

  Widget _actionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, color: color),
      label: Text(label,
          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }

  Widget _imgPlaceholder() => const OfficeLogoPlaceholder(logoSize: 24);

  (String, Color, IconData) _statusInfo(int s) {
    switch (s) {
      case 0:
        return ('قيد الانتظار', AppTheme.warningOrange, Icons.hourglass_empty);
      case 1:
        return ('مؤكد', AppTheme.successGreen, Icons.check_circle);
      case 2:
        return ('مكتمل', Colors.teal, Icons.done_all);
      case 3:
        return ('ملغي', AppTheme.textGrey, Icons.block);
      case 4:
        return ('مرفوض', AppTheme.errorRed, Icons.cancel);
      case 5:
        return ('لم يتم الحضور', Colors.deepOrange, Icons.person_off);
      default:
        return ('غير معروف', AppTheme.textGrey, Icons.help);
    }
  }
}
