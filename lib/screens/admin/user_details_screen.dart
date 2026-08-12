import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/user_model.dart';
import '../../models/offer_model.dart';
import '../../models/appointment_model.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';

/// شاشة تفاصيل المستخدم للإدارة
/// تعرض: بياناته + إحصائياته + عروضه + مواعيده + التبليغات عليه + إجراءات سريعة
/// تستخدم Edge Function (service_role) لتخطي RLS
class UserDetailsScreen extends StatefulWidget {
  final String userId;
  const UserDetailsScreen({super.key, required this.userId});

  @override
  State<UserDetailsScreen> createState() => _UserDetailsScreenState();
}

class _UserDetailsScreenState extends State<UserDetailsScreen>
    with SingleTickerProviderStateMixin {
  UserModel? _user;
  List<OfferModel> _offers = [];
  List<AppointmentModel> _appointments = [];
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _activity = [];
  bool _loading = true;
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
      final response = await SupabaseService().invokeFunction(
        'admin-dashboard',
        body: {
          'action': 'admin_user_details',
          'admin_uid': adminUid,
          'target_uid': widget.userId,
        },
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data)
          : null;
      if (data == null || data['success'] != true) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // بيانات المستخدم
      final userRow = data['user'];
      if (userRow is Map) {
        _user = UserModel.fromSupabase(
            Map<String, dynamic>.from(userRow), widget.userId);
      }

      // العروض
      final offersList = data['offers'];
      if (offersList is List) {
        _offers = offersList
            .map((d) => OfferModel.fromSupabase(
                Map<String, dynamic>.from(d as Map), d['id'] as String))
            .toList();
      }

      // المواعيد
      final apptList = data['appointments'];
      if (apptList is List) {
        _appointments = apptList
            .map((d) => AppointmentModel.fromSupabase(
                Map<String, dynamic>.from(d as Map), d['id'] as String))
            .toList();
      }

      // التبليغات
      final repList = data['reports'];
      if (repList is List) {
        _reports = repList
            .map((d) => Map<String, dynamic>.from(d as Map))
            .toList();
      }

      // النشاط
      final actList = data['activity'];
      if (actList is List) {
        _activity = actList
            .map((d) => Map<String, dynamic>.from(d as Map))
            .toList();
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _callUser() async {
    if (_user == null || _user!.ph.isEmpty) return;
    final uri = Uri.parse('tel:${_user!.ph}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsappUser() async {
    if (_user == null || _user!.ph.isEmpty) return;
    final clean = _user!.ph.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('https://wa.me/$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _changeStatus(int status) async {
    final adminId = context.read<AuthProvider>().userModel?.uid ?? '';
    String? reason;
    if (status != 0) {
      final ctrl = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: Text(
            status == 1 ? 'تجميد الحساب' : 'حظر الحساب',
            style: const TextStyle(color: AppTheme.textWhite),
          ),
          content: TextField(
            controller: ctrl,
            style: const TextStyle(color: AppTheme.textWhite),
            decoration: const InputDecoration(hintText: 'السبب'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      );
      if (reason == null) return;
    }

    if (!mounted) return;
    final admin = context.read<AdminProvider>();
    final ok = await admin.setUserStatus(
      adminId,
      widget.userId,
      status,
      reason: reason ?? '',
    );
    if (ok && mounted) {
      _snack('✅ تم تحديث الحالة');
      _load();
    }
  }

  Future<void> _changeRole(int newRole) async {
    final auth = context.read<AuthProvider>();
    final adminId = auth.userModel?.uid ?? '';
    final admin = context.read<AdminProvider>();
    final ok = await admin.updateUserRole(adminId, widget.userId, newRole);
    if (ok && mounted) {
      _snack('✅ تم تحديث الدور');
      _load();
    }
  }

  void _snack(String m) =>
      AppTheme.showSnackBar(context, SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryGold)),
      );
    }
    if (_user == null) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        appBar: AppBar(title: const Text('تفاصيل المستخدم')),
        body: const Center(
            child: Text('المستخدم غير موجود',
                style: TextStyle(color: AppTheme.textGrey))),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            backgroundColor: AppTheme.surfaceBlack,
            expandedHeight: 220,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: _header(),
            ),
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              indicatorColor: AppTheme.primaryGold,
              labelColor: AppTheme.primaryGold,
              unselectedLabelColor: AppTheme.textGrey,
              tabs: [
                Tab(text: 'العروض (${_offers.length})'),
                Tab(text: 'المواعيد (${_appointments.length})'),
                Tab(text: 'التبليغات (${_reports.length})'),
                Tab(text: 'النشاط (${_activity.length})'),
              ],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tab,
          children: [
            _offersTab(),
            _appointmentsTab(),
            _reportsTab(),
            _activityTab(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final u = _user!;
    final statusInfo = _statusInfo(u.sts);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1E1E1E), AppTheme.deepBlack],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppTheme.primaryGold,
                child: Text(
                  u.nm.isNotEmpty ? u.nm[0].toUpperCase() : '؟',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: AppTheme.fontSizeLarge,
                      fontWeight: FontWeight.bold),
                ),
              ),
              AppTheme.gapWidthMedium,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u.nm.isEmpty ? 'مستخدم بدون اسم' : u.nm,
                      style: const TextStyle(
                          color: AppTheme.textWhite,
                          fontSize: AppTheme.fontSizeTitle,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(AppUtils.displayPhone(u.ph),
                        style: const TextStyle(
                            color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
                    if (u.eml?.isNotEmpty == true)
                      Text(u.eml!,
                          style: const TextStyle(
                              color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                  ],
                ),
              ),
              if (u.ph.isNotEmpty) ...[
                IconButton(
                  icon: const Icon(Icons.phone, color: AppTheme.successGreen),
                  onPressed: _callUser,
                ),
                IconButton(
                  icon: const Icon(Icons.chat, color: AppTheme.primaryGold),
                  onPressed: _whatsappUser,
                ),
              ],
            ],
          ),
          AppTheme.gapHeightSmall,
          // شارات
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip(statusInfo.$1, statusInfo.$2),
            _chip(u.roleName, AppTheme.primaryGold),
            _chip('⭐ ${u.pt}', Colors.amber),
            if (u.isVerifiedOfficial)
              _chip('✓ موثق رسمياً', AppTheme.successGreen)
            else if (u.vrf == 1)
              _chip('⏳ توثيق قيد المراجعة', AppTheme.warningOrange)
            else
              _chip('غير موثق', AppTheme.textGrey),
          ]),
          AppTheme.gapHeightSmall,
          _quickActions(),
        ],
      ),
    );
  }

  Widget _quickActions() {
    final u = _user!;
    return Row(children: [
      if (u.sts == 0) ...[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _changeStatus(1),
            icon: const Icon(Icons.pause_circle, color: AppTheme.warningOrange, size: 14),
            label: const Text('تجميد',
                style: TextStyle(color: AppTheme.warningOrange, fontSize: AppTheme.fontSizeCaption)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.warningOrange),
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _changeStatus(2),
            icon: const Icon(Icons.block, color: AppTheme.errorRed, size: 14),
            label: const Text('حظر',
                style: TextStyle(color: AppTheme.errorRed, fontSize: AppTheme.fontSizeCaption)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.errorRed),
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
      ] else
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _changeStatus(0),
            icon: const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 14),
            label: const Text('تفعيل',
                style: TextStyle(color: AppTheme.successGreen, fontSize: AppTheme.fontSizeCaption)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppTheme.successGreen),
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
          ),
        ),
      const SizedBox(width: 6),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _showRoleDialog(),
          icon: const Icon(Icons.swap_horiz,
              color: AppTheme.primaryGold, size: 14),
          label: const Text('الدور',
              style: TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeCaption)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppTheme.primaryGold),
            padding: const EdgeInsets.symmetric(vertical: 6),
          ),
        ),
      ),
    ]);
  }

  void _showRoleDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تغيير الدور',
            style: TextStyle(color: AppTheme.textWhite)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(UserRole.count, (i) {
            return ListTile(
              leading: const Icon(Icons.person, color: AppTheme.primaryGold),
              title: Text(UserRole.nameOf(i),
                  style: const TextStyle(color: AppTheme.textWhite)),
              selected: _user!.role == i,
              onTap: () {
                Navigator.pop(context);
                _changeRole(i);
              },
            );
          }),
        ),
      ),
    );
  }

  Widget _offersTab() {
    if (_offers.isEmpty) {
      return const Center(
          child: Text('لا توجد عروض',
              style: TextStyle(color: AppTheme.textGrey)));
    }
    return ListView.builder(
      padding: AppTheme.paddingAllMedium,
      itemCount: _offers.length,
      itemBuilder: (_, i) {
        final o = _offers[i];
        return Card(
          color: AppTheme.surfaceBlack,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: AppTheme.radiusSmall,
              child: SizedBox(
                width: 50,
                height: 50,
                child: o.imgs.isNotEmpty
                    ? Image.network(o.imgs.first,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.image, color: AppTheme.textGrey))
                    : const Icon(Icons.image, color: AppTheme.textGrey),
              ),
            ),
            title: Text(o.ttl,
                style: const TextStyle(color: AppTheme.textWhite),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            subtitle: Text(
              '${o.prc.toStringAsFixed(0)} ${o.cur == 0 ? '\$' : 'ل.س'} • ${_offerStatusText(o.sts)}',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
            ),
            trailing: const Icon(Icons.chevron_left, color: AppTheme.primaryGold),
            onTap: () => context.push('/offer/${o.id}'),
          ),
        );
      },
    );
  }

  Widget _appointmentsTab() {
    if (_appointments.isEmpty) {
      return const Center(
          child: Text('لا توجد مواعيد',
              style: TextStyle(color: AppTheme.textGrey)));
    }
    return ListView.builder(
      padding: AppTheme.paddingAllMedium,
      itemCount: _appointments.length,
      itemBuilder: (_, i) {
        final a = _appointments[i];
        return Card(
          color: AppTheme.surfaceBlack,
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.event, color: AppTheme.primaryGold),
            title: Text('موعد #${a.id.substring(0, 6)}',
                style: const TextStyle(color: AppTheme.textWhite)),
            subtitle: Text(
              '${a.dt.year}/${a.dt.month}/${a.dt.day} ${a.dt.hour}:${a.dt.minute.toString().padLeft(2, '0')} • ${_apptStatusText(a.sts)}',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
            ),
          ),
        );
      },
    );
  }

  Widget _reportsTab() {
    if (_reports.isEmpty) {
      return const Center(
          child: Text('لا توجد تبليغات عليه ✅',
              style: TextStyle(color: AppTheme.successGreen)));
    }
    return ListView.builder(
      padding: AppTheme.paddingAllMedium,
      itemCount: _reports.length,
      itemBuilder: (_, i) {
        final r = _reports[i];
        return Card(
          color: AppTheme.errorRed.withOpacity(0.1),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(Icons.flag, color: AppTheme.errorRed),
            title: Text('تبليغ #${r['id'].toString().substring(0, 6)}',
                style: const TextStyle(color: AppTheme.textWhite)),
            subtitle: Text(
              '${r['det'] ?? 'بدون تفاصيل'}',
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(
              AppUtils.formatTimestamp(r['ts_crt']),
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeXS),
            ),
          ),
        );
      },
    );
  }

  Widget _activityTab() {
    if (_activity.isEmpty) {
      return const Center(
          child: Text('لا نشاط حديث',
              style: TextStyle(color: AppTheme.textGrey)));
    }
    return ListView.builder(
      padding: AppTheme.paddingAllMedium,
      itemCount: _activity.length,
      itemBuilder: (_, i) {
        final a = _activity[i];
        return Card(
          color: AppTheme.surfaceBlack,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: const Icon(Icons.history, color: AppTheme.primaryGold, size: 18),
            title: Text(
                a['det']?.toString().isNotEmpty == true
                    ? a['det'].toString()
                    : (a['action']?.toString() ?? (a['act'] != null ? 'إجراء رقم ${a['act']}' : '—')),
                style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
            subtitle: Text(
              AppUtils.formatTimestamp(a['ts_crt']),
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeXS),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: AppTheme.radiusSmall,
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
    );
  }

  (String, Color) _statusInfo(int s) {
    switch (s) {
      case 0:
        return ('نشط', AppTheme.successGreen);
      case 1:
        return ('مجمّد', AppTheme.warningOrange);
      case 2:
        return ('محظور', AppTheme.errorRed);
      default:
        return ('غير معروف', AppTheme.textGrey);
    }
  }

  String _offerStatusText(int s) {
    const m = {
      0: 'مسودة',
      1: 'قيد المراجعة',
      2: 'منشور',
      3: 'مرفوض',
      4: 'منتهي',
      5: 'محجوز',
      6: 'مكتمل',
    };
    return m[s] ?? 'غير معروف';
  }

  String _apptStatusText(int s) {
    const m = {
      0: 'قيد الانتظار',
      1: 'مؤكد',
      2: 'مكتمل',
      3: 'ملغي',
      4: 'مرفوض',
      5: 'لم يحضر',
    };
    return m[s] ?? 'غير معروف';
  }
}
