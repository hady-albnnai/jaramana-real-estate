import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/constants/db_constants.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../core/utils/app_utils.dart';
import '../../models/user_model.dart';

/// شاشة معلومات الحساب + التوثيق الرسمي
/// نُقلت من الملف الشخصي لتكون شاشة مستقلة وأنظف
class AccountInfoScreen extends StatelessWidget {
  const AccountInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.userModel;

    if (user == null) {
      return const Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: Center(
            child: Text('جاري التحميل...',
                style: TextStyle(color: AppTheme.textGrey))),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        title: const Text('معلومات الحساب',
            style: TextStyle(
                color: AppTheme.primaryGold, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppTheme.primaryGold, size: 20),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: AppTheme.paddingAllXL,
        child: Column(
          children: [
            // ─── معلومات الحساب ───
            _buildInfoCard(user, context),

            // ─── بطاقة «باقتي» (مخفية للموظفين الداخليين) ───
            if (!user.isInternal) ...[
              AppTheme.gapHeightLarge,
              _buildPackageCard(user, context),
            ],

            if (user.isLawyer || user.isExpediter) ...[
              AppTheme.gapHeightLarge,
              _buildLegalRoleDetailsCard(user),
            ],

            AppTheme.gapHeightLarge,

            // ─── حالة التوثيق (مخفي للموظفين الداخليين) ───
            if (!user.isInternal) ...[
              _buildVerificationCard(user, context),
              AppTheme.gapHeightLarge,
            ],

            // ─── تغيير كلمة المرور ───
            _buildPasswordSection(user, context),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(UserModel user, BuildContext context) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(
            color: AppTheme.primaryGold.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  color: AppTheme.primaryGold.withOpacity(0.8),
                  size: 18),
              AppTheme.gapWidthSmall,
              const Text(
                'بيانات الحساب',
                style: TextStyle(
                  color: AppTheme.primaryGold,
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          AppTheme.gapHeightMedium,
          _infoRow(
              Icons.phone_android_outlined, 'الهاتف', AppUtils.displayPhone(user.ph), context),
          _infoRow(Icons.person_outline_rounded, 'الاسم',
              user.nm.isEmpty ? 'غير محدد' : user.nm, context),
          if (user.usr != null && user.usr!.isNotEmpty)
            _infoRow(Icons.alternate_email, 'اسم المستخدم',
                '@${user.usr}', context),
          _infoRow(Icons.location_on_outlined, 'العنوان',
              user.ad.isEmpty ? 'غير محدد' : user.ad, context),
          _infoRow(Icons.badge_outlined, 'الرقم الوطني',
              user.sid.isEmpty ? 'غير مكتمل' : user.sid, context),
          _infoRow(
              Icons.credit_card_outlined,
              user.isInternal ? 'صور الهوية' : 'صورة الهوية',
              _identityImagesText(user),
              context),
          _infoRow(Icons.calendar_today_outlined, 'تاريخ التسجيل',
              AppUtils.formatTimestamp(user.tsCrt), context),

        ],
      ),
    );
  }

  List<String> _parseIdentityImages(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const [];
    if (value.startsWith('[')) {
      try {
        final parsed = jsonDecode(value);
        if (parsed is List) {
          return parsed.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {
        // fallback below
      }
    }
    return [value];
  }

  String _identityImagesText(UserModel user) {
    final count = _parseIdentityImages(user.img).length;
    if (count <= 0) return 'غير مرفوعة';
    if (user.isInternal) return 'محفوظة بشكل خاص ($count/2)';
    return 'مرفوعة بشكل خاص';
  }

  Future<Map<String, dynamic>?> _fetchLawyerProfile(UserModel user) async {
    final res = await SupabaseService().invokeFunction(
      'legal-actions',
      body: {'action': 'get_lawyer_profile', 'user_uid': user.uid},
    );
    final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
    if (data == null || data['success'] != true || data['profile'] is! Map) return null;
    return Map<String, dynamic>.from(data['profile'] as Map);
  }

  Future<List<dynamic>> _fetchExpediterTasks(UserModel user) async {
    final res = await SupabaseService().invokeFunction(
      'legal-actions',
      body: {'action': 'get_my_expediting_tasks', 'user_uid': user.uid},
    );
    final data = res.data is Map ? Map<String, dynamic>.from(res.data) : null;
    if (data == null || data['success'] != true || data['tasks'] is! List) return const [];
    return data['tasks'] as List;
  }

  Widget _buildLegalRoleDetailsCard(UserModel user) {
    if (user.isLawyer) {
      return FutureBuilder<Map<String, dynamic>?>(
        future: _fetchLawyerProfile(user),
        builder: (context, snapshot) {
          final profile = snapshot.data;
          final found = profile != null && profile['found'] == true;
          return _roleDetailsContainer(
            title: 'تفاصيل المحامي المختص',
            icon: Icons.gavel_rounded,
            children: [
              _infoRow(Icons.work_outline, 'القسم', 'القسم القانوني والاستشارات', context),
              _infoRow(Icons.verified_user_outlined, 'التوثيق', user.vrf == 2 ? 'موثق وظيفياً' : 'ينتظر استكمال التوثيق الوظيفي', context),
              _infoRow(Icons.credit_card, 'صور الهوية', _identityImagesText(user), context),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(color: AppTheme.primaryGold),
                )
              else ...[
                _infoRow(Icons.phone_android, 'واتساب', found ? (profile['whatsapp_phone']?.toString() ?? '') : 'غير معد بعد', context),
                _infoRow(Icons.location_on_outlined, 'عنوان المكتب', found ? (profile['office_address']?.toString() ?? '') : 'غير محدد', context),
                _infoRow(Icons.balance_outlined, 'الاختصاص', found ? (profile['specialization']?.toString() ?? '') : 'عقارات وسيارات', context),
                _infoRow(Icons.toggle_on_outlined, 'حالة الملف', found && profile['is_active'] == true ? 'نشط' : 'يحتاج إعداد رقم الواتساب', context),
              ],
            ],
          );
        },
      );
    }

    return FutureBuilder<List<dynamic>>(
      future: _fetchExpediterTasks(user),
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? const [];
        final pending = tasks.where((t) => t is Map && (t['status'] == 0 || t['status'] == 1)).length;
        final done = tasks.where((t) => t is Map && (t['status'] == 2 || t['status'] == 3)).length;
        return _roleDetailsContainer(
          title: 'تفاصيل معقب المعاملات',
          icon: Icons.assignment_turned_in_outlined,
          children: [
            _infoRow(Icons.work_outline, 'القسم', 'تعقيب المعاملات الميدانية', context),
            _infoRow(Icons.verified_user_outlined, 'التوثيق', user.vrf == 2 ? 'موثق وظيفياً' : 'ينتظر استكمال التوثيق الوظيفي', context),
            _infoRow(Icons.credit_card, 'صور الهوية', _identityImagesText(user), context),
            if (snapshot.connectionState == ConnectionState.waiting)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(color: AppTheme.primaryGold),
              )
            else ...[
              _infoRow(Icons.pending_actions, 'مهام قيد العمل', '$pending', context),
              _infoRow(Icons.task_alt, 'مهام منتهية', '$done', context),
              _infoRow(Icons.list_alt, 'إجمالي المهام', '${tasks.length}', context),
            ],
          ],
        );
      },
    );
  }

  Widget _roleDetailsContainer({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.primaryGold, size: 20),
              AppTheme.gapWidthSmall,
              Text(
                title,
                style: const TextStyle(
                  color: AppTheme.primaryGold,
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          AppTheme.gapHeightMedium,
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(
      IconData icon, String label, String value, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon,
              color: AppTheme.primaryGold.withOpacity(0.6), size: 18),
          AppTheme.gapWidthSmall,
          Text(
            label,
            style: TextStyle(
              color: AppTheme.textGrey.withOpacity(0.7),
              fontSize: AppTheme.fontSizeBody,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.textWhite,
                fontSize: AppTheme.fontSizeBody,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.left,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  بطاقة «باقتي» — الاسم من إعدادات السيرفر، الحصة المستهلكة، زر الترقية
  // ═══════════════════════════════════════════════════════════════
  int _pkgLimit(UserModel user, Map<String, dynamic> pkgMap, bool pkgLive) {
    if (pkgLive) {
      final p = pkgMap['${user.bPkg}'];
      final o = p is Map ? p['o'] : null;
      return o is int ? o : int.tryParse('$o') ?? 5;
    }
    // مرآة منطق create_offer_internal: الوسيط 5 عروض، غيره مجاني من الإعدادات
    if (user.role == 1) return 5;
    final p0 = pkgMap['0'];
    final o0 = p0 is Map ? p0['o'] : null;
    return o0 is int ? o0 : int.tryParse('$o0') ?? 1;
  }

  Future<int> _countActiveOffers(String uid) async {
    final rows = await SupabaseService()
        .client
        .from(DbTables.offers)
        .select('id')
        .eq('usr_id', uid)
        .eq('i_del', 0)
        .inFilter('sts', [0, 1, 2, 5]);
    return (rows as List).length;
  }

  Widget _buildPackageCard(UserModel user, BuildContext context) {
    final config = Provider.of<ConfigProvider>(context).config;
    final pkgMap = config?.packages ?? const <String, dynamic>{};
    final pkgLive =
        user.bPkg > 0 && (user.isPkgActive || user.isInGracePeriod);
    final entry = pkgMap['${user.bPkg}'];
    final pkgName = (entry is Map ? entry['nm'] : null)?.toString() ??
        (user.bPkg == 0 ? 'مجاني' : 'باقة ${user.bPkg}');

    String statusLabel;
    Color statusColor;
    if (user.bPkg == 0) {
      statusLabel = 'مجانية';
      statusColor = AppTheme.textGrey;
    } else if (user.isPkgActive) {
      statusLabel = 'فعّالة';
      statusColor = AppTheme.successGreen;
    } else if (user.isInGracePeriod) {
      statusLabel = 'سماح ${user.graceDaysLeft} يوم';
      statusColor = AppTheme.warningOrange;
    } else {
      statusLabel = 'منتهية';
      statusColor = AppTheme.errorRed;
    }

    final limit = _pkgLimit(user, pkgMap, pkgLive);
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border:
            Border.all(color: AppTheme.primaryGold.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.workspace_premium_outlined,
                color: AppTheme.primaryGold.withOpacity(0.8), size: 18),
            AppTheme.gapWidthSmall,
            const Expanded(
              child: Text('باقتي',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.w600)),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: AppTheme.radiusSmall,
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      color: statusColor,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold)),
            ),
          ]),
          AppTheme.gapHeightSmall,
          Text(pkgName,
              style: const TextStyle(
                  color: AppTheme.textWhite,
                  fontSize: AppTheme.fontSizeSubtitle,
                  fontWeight: FontWeight.bold)),
          if (user.bPkg > 0 && user.pkgEnd != null) ...[
            AppTheme.gapHeightXS,
            Text(
              user.isPkgActive
                  ? 'تنتهي: ${AppUtils.formatTimestamp(user.pkgEnd!)}'
                  : user.isInGracePeriod
                      ? 'فترة السماح حتى: ${AppUtils.formatTimestamp(user.pkgGrace!)}'
                      : 'انتهت بتاريخ: ${AppUtils.formatTimestamp(user.pkgEnd!)}',
              style:
                  const TextStyle(color: AppTheme.textGrey, fontSize: 11.5),
            ),
          ],
          AppTheme.gapHeightMedium,
          FutureBuilder<int>(
            future: _countActiveOffers(user.uid),
            builder: (ctx, snap) {
              final used = snap.data ?? 0;
              final lim = limit <= 0 ? 1 : limit;
              final ratio = (used / lim).clamp(0.0, 1.0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('عروضك الفعّالة: $used / $limit',
                      style: const TextStyle(
                          color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: AppTheme.radiusXS,
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation(
                          ratio >= 1.0
                              ? AppTheme.errorRed
                              : AppTheme.primaryGold),
                    ),
                  ),
                ],
              );
            },
          ),
          AppTheme.gapHeightMedium,
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/user/packages'),
              icon: const Icon(Icons.upgrade_rounded, size: 18),
              label: Text(
                  user.bPkg > 0 ? 'تغيير / تجديد الباقة' : 'ترقية الباقة',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold,
                foregroundColor: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  بطاقة التوثيق
  // ═══════════════════════════════════════════════════════════════

  Widget _buildVerificationCard(UserModel user, BuildContext context) {
    final vrf = user.vrf;

    late final Color color;
    late final IconData icon;
    late final String title;
    late final String subtitle;
    late final bool showAction;

    switch (vrf) {
      case 2:
        color = AppTheme.successGreen;
        icon = Icons.verified_rounded;
        title = 'حسابك موثق رسمياً';
        subtitle = 'تظهر شارة التوثيق في جميع عروضك أمام العملاء.';
        showAction = false;
        break;
      case 1:
        color = AppTheme.warningOrange;
        icon = Icons.hourglass_top_rounded;
        title = 'طلبك قيد المراجعة';
        subtitle = 'الإدارة تراجع وثائقك حالياً. ستصلك إشعار بالنتيجة.';
        showAction = false;
        break;
      default:
        color = AppTheme.textGrey;
        icon = Icons.shield_outlined;
        title = 'حسابك غير موثق';
        subtitle =
            'الحسابات الموثقة تحظى بثقة أكبر. ارفع هويتك واطلب التوثيق.';
        showAction = true;
    }

    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: AppTheme.fontSizeMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          AppTheme.gapHeightSmall,
          Text(
            subtitle,
            style: const TextStyle(
              color: AppTheme.textGrey,
              fontSize: AppTheme.fontSizeSmall,
              height: 1.5,
            ),
          ),
          if (showAction) ...[
            AppTheme.gapHeightMedium,
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _requestVerification(context),
                icon: const Icon(Icons.verified_outlined,
                    color: AppTheme.deepBlack, size: 18),
                label: const Text(
                  'طلب التوثيق الرسمي',
                  style: TextStyle(
                    color: AppTheme.deepBlack,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontSizeBody,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: AppTheme.radiusMedium),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _requestVerification(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) return;

    // ✅ فحص البيانات المطلوبة فعلياً للتوثيق — مطابق لشرط السيرفر (رقم وطني + صورة هوية فقط)
    final missingFields = <String>[];
    if (user.sid.isEmpty) missingFields.add('الرقم الوطني');
    if (user.img.isEmpty) missingFields.add('صورة الهوية');

    if (missingFields.isNotEmpty) {
      // نظهر للمستخدم شو ناقص بالاسم بدل التوجيه الأصم الذي كان يضيّعه
      final goComplete = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          shape: RoundedRectangleBorder(
              borderRadius: AppTheme.radiusLarge),
          title: const Text('بيانات ناقصة',
              style: TextStyle(color: AppTheme.textWhite)),
          content: Text(
            'لإرسال طلب التوثيق أكمل أولاً:\n• ${missingFields.join('\n• ')}',
            style: const TextStyle(color: AppTheme.textGrey, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGold),
              child: const Text('استكمال البيانات',
                  style: TextStyle(color: AppTheme.deepBlack)),
            ),
          ],
        ),
      );
      if (goComplete == true && context.mounted) {
        // ✅ Fix for Bug #12: بعد العودة من setup-identity، نرسل طلب التوثيق تلقائياً
        final result = await context.push('/setup-identity');
        if (result == true && context.mounted) {
          // تم حفظ البيانات بنجاح، نرسل طلب التوثيق تلقائياً
          await _sendVerificationRequest(context);
        }
      }
      return;
    }

    // ✅ Fix for Bug #12: إرسال طلب التوثيق مباشرة
    await _sendVerificationRequest(context);
  }

  // ✅ Fix for Bug #12: فصل منطق إرسال طلب التوثيق ليتم استدعاؤه تلقائياً
  Future<void> _sendVerificationRequest(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
        title: const Text('طلب التوثيق الرسمي',
            style: TextStyle(color: AppTheme.textWhite)),
        content: const Text(
          'سيتم إرسال بياناتك للإدارة لمراجعتها واعتمادها. '
          'بعد الاعتماد ستحصل على شارة "موثق ✓" في كل عروضك.\n\nهل تريد المتابعة؟',
          style: TextStyle(color: AppTheme.textGrey, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold),
            child: const Text('إرسال الطلب',
                style: TextStyle(color: AppTheme.deepBlack)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // ✅ تعطيل الزر فوراً بتحديث vrf محلياً (optimistic update)
    // هذا يمنع المستخدم من الضغط مرة ثانية أثناء انتظار الاستجابة
    auth.setVerificationPending();

    try {
      // الإصلاح الجذري: الدالة تقرأ user_uid فقط — إرسال p_user_uid كان يُرفض صامتاً (USER_UID_REQUIRED)
      // والنجاح كان يُعرض زوراً لأن invokeFunction لا ترمي عند 4xx والرد لم يكن يُفحص أبداً
      final res = await SupabaseService().invokeFunction('user-account', body: {'action': 'request_verification', 'user_uid': user.uid});
      final body = res.data;
      if (body is! Map || body['success'] != true) {
        throw Exception((body is Map ? body['error'] : null)?.toString() ?? 'VERIFICATION_REQUEST_FAILED');
      }
      await auth.refreshUser();
      if (!context.mounted) return;
      AppTheme.showSnackBar(context,
        const SnackBar(
          content: Text('✅ تم إرسال طلب التوثيق، بانتظار مراجعة الإدارة'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      // ✅ إرجاع الحالة عند الفشل
      auth.setVerificationReverted();
      final msg = e.toString();
      String userMsg = '❌ فشل إرسال الطلب';
      if (msg.contains('ALREADY_VERIFIED')) {
        userMsg = 'حسابك موثق بالفعل';
      } else if (msg.contains('ALREADY_PENDING')) {
        userMsg = 'طلبك السابق قيد المراجعة';
      } else if (msg.contains('MISSING_DOCUMENTS')) {
        userMsg = 'يجب رفع صورة الهوية + الرقم الوطني أولاً';
      }
      AppTheme.showSnackBar(context,
        SnackBar(content: Text(userMsg), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  تغيير كلمة المرور
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPasswordSection(UserModel user, BuildContext context) {
    final hasPassword = user.pwd != null && user.pwd!.isNotEmpty;

    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded,
                  color: AppTheme.primaryGold.withOpacity(0.8),
                  size: 18),
              AppTheme.gapWidthSmall,
              const Text(
                'كلمة المرور',
                style: TextStyle(
                  color: AppTheme.primaryGold,
                  fontSize: AppTheme.fontSizeMedium,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          AppTheme.gapHeightSmall,
          Text(
            hasPassword
                ? 'كلمة المرور مُعيّنة — يمكنك تغييرها'
                : 'لم يتم تعيين كلمة مرور بعد',
            style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
          ),
          AppTheme.gapHeightSmall,
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showChangePasswordDialog(context, hasPassword),
              icon: Icon(
                hasPassword ? Icons.edit_outlined : Icons.add_outlined,
                color: AppTheme.primaryGold,
                size: 18,
              ),
              label: Text(
                hasPassword ? 'تغيير كلمة المرور' : 'تعيين كلمة مرور',
                style: const TextStyle(
                    color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: AppTheme.primaryGold.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: AppTheme.radiusMedium),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, bool hasOld) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        shape: RoundedRectangleBorder(borderRadius: AppTheme.radiusLarge),
        title: Text(
          hasOld ? 'تغيير كلمة المرور' : 'تعيين كلمة مرور',
          style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasOld)
                TextField(
                  controller: oldCtrl,
                  obscureText: true,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور الحالية',
                    prefixIcon:
                        Icon(Icons.lock_outline, color: AppTheme.primaryGold),
                  ),
                ),
              if (hasOld) AppTheme.gapHeightMedium,
              TextField(
                controller: newCtrl,
                obscureText: true,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  prefixIcon:
                      Icon(Icons.lock_rounded, color: AppTheme.primaryGold),
                ),
              ),
              AppTheme.gapHeightMedium,
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                style: const TextStyle(color: AppTheme.textWhite),
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  prefixIcon:
                      Icon(Icons.lock_rounded, color: AppTheme.primaryGold),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newCtrl.text.length < 8) {
                AppTheme.showSnackBar(context,
                  const SnackBar(
                      content: Text('كلمة المرور يجب أن تكون 8 أحرف على الأقل')),
                );
                return;
              }
              if (newCtrl.text != confirmCtrl.text) {
                AppTheme.showSnackBar(context,
                  const SnackBar(content: Text('كلمتا المرور غير متطابقتين')),
                );
                return;
              }

              Navigator.pop(ctx);
              try {
                final auth = context.read<AuthProvider>();
                final user = auth.userModel!;

                if (hasOld) {
                  await SupabaseService().invokeFunction('user-account', body: {
                    'action': 'change_password',
                    'user_uid': user.uid,
                    'old_password': oldCtrl.text,
                    'new_password': newCtrl.text,
                  });
                } else {
                  await SupabaseService().invokeFunction('user-account', body: {
                    'action': 'register_password',
                    'user_uid': user.uid,
                    'username': user.usr ?? user.ph,
                    'password': newCtrl.text,
                  });
                }

                await auth.refreshUser();
                if (context.mounted) {
                  AppTheme.showSnackBar(context,
                    const SnackBar(
                        content: Text('✅ تم تحديث كلمة المرور'),
                        backgroundColor: AppTheme.successGreen),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  final msg = e.toString();
                  String userMsg = 'فشل التحديث';
                  if (msg.contains('WRONG_OLD_PASSWORD')) {
                    userMsg = 'كلمة المرور الحالية غير صحيحة';
                  }
                  AppTheme.showSnackBar(context,
                    SnackBar(
                        content: Text(userMsg),
                        backgroundColor: AppTheme.errorRed),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGold),
            child: const Text('حفظ',
                style: TextStyle(color: AppTheme.deepBlack)),
          ),
        ],
      ),
    );
  }
}
