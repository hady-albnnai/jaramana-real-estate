import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../models/offer_model.dart';
import '../../models/user_model.dart';
import '../../core/services/business_service.dart';
import '../../core/network/supabase_service.dart';
import '../../core/constants/db_constants.dart';
import '../../core/theme/app_theme.dart';

/// شاشة مراجعة العروض الجديدة للإدارة
/// تعرض الصور + معلومات المرسل + التفاصيل + كشف العروض المكررة
/// + إجراءات قبول/رفض بسبب + نشر اجتماعي تلقائي بعد الموافقة
class OffersReviewScreen extends StatefulWidget {
  const OffersReviewScreen({super.key});

  @override
  State<OffersReviewScreen> createState() => _OffersReviewScreenState();
}

class _OffersReviewScreenState extends State<OffersReviewScreen> {
  List<OfferModel> _offers = [];
  List<OfferModel> _socialQueue = [];
  final Set<String> _publishingIds = {};
  final Set<String> _videoBusyIds = {}; // 🎥 عروض جاري تقليب علامة الفيديو لها
  bool _loading = true;
  bool _bulkPublishing = false;

  // كاش بيانات المرسلين: userId → UserModel
  final Map<String, UserModel> _ownersCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final offers = await admin.getPendingOffers(adminUid);
    final socialQueue = await admin.getSocialQueue(adminUid);

    // اجلب بيانات المرسلين + مضيفي الإدارة دفعة واحدة
    final allOffers = [...offers, ...socialQueue];
    final uids = {
      ...allOffers.map((o) => o.usrId),
      ...allOffers.where((o) => o.addedBy != null).map((o) => o.addedBy!),
    }.where((id) => id.isNotEmpty).toList();

    if (uids.isNotEmpty) {
      try {
        final usersData = await SupabaseService()
            .client
            .from(DbTables.users)
            .select()
            .inFilter('id', uids);
        for (final u in usersData as List) {
          final m = Map<String, dynamic>.from(u as Map);
          final user = UserModel.fromSupabase(m, m['id'] as String);
          _ownersCache[user.uid] = user;
        }
      } catch (e) {
        // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
      }
    }

    if (!mounted) return;
    setState(() {
      _offers = offers;
      _socialQueue = socialQueue;
      _loading = false;
    });
  }

  Future<void> _approve(OfferModel o) async {
    final config = context.read<ConfigProvider>().config;
    final autoEnabled = config?.socialAutoPublish ?? true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تأكيد القبول',
            style: TextStyle(color: AppTheme.textWhite)),
        content: Text(
            autoEnabled && o.iSoc == 1
                ? 'سيتم نشر العرض ليصبح مرئياً للجميع وسيتم نشره تلقائياً على فيسبوك وإنستغرام${o.imgs.isEmpty ? ' (يحتاج صورة للإنستغرام)' : ''}. هل أنت متأكد؟'
                : 'سيتم نشر العرض ليصبح مرئياً للجميع. هل أنت متأكد؟',
            style: const TextStyle(color: AppTheme.textGrey)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.successGreen),
            child: const Text('نشر',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await admin.reviewOffer(adminUid, o.id, true);
    if (!mounted) return;
    final ok = result['success'] == true;
    if (ok) {
      try {
        final cfg = context.read<ConfigProvider>().config;
        await BusinessService().awardEvent(o.usrId, cfg, 'addO', fallback: 500);
      } catch (_) {}

      // رسالة مفصلة عن النشر الاجتماعي
      String msg = '✅ تم نشر العرض داخلياً';
      if (o.iSoc == 1 && o.socTxt.isNotEmpty) {
        final social = result['social_publish'] as Map<String, dynamic>?;
        if (social == null) {
          msg += ' • 📣 تمت جدولته للنشر (الوضع التلقائي معطل)';
        } else if (social['success'] == true) {
          final already = social['alreadyPublished'] == true;
          msg += already
              ? ' • 📣 كان منشوراً مسبقاً على السوشيال'
              : ' • 📣 ✅ تم النشر تلقائياً على فيسبوك وإنستغرام';
        } else {
          final err = (social['error'] ?? '').toString();
          if (err.contains('META_SECRETS_NOT_CONFIGURED')) {
            msg += ' • ⚠️ التوكنات غير مضبوطة، بقي في قائمة الجاهزة';
          } else if (err.contains('PUBLIC_IMAGE_REQUIRED')) {
            msg += ' • ⚠️ لا توجد صورة عامة للنشر، بقي في قائمة الجاهزة';
          } else {
            msg += ' • ⚠️ فشل النشر التلقائي (${err.isEmpty ? 'خطأ غير معروف' : err}). سيبقى في قائمة الجاهزة لإعادة المحاولة';
          }
        }
      }
      _snack(msg);
      // ✅ Bug #33: تحديث فوري للقائمة والإشعارات بعد إتمام المراجعة
      await _load();
      // تحديث Provider لإشعار الشاشات الأخرى
      if (mounted) {
        context.read<AdminProvider>().notifyListeners();
      }
    } else {
      _snack(result['error']?.toString() ?? 'فشل النشر: ${admin.error ?? ''}');
    }
  }

  Future<void> _publishToSocial(OfferModel o) async {
    if (_publishingIds.contains(o.id)) return;
    if (o.imgs.isEmpty) {
      _snack('لا يمكن النشر على إنستغرام بدون صورة واحدة على الأقل');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('نشر على فيسبوك + إنستغرام',
            style: TextStyle(color: AppTheme.textWhite)),
        content: Text(
          'سيتم نشر ${o.imgs.length > 10 ? 10 : o.imgs.length} صورة كألبوم مع نص العرض. هل تريد المتابعة؟',
          style: const TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.send),
            label: const Text('نشر الآن'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _publishingIds.add(o.id));
    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final ok = await admin.publishOfferToSocial(adminUid, o.id);
    if (!mounted) return;
    setState(() => _publishingIds.remove(o.id));
    if (ok) {
      _snack('✅ تم النشر فعلياً على فيسبوك وإنستغرام');
      // ✅ Bug #33: تحديث فوري للقائمة والإشعارات بعد إتمام النشر
      await _load();
      // تحديث Provider لإشعار الشاشات الأخرى
      if (mounted) {
        context.read<AdminProvider>().notifyListeners();
      }
    } else {
      _snack(admin.error ?? 'تعذر النشر؛ يمكنك إعادة المحاولة بأمان');
    }
  }

  Future<void> _publishAllQueued() async {
    if (_socialQueue.isEmpty || _bulkPublishing) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('نشر جميع العروض الجاهزة',
            style: TextStyle(color: AppTheme.textWhite)),
        content: Text(
          'سيتم محاولة نشر ${_socialQueue.length} عرض تلقائياً على فيسبوك وإنستغرام. المتابعة؟',
          style: const TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نشر الجميع'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _bulkPublishing = true);
    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    int successCount = 0;
    int failCount = 0;

    for (final offer in List<OfferModel>.from(_socialQueue)) {
      if (offer.imgs.isEmpty) {
        failCount++;
        continue;
      }
      final ok = await admin.publishOfferToSocial(adminUid, offer.id);
      if (ok) {
        successCount++;
      } else {
        failCount++;
      }
    }

    if (!mounted) return;
    setState(() => _bulkPublishing = false);
    _snack('📊 النتيجة: ✅ $successCount نجح • ❌ $failCount فشل/تخطي');
    // ✅ Bug #33: تحديث فوري للقائمة والإشعارات بعد إتمام النشر
    await _load();
    // تحديث Provider لإشعار الشاشات الأخرى
    if (mounted) {
      context.read<AdminProvider>().notifyListeners();
    }
  }

  Future<void> _reject(OfferModel o) async {
    final reason = await _askReason();
    if (reason == null || !mounted) return;

    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await admin.reviewOffer(adminUid, o.id, false, reason: reason);
    if (!mounted) return;
    final ok = result['success'] == true;
    if (ok) {
      _snack('تم رفض العرض');
      // ✅ Bug #33: تحديث فوري للقائمة والإشعارات بعد إتمام المراجعة
      await _load();
      // تحديث Provider لإشعار الشاشات الأخرى
      if (mounted) {
        context.read<AdminProvider>().notifyListeners();
      }
    } else {
      _snack(result['error']?.toString() ?? 'فشل الرفض');
    }
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    String? selected;
    final presets = [
      'صور غير واضحة',
      'بيانات ناقصة',
      'سعر غير منطقي',
      'عرض مكرر',
      'محتوى مخالف',
      'سبب آخر',
    ];

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            backgroundColor: AppTheme.surfaceBlack,
            title: const Text('سبب الرفض',
                style: TextStyle(color: AppTheme.textWhite)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...presets.map((p) => RadioListTile<String>(
                        title: Text(p,
                            style: const TextStyle(color: AppTheme.textWhite)),
                        value: p,
                        groupValue: selected,
                        onChanged: (value) => setS(() => selected = value),
                        activeColor: AppTheme.primaryGold,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      )),
                  AppTheme.gapHeightSmall,
                  TextField(
                    controller: ctrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppTheme.textWhite),
                    decoration: const InputDecoration(
                      hintText: 'تفاصيل إضافية (اختياري)',
                      border: OutlineInputBorder(),
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
                onPressed: () {
                  if (selected == null) return;
                  final extra = ctrl.text.trim();
                  final result =
                      extra.isEmpty ? selected! : '$selected — $extra';
                  Navigator.pop(ctx, result);
                },
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
                child: const Text('رفض',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _snack(String m) =>
      AppTheme.showSnackBar(context, SnackBar(content: Text(m), duration: const Duration(seconds: 4)));

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>().config;
    final autoEnabled = config?.socialAutoPublish ?? true;
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: Text('مراجعة العروض (${_offers.length}) • جاهز للنشر (${_socialQueue.length})'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primaryGold))
          : _offers.isEmpty && _socialQueue.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 80,
                          color: AppTheme.successGreen.withOpacity(0.6)),
                      AppTheme.gapHeightXL,
                      const Text(
                        'لا توجد عروض للمراجعة أو للنشر 🎉',
                        style: TextStyle(
                            color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSubtitle),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppTheme.primaryGold,
                  onRefresh: _load,
                  child: ListView(
                    padding: AppTheme.paddingAllMedium,
                    children: [
                      Container(
                        padding: AppTheme.paddingAllMedium,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: autoEnabled
                              ? AppTheme.successGreen.withOpacity(0.08)
                              : AppTheme.warningOrange.withOpacity(0.08),
                          borderRadius: AppTheme.radiusMedium,
                          border: Border.all(
                              color: autoEnabled
                                  ? AppTheme.successGreen.withOpacity(0.4)
                                  : AppTheme.warningOrange.withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(
                                autoEnabled
                                    ? Icons.auto_awesome
                                    : Icons.pause_circle_outline,
                                color: autoEnabled ? AppTheme.successGreen : AppTheme.warningOrange,
                                size: 18),
                            AppTheme.gapWidthSmall,
                            Expanded(
                              child: Text(
                                autoEnabled
                                    ? 'الوضع التلقائي مفعّل: سيُنشر العرض تلقائياً على فيسبوك وإنستغرام بعد الموافقة'
                                    : 'الوضع التلقائي معطل: العروض ستُجدول فقط وتحتاج نشر يدوي من قائمة الجاهزة',
                                style: TextStyle(
                                    color: autoEnabled ? AppTheme.successGreen : AppTheme.warningOrange,
                                    fontSize: AppTheme.fontSizeSmall,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_socialQueue.isNotEmpty) ...[
                        _listHeader(
                          '📣 جاهزة للنشر على فيسبوك + إنستغرام',
                          '${_socialQueue.length}',
                          AppTheme.infoBlue,
                          action: _socialQueue.length > 1
                              ? TextButton.icon(
                                  onPressed: _bulkPublishing ? null : _publishAllQueued,
                                  icon: _bulkPublishing
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.publish, size: 16),
                                  label: Text(_bulkPublishing ? 'جارٍ...' : 'نشر الكل'),
                                )
                              : null,
                        ),
                        ..._socialQueue.map((o) => _offerCard(o, socialOnly: true)),
                        AppTheme.gapHeightSmall,
                      ],
                      if (_offers.isNotEmpty) ...[
                        _listHeader(
                          '📝 بانتظار المراجعة',
                          '${_offers.length}',
                          AppTheme.primaryGold,
                        ),
                        ..._offers.map(_offerCard),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _listHeader(String title, String count, Color color, {Widget? action}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
            if (action != null) action,
            AppTheme.gapWidthSmall,
            CircleAvatar(
              radius: 14,
              backgroundColor: color.withOpacity(0.2),
              child: Text(count, style: TextStyle(color: color, fontSize: AppTheme.fontSizeCaption)),
            ),
          ],
        ),
      );

  Widget _offerCard(OfferModel o, {bool socialOnly = false}) {
    final owner = _ownersCache[o.usrId];
    final hasImage = o.imgs.isNotEmpty;
    final isDup = o.iDup == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(
          color: isDup ? AppTheme.warningOrange : AppTheme.primaryGold.withOpacity(0.3),
          width: isDup ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // تحذير العرض المكرر
          if (isDup)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.warningOrange.withOpacity(0.2),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber,
                      color: AppTheme.warningOrange, size: 16),
                  SizedBox(width: 6),
                  Text('⚠️ عرض مكرّر محتمل',
                      style: TextStyle(
                          color: AppTheme.warningOrange,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTheme.fontSizeSmall)),
                ],
              ),
            ),

          // الصور
          if (hasImage)
            SizedBox(
              height: 180,
              child: PageView.builder(
                itemCount: o.imgs.length,
                itemBuilder: (_, i) => Image.network(
                  o.imgs[i].toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: AppTheme.deepBlack,
                    child: const Center(
                      child: Icon(Icons.broken_image,
                          color: AppTheme.textGrey, size: 50),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 120,
              color: AppTheme.deepBlack,
              child: const Center(
                child: Icon(Icons.image_not_supported,
                    color: AppTheme.textGrey, size: 50),
              ),
            ),

          // التفاصيل
          Padding(
            padding: AppTheme.paddingAllLarge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // عنوان + سعر
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        o.ttl,
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: AppTheme.fontSizeSubtitle,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      '${o.prc.toStringAsFixed(0)} ${o.cur == 0 ? '\$' : 'ل.س'}',
                      style: const TextStyle(
                          color: AppTheme.primaryGold,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTheme.fontSizeSubtitle),
                    ),
                  ],
                ),
                AppTheme.gapHeightSmall,

                // النوع + المعاملة
                Wrap(spacing: 6, children: [
                  _chip('#${o.offerNumber ?? 0}', Colors.teal),
                  _chip(o.typ == 0 ? '🏠 عقار' : '🚗 سيارة', AppTheme.infoBlue),
                  _chip(o.trx == 0 ? 'بيع' : 'إيجار', Colors.purple),
                  if (o.imgs.isNotEmpty)
                    _chip('${o.imgs.length} صور',
                        AppTheme.primaryGold),
                ]),
                AppTheme.gapHeightSmall,

                // الموقع
                Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: AppTheme.textGrey, size: 14),
                    AppTheme.gapWidthXS,
                    Expanded(
                      child: Text(
                        (o.loc['d'] ?? 'غير محدد').toString(),
                        style: const TextStyle(
                            color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                      ),
                    ),
                  ],
                ),
                AppTheme.gapHeightSmall,

                // شارة النشر الاجتماعي (إن كان مفعّل)
                if (o.iSoc == 1 && o.socTxt.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(top: 4, bottom: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.infoBlue.withOpacity(0.12),
                      borderRadius: AppTheme.radiusSmall,
                      border: Border.all(color: AppTheme.infoBlue.withOpacity(0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.share, color: AppTheme.infoBlue, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            socialOnly
                                ? '📣 العرض معتمد وجاهز للنشر الفعلي على فيسبوك + إنستغرام'
                                : '📣 سيُنشر تلقائياً على فيسبوك + إنستغرام بعد الموافقة',
                            style: const TextStyle(color: AppTheme.infoBlue, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // الوصف
                if (o.descript.isNotEmpty) ...[
                  Text(
                    o.descript,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
                  ),
                  AppTheme.gapHeightSmall,
                ],

                // تنويه داخلي: من أضاف العرض
                if (o.addedBy != null && o.addedBy!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.08),
                      borderRadius: AppTheme.radiusSmall,
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.admin_panel_settings,
                          color: Colors.amber, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'أُضيف بواسطة: ${_ownersCache[o.addedBy]?.nm.isNotEmpty == true ? _ownersCache[o.addedBy]!.nm : 'موظف (${o.addedBy!.substring(0, 8)})'}',
                          style: const TextStyle(color: Colors.amber, fontSize: AppTheme.fontSizeCaption),
                        ),
                      ),
                    ]),
                  ),
                  AppTheme.gapHeightSmall,
                ],

                // المرسل
                const Divider(color: AppTheme.textGrey, height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppTheme.primaryGold,
                      child: Text(
                        (owner?.nm.isNotEmpty == true
                                ? owner!.nm[0]
                                : (owner?.usr.isNotEmpty == true ? owner!.usr[0] : '؟'))
                            .toUpperCase(),
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    AppTheme.gapWidthSmall,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            owner?.nm.isNotEmpty == true
                                ? owner!.nm
                                : (owner?.usr.isNotEmpty == true ? owner!.usr : 'مستخدم بدون اسم'),
                            style: const TextStyle(
                                color: AppTheme.textWhite,
                                fontWeight: FontWeight.bold,
                                fontSize: AppTheme.fontSizeBody),
                          ),
                          Text(
                            owner?.ph ?? '—',
                            style: const TextStyle(
                                color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
                          ),
                        ],
                      ),
                    ),
                    if (owner != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGold.withOpacity(0.15),
                          borderRadius: AppTheme.radiusSmall,
                        ),
                        child: Text(
                          '${owner.pt} نقطة',
                          style: const TextStyle(
                              color: AppTheme.primaryGold,
                              fontSize: AppTheme.fontSizeCaption,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // أزرار الإجراءات
          Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.deepBlack, width: 1),
              ),
            ),
            child: socialOnly
                ? Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => context.push('/offer/${o.id}'),
                          icon: const Icon(Icons.preview, color: AppTheme.textWhite),
                          label: const Text('معاينة',
                              style: TextStyle(color: AppTheme.textWhite)),
                        ),
                      ),
                      Container(width: 1, height: 36, color: AppTheme.deepBlack),
                      Expanded(child: _videoFlagBtn(o)),
                      Container(width: 1, height: 36, color: AppTheme.deepBlack),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _publishingIds.contains(o.id)
                              ? null
                              : () => _publishToSocial(o),
                          icon: _publishingIds.contains(o.id)
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.share),
                          label: Text(_publishingIds.contains(o.id)
                              ? 'جارٍ النشر...'
                              : 'نشر الآن'),
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _reject(o),
                          icon: const Icon(Icons.close_rounded, color: AppTheme.errorRed, size: 22),
                          label: const Text('رفض',
                              style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                      Container(width: 1, height: 40, color: AppTheme.deepBlack),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => context.push('/offer/${o.id}'),
                          icon: const Icon(Icons.visibility_rounded, color: AppTheme.textWhite, size: 22),
                          label: const Text('معاينة',
                              style: TextStyle(color: AppTheme.textWhite, fontSize: 15)),
                        ),
                      ),
                      Container(width: 1, height: 40, color: AppTheme.deepBlack),
                      Expanded(child: _videoFlagBtn(o)),
                      Container(width: 1, height: 40, color: AppTheme.deepBlack),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: () => _approve(o),
                          icon: const Icon(Icons.check_circle_rounded, color: AppTheme.successGreen, size: 22),
                          label: const Text('قبول',
                              style: TextStyle(color: AppTheme.successGreen, fontWeight: FontWeight.bold, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// 🎥 قلب علامة «فيديو متوفر» (واتساب المكتب) — ميزة الفيديو 2026-07-27
  Future<void> _toggleVideoFlag(OfferModel o) async {
    final has = o.vdo.isEmpty; // الحالة الجديدة المطلوبة
    setState(() => _videoBusyIds.add(o.id));
    try {
      final res = await SupabaseService().invokeFunction('admin-offers', body: {
        'action': 'set_video_flag',
        'offer_id': o.id,
        'has_video': has,
      });
      if (!mounted) return;
      if (res.data?['success'] == true) {
        _snack(has
            ? '🎥 تم تفعيل الفيديو — ستظهر بطاقته بصفحة العرض للزوار'
            : 'تم إلغاء علامة الفيديو');
        await _load();
      } else {
        _snack(res.data?['error']?.toString() ?? 'فشل تغيير علامة الفيديو');
      }
    } catch (e) {
      if (mounted) _snack('خطأ: $e');
    } finally {
      if (mounted) setState(() => _videoBusyIds.remove(o.id));
    }
  }

  Widget _videoFlagBtn(OfferModel o) {
    final busy = _videoBusyIds.contains(o.id);
    final active = o.vdo.isNotEmpty;
    return TextButton.icon(
      onPressed: busy ? null : () => _toggleVideoFlag(o),
      icon: busy
          ? const SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(active ? Icons.videocam : Icons.videocam_off_outlined,
              color: active ? AppTheme.primaryGold : AppTheme.textGrey, size: 20),
      label: Text(active ? 'فيديو ✓' : 'فيديو',
          style: TextStyle(
              color: active ? AppTheme.primaryGold : AppTheme.textGrey,
              fontSize: AppTheme.fontSizeSmall,
              fontWeight: active ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: AppTheme.radiusSmall,
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: AppTheme.fontSizeCaption, fontWeight: FontWeight.bold)),
    );
  }
}
