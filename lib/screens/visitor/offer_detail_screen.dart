import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/offer_model.dart';
import '../../models/user_model.dart';
import '../../providers/offer_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/app_utils.dart';
import '../../core/services/business_service.dart';
import '../../core/services/local_cache_service.dart';
import '../../core/network/supabase_service.dart';
import '../../core/constants/db_constants.dart';
import '../../widgets/book_appointment_sheet.dart';
import '../../widgets/video_player_widget.dart';
import '../../widgets/location_picker.dart';
import '../../widgets/rating_dialog.dart';

import '../../providers/admin_provider.dart';
import '../../providers/notification_provider.dart';
import '../../widgets/fit_tile.dart';

class OfferDetailScreen extends StatefulWidget {
  final String offerId;
  const OfferDetailScreen({super.key, required this.offerId});

  @override
  State<OfferDetailScreen> createState() => _OfferDetailScreenState();
}

class _OfferDetailScreenState extends State<OfferDetailScreen> {
  OfferModel? _offer;
  UserModel? _owner;
  double? _ownerAvgRating;
  int _ownerRatingCount = 0;
  bool _loading = true;
  /// 📸 معلومات «مُصوَّر من المكتب» — تُجلب للإدارة فقط من مصدر محمي.
  /// null = ليس مُصوَّراً من المكتب أو المستخدم ليس إدارياً ⇒ لا يظهر التنويه.
  Map<String, dynamic>? _officePhotoInfo;
  // حالة القلب تُقرأ حيّاً من favoritesListenable (لا حقل محلي — إصلاح مزامنة 2026-07-27)
  bool _publishing = false;
  int _currentImg = 0;
  late final PageController _pageCtrl = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final provider = context.read<OfferProvider>();
    final userId = context.read<AuthProvider>().userModel?.uid;
    // محاولة من الذاكرة أولاً ثم جلب من السيرفر
    var offer = provider.getOfferById(widget.offerId);
    offer ??= await provider.fetchOfferById(widget.offerId, userId: userId);
    if (offer != null) {
      // مشاهدة المالك لعرضه لا تُحتسب (قاعدة المالك 2026-07-26) — والسيرفر يحسم أيضاً
      if (userId == null || userId != offer.usrId) {
        provider.incrementViews(widget.offerId, viewerUid: userId);
      }

      // جلب بيانات المالك لتوليد التسمية المهنية (لا يُعرض اسمه أبداً)
      try {
        final row = await SupabaseService()
            .client
            .from(DbTables.usersPublic)
            .select()
            .eq('id', offer.usrId)
            .maybeSingle();
        if (row != null) {
          _owner = UserModel.fromSupabase(
            Map<String, dynamic>.from(row),
            row['id'] as String,
          );
        }
      } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }

      // ⭐ جلب متوسط تقييم المالك (LOGIC_SPEC §3.3)
      try {
        final ratings = await SupabaseService()
            .client
            .from('ratings')
            .select('stars')
            .eq('target_uid', offer.usrId);
        final list = (ratings as List);
        if (list.isNotEmpty) {
          double sum = 0;
          for (final r in list) {
            sum += ((r['stars'] as num?) ?? 0).toDouble();
          }
          _ownerRatingCount = list.length;
          _ownerAvgRating = sum / list.length;
        }
      } catch (e) {
      // تم تجاهل الخطأ عمداً للحفاظ على التدفق الحالي.
    }
    }
    if (mounted) {
      setState(() {
        _offer = offer;
        _loading = false;
      });
    }
    _loadOfficePhotoInfo();
  }

  /// 📸 يجلب تنويه «مُصوَّر من المكتب» — للإداريين فقط (دور ≥ موظف مكتب).
  /// المصدر محمي (photography_tasks عبر إيدج بحارس دور) وليس specs المكشوف.
  Future<void> _loadOfficePhotoInfo() async {
    final me = context.read<AuthProvider>().userModel;
    if (me == null || me.role < UserRole.employee) return;
    try {
      final res = await SupabaseService().invokeFunction(
        'admin-photography',
        body: {
          'action': 'offer_photo_info',
          'admin_uid': me.uid,
          'offer_id': widget.offerId,
        },
      );
      final d = res.data;
      if (d is Map && d['office_photographed'] == true && mounted) {
        setState(() => _officePhotoInfo = Map<String, dynamic>.from(d));
      }
    } catch (_) {
      // التنويه إثراء إداري — فشله لا يؤثر على عرض التفاصيل
    }
  }

  Widget _favIconButton(BuildContext ctx) {
    final own = _offer != null &&
        ctx.read<AuthProvider>().userModel?.uid == _offer!.usrId;
    final listenable = LocalCacheService().favoritesListenable;
    Widget buildBtn(bool isFav) => IconButton(
          icon: Opacity(
            opacity: own ? 0.35 : 1,
            child: Icon(isFav ? Icons.favorite : Icons.favorite_border,
                color: isFav ? AppTheme.errorRed : null),
          ),
          onPressed: _toggleFav,
        );
    if (listenable == null) {
      return buildBtn(LocalCacheService().isFavorite(widget.offerId));
    }
    return ValueListenableBuilder<Box>(
      valueListenable: listenable,
      builder: (_, __, ___) =>
          buildBtn(LocalCacheService().isFavorite(widget.offerId)),
    );
  }

  Future<void> _toggleFav() async {
    // 🚫 عرضي الخاص: لا إعجاب جديد ولا نقاط (والسيرفر يحسم أيضاً عبر offer_id)
    final myUid = context.read<AuthProvider>().userModel?.uid;
    final isOwn = _offer != null && myUid != null && _offer!.usrId == myUid;
    final isFavNow = LocalCacheService().isFavorite(widget.offerId);
    if (isOwn && !isFavNow) {
      if (mounted) {
        AppTheme.showSnackBar(context, const SnackBar(
          content: Text('لا يمكن الإعجاب بالعرض الخاص بك 👌'),
          duration: Duration(seconds: 1),
        ));
      }
      return;
    }
    final added = await LocalCacheService().toggleFavorite(widget.offerId);
    // لا setState للقلب — الـ listenable يعيد بنائه تلقائياً
    if (mounted) {
      AppTheme.showSnackBar(context, SnackBar(
        content: Text(added ? 'أُضيف للمفضلة ❤️' : 'أُزيل من المفضلة'),
        duration: const Duration(seconds: 1),
      ));
    }
    // عرضي الخاص (كان مضافاً للمفضلة قبل الحماية): إزالة محلية فقط — بدون أي نقاط
    if (isOwn) return;
    if (added && mounted) {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        final config = context.read<ConfigProvider>().config;
        final result = await BusinessService().awardEventDetailed(
          auth.userModel!.uid,
          config,
          'like',
          fallback: 10,
          offerId: widget.offerId, // يمكّن حارس SELF_ACTION بالسيرفر
        );
        if (!mounted) return;
        if (result.awarded) {
          auth.refreshUser();
          AppUtils.showPointsAwarded(
            context,
            BusinessService().pointsFor(config, 'like', 10),
            label: 'نقطة إعجاب',
          );
        } else if (result.limitReached) {
          // بلغ الحد اليومي — الإعجاب محفوظ، بلا منحة وهمية
          AppTheme.showSnackBar(context, SnackBar(
            content: Text(
                'إعجابك انحفظ ❤️ — بس وصلت للحد اليومي (${result.limit} إعجابات)، النقاط ترجع بكرا 🌙'),
            duration: const Duration(seconds: 2),
          ));
        }
        
        // ✅ Fix for Bug #9: Send notification to offer owner
        if (_offer != null && auth.userModel != null) {
          final notifProvider = context.read<NotificationProvider>();
          await notifProvider.sendNotification(
            userId: _offer!.usrId,
            type: 2, // إعجاب
            title: 'إعجاب جديد ❤️',
            body: '${auth.userModel!.nm} أعجب بعرضك "${_offer!.ttl}"',
            refId: widget.offerId,
            action: 'offer_like',
          );
        }
      }
    }
    // إزالة الإعجاب لا تخصم نقاط (2026-07-27): توحيد المنطق بين البطاقة والتفاصيل.
  }

  Future<void> _share() async {
    if (_offer == null) return;
    final config = context.read<ConfigProvider>().config;
    final text = BusinessService().generateSocialPost(_offer!, config: config);
    await SharePlus.instance.share(
      ShareParams(text: text, subject: _offer!.ttl),
    );
  }

  void _showAdminPrioritySheet(BuildContext context, OfferModel offer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceBlack,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(AppTheme.paddingXXL),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تحديد أولوية النشر (للإدارة فقط)',
                style: TextStyle(
                  color: AppTheme.primaryGold,
                  fontSize: AppTheme.fontSizeTitle,
                  fontWeight: FontWeight.bold,
                ),
              ),
              AppTheme.gapHeightSmall,
              const Text(
                'اختر مستوى الأولوية الذي سيظهر فيه العرض للمستخدمين. (لمدة 30 يوم)',
                style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                textAlign: TextAlign.center,
              ),
              AppTheme.gapHeightXXL,
              _priorityOption(ctx, offer.id, 'pin', 'مثبّت في الأعلى (أعلى أولوية)', Icons.push_pin, Colors.redAccent),
              _priorityOption(ctx, offer.id, 'fms', 'مميّز (ثاني أولوية)', Icons.star, Colors.orangeAccent),
              _priorityOption(ctx, offer.id, 'bst', 'مُرقّى (ثالث أولوية)', Icons.rocket_launch, Colors.blueAccent),
              _priorityOption(ctx, offer.id, 'normal', 'عادي (ترتيب حسب التاريخ)', Icons.format_list_bulleted, AppTheme.textGrey),
            ],
          ),
        );
      },
    );
  }

  Widget _priorityOption(BuildContext ctx, String offerId, String type, String label, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: const TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.w600)),
      onTap: () async {
        final adminProv = context.read<AdminProvider>();
        final authProv = context.read<AuthProvider>();

        Navigator.pop(ctx);
        // نعطي الـ bottom sheet وقتاً ليُغلق حتى لا تضيع الرسالة خلفه/أثناء الإغلاق.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!mounted) return;

        AppTheme.hideSnackBar(context);
        AppTheme.showSnackBar(
          context,
          const SnackBar(
            content: Text('جاري تحديث أولوية العرض...'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );

        final ok = await adminProv.setOfferPriority(
          authProv.userModel!.uid,
          offerId,
          type,
        );

        if (mounted) {
          AppTheme.hideSnackBar(context);
          if (ok) {
            AppTheme.showSnackBar(
              context,
              const SnackBar(
                content: Text('تم تحديث أولوية العرض بنجاح'),
                backgroundColor: AppTheme.successGreen,
                behavior: SnackBarBehavior.floating,
              ),
            );
            // Refresh to see updated state
            _load();
          } else {
            AppTheme.showSnackBar(
              context,
              SnackBar(
                content: Text('فشل التحديث: ${adminProv.error ?? "حدث خطأ"}'),
                backgroundColor: AppTheme.errorRed,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      },
    );
  }

  void _showAdminDeleteDialog(BuildContext context, OfferModel offer) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.errorRed),
          AppTheme.gapWidthSmall,
          Text('حذف العرض (إدارة)', style: TextStyle(color: AppTheme.textWhite)),
        ]),
        content: const Text(
          'هل أنت متأكد من رغبتك في حذف هذا العرض؟ سيتم نقله إلى الأرشيف ولن يظهر للمستخدمين بعد الآن.',
          style: TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final adminProv = context.read<AdminProvider>();
              final authProv = context.read<AuthProvider>();

              AppTheme.showSnackBar(context,
                const SnackBar(content: Text('جاري الحذف...')),
              );

              final ok = await adminProv.deleteOfferByAdmin(
                authProv.userModel!.uid,
                offer.id,
              );

              if (mounted) {
                if (ok) {
                  AppTheme.showSnackBar(context,
                    const SnackBar(content: Text('تم حذف العرض بنجاح')),
                  );
                  Navigator.pop(context); // الرجوع للشاشة السابقة بعد الحذف
                } else {
                  AppTheme.showSnackBar(context,
                    SnackBar(content: Text('فشل الحذف: ${adminProv.error ?? "حدث خطأ"}')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }

  Future<void> _approveOffer(OfferModel offer) async {
    final config = context.read<ConfigProvider>().config;
    final autoEnabled = config?.socialAutoPublish ?? true;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('تأكيد القبول',
            style: TextStyle(color: AppTheme.textWhite)),
        content: Text(
            autoEnabled && offer.iSoc == 1
                ? 'سيتم نشر العرض ليصبح مرئياً للجميع وسيتم نشره تلقائياً على فيسبوك وإنستغرام. هل أنت متأكد؟'
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
                style: TextStyle(color: AppTheme.deepBlack, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await admin.reviewOffer(adminUid, offer.id, true);
    if (!mounted) return;
    final ok = result['success'] == true;
    if (ok) {
      try {
        final cfg = context.read<ConfigProvider>().config;
        await BusinessService().awardEvent(offer.usrId, cfg, 'addO', fallback: 500);
      } catch (_) {}
      String msg = '✅ تم نشر العرض';
      final social = result['social_publish'] as Map<String, dynamic>?;
      if (offer.iSoc == 1 && social != null) {
        if (social['success'] == true) {
          msg += ' • 📣 تم النشر تلقائياً على فيسبوك وإنستغرام';
        } else if ((social['error'] ?? '').toString().contains('META_SECRETS')) {
          msg += ' • ⚠️ التوكنات غير مضبوطة — بقي في الجاهزة';
        } else if (social['queued'] == true) {
          msg += ' • 📣 مجدول للنشر';
        } else if (social['error'] != null) {
          msg += ' • ⚠️ فشل تلقائي: ${social['error']}';
        }
      }
      AppTheme.showSnackBar(context,
        SnackBar(content: Text(msg), backgroundColor: AppTheme.successGreen, duration: const Duration(seconds: 4)),
      );
      _load();
    } else {
      AppTheme.showSnackBar(context,
        SnackBar(content: Text('فشل النشر: ${result['error'] ?? admin.error ?? "خطأ غير معروف"}'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  Future<void> _rejectOffer(OfferModel offer) async {
    final reason = await _askRejectReason();
    if (reason == null || !mounted) return;

    final admin = context.read<AdminProvider>();
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final result = await admin.reviewOffer(adminUid, offer.id, false, reason: reason);
    if (!mounted) return;
    final ok = result['success'] == true;
    if (ok) {
      AppTheme.showSnackBar(context,
        const SnackBar(content: Text('تم رفض العرض'), backgroundColor: AppTheme.warningOrange),
      );
      _load();
    } else {
      AppTheme.showSnackBar(context,
        SnackBar(content: Text('فشل الرفض: ${result['error'] ?? admin.error ?? "خطأ غير معروف"}'), backgroundColor: AppTheme.errorRed),
      );
    }
  }

  Future<String?> _askRejectReason() async {
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
                    style: TextStyle(color: AppTheme.scaffoldBackground, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// 🚫 GP-004 (2026-08-15) — حظر صاحب العرض (متطلب سياسة UGC)
  /// ═══════════════════════════════════════════════════════════════════
  /// سياسة Google Play «User Generated Content» تشترط — إلى جانب التبليغ —
  /// **إمكانية حظر المستخدمين**. كانت غائبة كلياً.
  ///
  /// الحظر يُرسَل بمعرّف **العرض** لا بمعرّف المالك: الواجهة لا تعرف
  /// `usr_id` إطلاقاً (SEC-004 يمنع كشفه عبر REST)، والسيرفر يستنتج المالك
  /// بمفتاح الخدمة. الأثر متماثل: يختفي محتوى كلٍّ منهما عن الآخر.
  Future<void> _blockOfferOwner() async {
    if (_offer == null) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      if (!mounted) return;
      AppTheme.showSnackBar(
        context,
        SnackBar(
          content: const Text('يجب تسجيل الدخول لحظر مُعلِن'),
          action: SnackBarAction(
            label: 'دخول',
            onPressed: () => context.push('/login'),
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Row(children: [
          Icon(Icons.block, color: AppTheme.errorRed),
          SizedBox(width: 8),
          Expanded(
            child: Text('حظر هذا المُعلِن',
                style: TextStyle(color: AppTheme.textWhite, fontSize: 18)),
          ),
        ]),
        content: const Text(
          'عند الحظر:\n\n'
          '• لن تظهر لك أي عروض لهذا المُعلِن.\n'
          '• لن تظهر عروضك له كذلك.\n\n'
          'يمكنك رفع الحظر في أي وقت من: الإعدادات ← المستخدمون المحظورون.',
          style: TextStyle(color: AppTheme.textWhite, height: 1.6),
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
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('حظر'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await context.read<AuthProvider>().blockOfferOwner(_offer!.id);
    if (!mounted) return;
    if (ok) {
      AppTheme.showSnackBar(
        context,
        const SnackBar(content: Text('✅ تم حظر المُعلِن — لن تظهر لك عروضه')),
      );
      // نغادر الصفحة: بقاء عرضٍ لمُعلِن محظور أمام المستخدم يناقض الحظر.
      if (context.canPop()) context.pop();
    } else {
      // §13: نعلن الفشل بنصّه لا نبتلعه.
      final err = context.read<AuthProvider>().lastError ?? '';
      AppTheme.showSnackBar(
        context,
        SnackBar(
          content: Text(err.contains('CANNOT_BLOCK_STAFF')
              ? 'لا يمكن حظر موظفي المكتب — استخدم «تبليغ» بدلاً من ذلك'
              : 'تعذّر حظر المُعلِن، حاول مرة أخرى'),
        ),
      );
    }
  }

  Future<void> _reportOffer() async {
    if (_offer == null) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn) {
      AppTheme.showSnackBar(context,
        SnackBar(
          content: const Text('يجب تسجيل الدخول لتبليغ عن عرض'),
          action: SnackBarAction(
            label: 'دخول',
            onPressed: () => context.push('/login'),
          ),
        ),
      );
      return;
    }

    final config = context.read<ConfigProvider>().config;
    final reasons = (config?.reportReasons ?? const [
      'إعلان وهمي / غير موجود',
      'احتيال / نصب',
      'معلومات مضللة',
      'مضايقة / سلوك غير لائق',
      'عرض مكرر',
      'آخر',
    ]).cast<String>();

    String? selected;
    final notesCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Row(children: [
            Icon(Icons.flag, color: AppTheme.errorRed),
            AppTheme.gapWidthSmall,
            Text('تبليغ عن العرض',
                style: TextStyle(color: AppTheme.textWhite)),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('اختر سبب التبليغ:',
                    style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                const SizedBox(height: 6),
                ...reasons.map((r) => RadioListTile<String>(
                      title: Text(r,
                          style: const TextStyle(color: AppTheme.textWhite)),
                      value: r,
                      groupValue: selected,
                      onChanged: (value) => setS(() => selected = value),
                      activeColor: AppTheme.primaryGold,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    )),
                AppTheme.gapHeightSmall,
                TextField(
                  controller: notesCtrl,
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
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textGrey)),
            ),
            ElevatedButton(
              onPressed: () {
                if (selected == null) return;
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
              child: const Text('إرسال التبليغ',
                  style: TextStyle(color: AppTheme.scaffoldBackground, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (result != true || selected == null || !mounted) return;

    try {
      final rsnIndex = reasons.indexOf(selected!);
      final response = await SupabaseService().invokeFunction(
        'user-account',
        body: {
          'action': 'create_report',
          'user_uid': auth.userModel!.uid,
          'report': {
            'tgt_uid': _offer!.usrId,
            'tgt_tp': 1,
            'tgt_id': _offer!.id,
            'rsn': rsnIndex < 0 ? 0 : rsnIndex,
            'det': notesCtrl.text.trim(),
          },
        },
      );
      if (response.data == null || response.data['success'] != true) {
        throw Exception(response.data?['error'] ?? 'Report failed');
      }
      if (!mounted) return;
      AppTheme.showSnackBar(context,
        const SnackBar(
          content: Text('✅ تم إرسال التبليغ، شكراً لمساعدتنا'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().contains('CANNOT_REPORT_OWN')
          ? 'لا يمكن التبليغ عن العرض الخاص بك 👌'
          : 'فشل إرسال التبليغ، حاول مرة أخرى';
      AppTheme.showSnackBar(context, SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryGold)),
      );
    }
    final offer = _offer;
    if (offer == null) {
      return const Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: Center(
            child: Text('العرض غير موجود',
                style: TextStyle(color: AppTheme.textGrey))),
      );
    }

    final auth = context.watch<AuthProvider>();
    final isOwner = auth.userModel?.uid == offer.usrId;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(fit: StackFit.expand, children: [
                // الصور — عرض ثابت (بدون PageView) + ضغط يفتح العارض الكامل
                offer.imgs.isEmpty
                    ? Container(
                        color: AppTheme.surfaceBlack,
                        child: const Icon(Icons.home_work,
                            size: 80, color: AppTheme.textGrey))
                    : GestureDetector(
                        onTap: () => _openImageViewer(offer.imgs, _currentImg),
                        child: Image.network(
                          offer.imgs[_currentImg],
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => Container(
                              color: AppTheme.surfaceBlack,
                              child: const Icon(Icons.image,
                                  size: 80, color: AppTheme.textGrey)),
                        ),
                      ),
                const DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, AppTheme.deepBlack]))),
                // مؤشر الصور (dots قابلة للضغط)
                if (offer.imgs.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0, right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(offer.imgs.length, (i) => GestureDetector(
                        onTap: () => setState(() => _currentImg = i),
                        child: Container(
                          width: _currentImg == i ? 18 : 8,
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: _currentImg == i
                                ? AppTheme.primaryGold
                                : AppTheme.scaffoldBackground.withOpacity(0.5),
                            borderRadius: AppTheme.radiusXS,
                          ),
                        ),
                      )),
                    ),
                  ),
                // أسهم التنقل + زر فتح الصورة
                if (offer.imgs.length > 1) ...[
                  Positioned(
                    left: 8, top: 0, bottom: 0,
                    child: Center(child: GestureDetector(
                      onTap: () { if (_currentImg > 0) setState(() => _currentImg--); },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Icon(Icons.chevron_left, color: AppTheme.scaffoldBackground, size: 24),
                      ),
                    )),
                  ),
                  Positioned(
                    right: 8, top: 0, bottom: 0,
                    child: Center(child: GestureDetector(
                      onTap: () { if (_currentImg < offer.imgs.length - 1) setState(() => _currentImg++); },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Icon(Icons.chevron_right, color: AppTheme.scaffoldBackground, size: 24),
                      ),
                    )),
                  ),
                ],
                // زر فتح الصورة بملء الشاشة
                if (offer.imgs.isNotEmpty)
                  Positioned(
                    bottom: 12, right: 16,
                    child: GestureDetector(
                      onTap: () => _openImageViewer(offer.imgs, _currentImg),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: AppTheme.radiusXL,
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.fullscreen, color: AppTheme.scaffoldBackground, size: 18),
                          AppTheme.gapWidthXS,
                          Text('عرض الصور', style: TextStyle(color: AppTheme.scaffoldBackground, fontSize: AppTheme.fontSizeSmall)),
                        ]),
                      ),
                    ),
                  ),
                // عداد الصور (1/3)
                if (offer.imgs.length > 1)
                  Positioned(
                    top: 12, left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: AppTheme.radiusMedium,
                      ),
                      child: Text(
                        '${_currentImg + 1}/${offer.imgs.length}',
                        style: const TextStyle(color: AppTheme.scaffoldBackground, fontSize: AppTheme.fontSizeSmall),
                      ),
                    ),
                  ),
              ]),
            ),
            leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios),
                onPressed: () => Navigator.pop(context)),
            actions: [
              // لا تبليغ/حظر على العرض الخاص بك — والسيرفر يحسم أيضاً
              // (CANNOT_REPORT_OWN / CANNOT_BLOCK_SELF).
              // 🚫 GP-004 (2026-08-15): صار الزر قائمة تضم «تبليغ» و«حظر
              // المُعلِن» معاً — سياسة UGC في Google Play تشترط الاثنين.
              if (_offer != null &&
                  context.read<AuthProvider>().userModel?.uid != _offer!.usrId)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: 'خيارات',
                  color: AppTheme.surfaceBlack,
                  onSelected: (v) {
                    if (v == 'report') _reportOffer();
                    if (v == 'block') _blockOfferOwner();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'report',
                      child: Row(children: [
                        Icon(Icons.flag_outlined, color: AppTheme.errorRed, size: 20),
                        SizedBox(width: 10),
                        Text('تبليغ عن العرض',
                            style: TextStyle(color: AppTheme.textWhite)),
                      ]),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Row(children: [
                        Icon(Icons.block, color: AppTheme.errorRed, size: 20),
                        SizedBox(width: 10),
                        Text('حظر هذا المُعلِن',
                            style: TextStyle(color: AppTheme.textWhite)),
                      ]),
                    ),
                  ],
                ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: _share,
              ),
              // ❤️ القلب يتعتّم على عروضك الخاصة (والسيرفر يرفض النقاط كذلك)
              // زر القلب — حيّ ومتزامن مع البطاقات بالقوائم (فئة المفضلة)
              Builder(builder: (ctx) => _favIconButton(ctx)),
            ],
          ),
          SliverToBoxAdapter(
            child: Container(
              padding: AppTheme.paddingAllXL,
              decoration: const BoxDecoration(
                  color: AppTheme.scaffoldBackground,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(30))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (offer.offerNumber != null)
                                Text('عرض رقم #${offer.offerNumber}',
                                    style: TextStyle(color: AppTheme.primaryGold.withOpacity(0.7), fontSize: AppTheme.fontSizeSmall)),
                              if (isOwner || auth.isAdmin)
                                Container(
                                  margin: const EdgeInsets.only(top: 4, bottom: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: offer.daysUntilExpiration <= 3 ? AppTheme.errorRed.withOpacity(0.1) : AppTheme.successGreen.withOpacity(0.1),
                                    borderRadius: AppTheme.radiusSmall,
                                    border: Border.all(color: offer.daysUntilExpiration <= 3 ? AppTheme.errorRed.withOpacity(0.3) : AppTheme.successGreen.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.timer_outlined, size: 14, color: offer.daysUntilExpiration <= 3 ? AppTheme.errorRed : AppTheme.successGreen),
                                      AppTheme.gapWidthXS,
                                      Text(
                                        offer.daysUntilExpiration == 0 ? 'ينتهي اليوم (بانتظار التجديد)' : 'ينتهي بعد ${offer.daysUntilExpiration} يوم',
                                        style: TextStyle(
                                          color: offer.daysUntilExpiration <= 3 ? AppTheme.errorRed : AppTheme.successGreen,
                                          fontSize: AppTheme.fontSizeCaption,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(offer.ttl,
                                  style: const TextStyle(
                                      color: AppTheme.textWhite,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        AppTheme.gapWidthSmall,
                        Text(
                            AppUtils.formatPrice(offer.prc, currency: offer.cur),
                            style: const TextStyle(
                                color: AppTheme.primaryGold,
                                fontSize: AppTheme.fontSizeHeadline,
                                fontWeight: FontWeight.bold)),
                      ]),

                  // 🏢 هوية المكتب — تسمية مهنية بدل اسم المالك (LOGIC_SPEC §1)
                  // تظهر دائماً: إذا لم يُجلب المالك تظهر "منشور بواسطة المكتب" كـ fallback
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGold.withOpacity(0.08),
                      borderRadius: AppTheme.radiusSmall,
                      border: Border.all(
                          color: AppTheme.primaryGold.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.business_center,
                            color: AppTheme.primaryGold, size: 16),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _owner != null
                                ? BusinessService().getUserPublicLabel(_owner!)
                                : (_offer?.ownerLabel?.isNotEmpty == true
                                    ? _offer!.ownerLabel!
                                    : 'منشور بواسطة المكتب العقاري الالكتروني'),
                            style: const TextStyle(
                                color: AppTheme.primaryGold,
                                fontSize: AppTheme.fontSizeBody,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ⭐ متوسط تقييم المالك (إن وُجد)
                  if (_ownerAvgRating != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.star,
                          color: AppTheme.primaryGold, size: 16),
                      AppTheme.gapWidthXS,
                      Text(
                        '${_ownerAvgRating!.toStringAsFixed(1)} ($_ownerRatingCount تقييم)',
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: AppTheme.fontSizeSmall,
                            fontWeight: FontWeight.w500),
                      ),
                    ]),
                  ],

                  AppTheme.gapHeightSmall,
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.location_on,
                        color: AppTheme.primaryGold, size: 20),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((offer.loc['city'] ?? '').toString().isNotEmpty)
                            Text((offer.loc['city'] ?? '').toString(),
                                style: const TextStyle(
                                    color: AppTheme.primaryGold,
                                    fontSize: AppTheme.fontSizeMedium,
                                    fontWeight: FontWeight.bold)),
                          Text(offer.loc['d'] ?? '',
                              style: const TextStyle(
                                  color: AppTheme.textGrey, fontSize: 15)),
                        ],
                      ),
                    ),
                  ]),
                  AppTheme.gapHeightXL,
                  const Text('الوصف التفصيلي',
                      style: TextStyle(
                          color: AppTheme.primaryGold,
                          fontSize: AppTheme.fontSizeTitle,
                          fontWeight: FontWeight.bold)),
                  AppTheme.gapHeightSmall,
                  Text(offer.descript.isEmpty ? 'لا يوجد وصف' : offer.descript,
                      style: const TextStyle(
                          color: AppTheme.textWhite, fontSize: AppTheme.fontSizeSubtitle, height: 1.5)),
                  // المواصفات التقنية
                  // المواصفات التفصيلية — حسب نوع العرض
                  if (offer.specs.isNotEmpty) ...[
                    AppTheme.gapHeightXL,
                    Text(offer.typ == 1 ? 'مواصفات السيارة' : 'مواصفات العقار',
                        style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeTitle, fontWeight: FontWeight.bold)),
                    AppTheme.gapHeightSmall,
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (offer.typ == 0) ...[
                        if ((offer.specs['area'] ?? '').toString().isNotEmpty) _spec(Icons.square_foot, 'المساحة', '${offer.specs['area']} م²'),
                        if ((offer.specs['floor'] ?? '').toString().isNotEmpty) _spec(Icons.layers, 'الطابق', offer.specs['floor'].toString()),
                        if ((offer.specs['finishing'] ?? '').toString().isNotEmpty) _spec(Icons.format_paint, 'الإكساء', offer.specs['finishing'].toString()),
                        if ((offer.specs['direction'] ?? '').toString().isNotEmpty) _spec(Icons.explore, 'الاتجاه', offer.specs['direction'].toString()),
                      ],
                      if (offer.typ == 1) ...[
                        if ((offer.specs['brand'] ?? '').toString().isNotEmpty) _spec(Icons.directions_car, 'الماركة', offer.specs['brand'].toString()),
                        if ((offer.specs['model'] ?? '').toString().isNotEmpty) _spec(Icons.car_repair, 'الموديل', offer.specs['model'].toString()),
                        if ((offer.specs['year'] ?? '').toString().isNotEmpty) _spec(Icons.calendar_today, 'سنة الصنع', offer.specs['year'].toString()),
                        if ((offer.specs['color'] ?? '').toString().isNotEmpty) _spec(Icons.palette, 'اللون', offer.specs['color'].toString()),
                        if ((offer.specs['km'] ?? '').toString().isNotEmpty) _spec(Icons.speed, 'الكيلومترات', '${offer.specs['km']} كم'),
                        if ((offer.specs['fuel'] ?? '').toString().isNotEmpty) _spec(Icons.local_gas_station, 'الوقود', offer.specs['fuel'].toString()),
                        if ((offer.specs['transmission'] ?? '').toString().isNotEmpty) _spec(Icons.settings, 'ناقل الحركة', offer.specs['transmission'].toString()),
                        if ((offer.specs['plate'] ?? '').toString().isNotEmpty) _spec(Icons.confirmation_number, 'رقم اللوحة والمحافظة', offer.specs['plate'].toString()),
                      ],
                    ]),
                    if ((offer.specs['legal_notes'] ?? '').toString().isNotEmpty) ...[
                      AppTheme.gapHeightSmall,
                      _spec(Icons.gavel, 'ملاحظات قانونية', offer.specs['legal_notes'].toString()),
                    ],
                    if ((offer.specs['details'] ?? '').toString().trim().isNotEmpty) ...[
                      AppTheme.gapHeightSmall,
                      Text(offer.specs['details'].toString(), style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium, height: 1.5)),
                    ],
                  ],
                  AppTheme.gapHeightXL,

                  // فيديو العرض — NOTICE + REQUEST BUTTON (NEVER PUBLICLY SHOWN OR DOWNLOADABLE)
                  // Only appears on published offers if vdo exists.
                  // "Watch video" button only visible to logged-in users.
                  // Opens booking sheet with video context → enforces verified phone + auto WhatsApp after success.
                  // ✅ Fix for Bug #8: لا تعرض قسم الفيديو للإدارة، بل اعرض معلومات المراجعة
                  if (offer.vdo.isNotEmpty && !auth.isAdmin) ...[
                    AppTheme.gapHeightSmall,
                    Container(
                      padding: AppTheme.paddingAllLarge,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGold.withOpacity(0.08),
                        borderRadius: AppTheme.radiusLarge,
                        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.videocam, color: AppTheme.primaryGold, size: 20),
                            AppTheme.gapWidthSmall,
                            const Expanded(
                              child: Text(
                                'فيديو العرض متوفر',
                                style: TextStyle(
                                    color: AppTheme.primaryGold,
                                    fontSize: AppTheme.fontSizeSubtitle,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ]),
                          AppTheme.gapHeightSmall,
                          const Text(
                            'يمكنك طلب مشاهدة الفيديو الخاص بهذا العرض بعد حجز موعد معاينة عليه. يتم إرسال الطلب تلقائياً إلى فريق المكتب بعد نجاح الحجز.',
                            style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody, height: 1.5),
                          ),
                          AppTheme.gapHeightSmall,
                          // Strong deterrent notice (per requirement)
                          Container(
                            padding: AppTheme.paddingAllSmall,
                            decoration: BoxDecoration(
                              color: AppTheme.errorRed.withOpacity(0.08),
                              borderRadius: AppTheme.radiusSmall,
                              border: Border.all(color: AppTheme.errorRed.withOpacity(0.3)),
                            ),
                            child: const Text(
                              '⚠️ حجز الموعد يُعتبر التزاماً. إلغاء متكرر أو عدم حضور قد يؤثر على صلاحية طلبات الفيديو المستقبلية. الفيديو يُرسل بشكل خاص بعد التحقق من الحجز.',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: AppTheme.fontSizeSmall,
                                height: 1.4,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          AppTheme.gapHeightMedium,

                          // 🎬 VID-001 (2026-08-15): كان الزر يمرّر `offer.vdo`
                          // مباشرةً لمشغّل الفيديو. لكن `vdo` **ليس دائماً
                          // رابطاً**: حين يختار المُعلِن «أريد إرفاق فيديو»
                          // يُحفظ العَلَم النصّي `"wa"` (مؤكَّد حياً: العرضان
                          // 3 و14 قيمتهما "wa" حرفياً). فكان المشغّل يستقبل
                          // `Uri.parse("wa")` ويفشل ⇒ **إشارة تعجب** بلا أي
                          // تفسير للمستخدم (بلاغ المالك).
                          // الآن: العَلَم يفتح واتساب المكتب برسالة تلقائية
                          // فيها رقم العرض، والرابط الحقيقي يشغّل المشغّل.
                          if (auth.isLoggedIn)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _isVideoOnRequest(offer.vdo)
                                    ? _requestVideoViaWhatsApp(offer)
                                    : _playVideo(offer.vdo),
                                icon: Icon(_isVideoOnRequest(offer.vdo)
                                    ? Icons.smart_display_outlined
                                    : Icons.play_circle_outline),
                                label: Text(_isVideoOnRequest(offer.vdo)
                                    ? 'اطلب الفيديو عبر واتساب'
                                    : 'مشاهدة الفيديو'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryGold,
                                  foregroundColor: AppTheme.deepBlack,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            )
                          else
                            const Text(
                              'سجّل الدخول لتتمكن من مشاهدة الفيديو',
                              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
                            ),
                        ],
                      ),
                    ),
                    AppTheme.gapHeightXL,
                  ],
                  
                  // ✅ Fix for Bug #8: عرض معلومات المراجعة للإدارة فقط
                  if (offer.vdo.isNotEmpty && auth.isAdmin) ...[
                    AppTheme.gapHeightSmall,
                    Container(
                      padding: AppTheme.paddingAllLarge,
                      decoration: BoxDecoration(
                        color: AppTheme.infoBlue.withOpacity(0.08),
                        borderRadius: AppTheme.radiusLarge,
                        border: Border.all(color: AppTheme.infoBlue.withOpacity(0.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.admin_panel_settings, color: AppTheme.infoBlue, size: 20),
                            AppTheme.gapWidthSmall,
                            const Expanded(
                              child: Text(
                                'معلومات للمراجعة (للإدارة فقط)',
                                style: TextStyle(
                                    color: AppTheme.infoBlue,
                                    fontSize: AppTheme.fontSizeSubtitle,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ]),
                          AppTheme.gapHeightSmall,
                          Row(
                            children: [
                              const Icon(Icons.tag, color: AppTheme.infoBlue, size: 16),
                              AppTheme.gapWidthSmall,
                              Text(
                                'رقم العرض: #${offer.offerNumber ?? 0}',
                                style: const TextStyle(
                                    color: AppTheme.textWhite,
                                    fontSize: AppTheme.fontSizeBody,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                          AppTheme.gapHeightSmall,
                          Row(
                            children: [
                              const Icon(Icons.person, color: AppTheme.infoBlue, size: 16),
                              AppTheme.gapWidthSmall,
                              Expanded(
                                child: Text(
                                  'المعلن: ${_owner?.nm ?? _owner?.usr ?? 'غير معروف'}',
                                  style: const TextStyle(
                                      color: AppTheme.textWhite,
                                      fontSize: AppTheme.fontSizeBody,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          if (_owner?.ph != null && _owner!.ph.isNotEmpty) ...[
                            AppTheme.gapHeightSmall,
                            Row(
                              children: [
                                const Icon(Icons.phone, color: AppTheme.infoBlue, size: 16),
                                AppTheme.gapWidthSmall,
                                Text(
                                  'هاتف المعلن: ${_owner!.ph}',
                                  style: const TextStyle(
                                      color: AppTheme.textWhite,
                                      fontSize: AppTheme.fontSizeBody,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                          AppTheme.gapHeightSmall,
                          const Text(
                            'يمكنك مراجعة هذا العرض في مجموعة الواتساب قبل التأكيد.',
                            style: TextStyle(
                                color: AppTheme.textGrey,
                                fontSize: AppTheme.fontSizeSmall,
                                height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    AppTheme.gapHeightXL,
                  ],

                  // الموقع على الخريطة (إذا exact_loc موجود)
                  if (offer.exactLoc.contains(',')) ...[
                    const Row(children: [
                      Icon(Icons.map, color: AppTheme.primaryGold),
                      AppTheme.gapWidthSmall,
                      Text('الموقع على الخريطة',
                          style: TextStyle(
                              color: AppTheme.primaryGold,
                              fontSize: AppTheme.fontSizeTitle,
                              fontWeight: FontWeight.bold)),
                    ]),
                    AppTheme.gapHeightSmall,
                    Builder(builder: (_) {
                      final parts = offer.exactLoc.split(',');
                      final lat = double.tryParse(parts[0].trim());
                      final lng = double.tryParse(parts[1].trim());
                      if (lat == null || lng == null) return const SizedBox();
                      return LocationViewer(lat: lat, lng: lng);
                    }),
                    AppTheme.gapHeightXL,
                  ],

                  // 📸 تنويه إداري: العرض صُوِّر بمصوّر المكتب (للإدارة فقط).
                  // المصدر: photography_tasks.off_id عبر إيدج بحارس دور — لا من
                  // specs (مقروء anon ⇒ يتسرّب). يُجلب مرة عند فتح الشاشة للإدارة.
                  if (_officePhotoInfo != null) ...[
                    AppTheme.gapHeightLarge,
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.cyan.withOpacity(0.10),
                        borderRadius: AppTheme.radiusMedium,
                        border: Border.all(color: Colors.cyan.withOpacity(0.45)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.photo_camera_front_rounded,
                              color: Colors.cyan, size: 20),
                          AppTheme.gapWidthSmall,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'صُوِّر بواسطة مصوّر المكتب',
                                  style: TextStyle(
                                      color: Colors.cyan,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  [
                                    if ((_officePhotoInfo!['photographer_name'] ?? '')
                                        .toString().isNotEmpty)
                                      'المصوّر: ${_officePhotoInfo!['photographer_name']}',
                                    'تنويه داخلي للإدارة فقط',
                                  ].join(' — '),
                                  style: const TextStyle(
                                      color: Colors.cyan, fontSize: AppTheme.fontSizeCaption),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // تفاصيل سند الملكية (للكل كمعلومة نصية، وللموظفين كمعاينة)
                  if (offer.docTp >= 0) ...[
                    AppTheme.gapHeightXL,
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('سند الملكية',
                            style: TextStyle(
                                color: AppTheme.primaryGold,
                                fontSize: AppTheme.fontSizeTitle,
                                fontWeight: FontWeight.bold)),
                        if (auth.userModel != null && auth.userModel!.role >= UserRole.employee && offer.docImg.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              if (offer.docImg.toLowerCase().endsWith('.pdf')) {
                                launchUrl(Uri.parse(offer.docImg), mode: LaunchMode.externalApplication);
                              } else {
                                _openImageViewer([offer.docImg], 0);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppTheme.infoBlue.withOpacity(0.1),
                                borderRadius: AppTheme.radiusXL,
                                border: Border.all(color: AppTheme.infoBlue.withOpacity(0.3)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.file_present, color: AppTheme.infoBlue, size: 16),
                                  AppTheme.gapWidthXS,
                                  Text('معاينة السند (إدارة)', style: TextStyle(color: AppTheme.infoBlue, fontSize: AppTheme.fontSizeSmall, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    AppTheme.gapHeightSmall,
                    _spec(Icons.description, 'نوع السند', AppUtils.deedTypeText(offer.docTp, offer.typ)),
                    AppTheme.gapHeightSmall,
                  ],

                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: AppTheme.getGridColumns(
                        context,
                        mobile: 2,
                        tablet: 2,
                        desktop: 4,
                      ),
                      mainAxisSpacing: AppTheme.spacingSmall,
                      crossAxisSpacing: AppTheme.spacingSmall,
                      childAspectRatio: AppTheme.responsiveValue(
                        context,
                        mobile: 3.0,
                        tablet: 3.5,
                        desktop: 4.0,
                      ),
                    ),
                    itemCount: 4,
                    itemBuilder: (context, index) {
                      switch (index) {
                        case 0:
                          return _spec(Icons.category, 'النوع',
                              offer.typ == 0 ? 'عقار' : 'سيارة');
                        case 1:
                          return _spec(Icons.swap_horiz, 'المعاملة',
                              offer.trx == 0 ? 'بيع' : 'إيجار');
                        case 2:
                          return _spec(Icons.visibility, 'المشاهدات', '${offer.vws}');
                        case 3:
                          return _spec(Icons.favorite, 'الإعجابات', '${offer.fvs}');
                        default:
                          return const SizedBox.shrink();
                      }
                    },
                  ),
                  const SizedBox(height: 25),

                  // ⚖️ بطاقة التوثيق القانوني وكتابة العقود المعتمدة (Legal Verification Card)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 25),
                    padding: AppTheme.paddingAllLarge,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppTheme.lightGold,
                          AppTheme.surfaceBlack,
                        ],
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                      ),
                      borderRadius: AppTheme.radiusLarge,
                      border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryGold.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: AppTheme.paddingAllSmall,
                              decoration: BoxDecoration(
                                color: AppTheme.primaryGold.withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.gavel, color: AppTheme.primaryGold, size: 22),
                            ),
                            AppTheme.gapWidthMedium,
                            const Expanded(
                              child: Text(
                                'الضمان والتوثيق القانوني المعتمد ⚖️',
                                style: TextStyle(
                                  color: AppTheme.primaryGold,
                                  fontSize: AppTheme.fontSizeSubtitle,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        AppTheme.gapHeightMedium,
                        const Text(
                          'يقدم المكتب العقاري خدمة التوثيق القانوني المأجور وتنظيم العقود أصولاً لضمان حق الطرفين. عند تقديم طلب إتمام المعاملة، يتولى فريقنا القانوني تدقيق صحة سندات الملكية (طابو، حكم محكمة، مواصلات) وخلوها من الإشارات والنزاعات قبل إتمام الصفقة.',
                          style: TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: AppTheme.fontSizeBody,
                            height: 1.6,
                          ),
                        ),
                        AppTheme.gapHeightMedium,
                        const Row(
                          children: [
                            Icon(Icons.verified_user, color: AppTheme.successGreen, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'توثيق قانوني • عقود معتمدة • استشارات محامين',
                              style: TextStyle(
                                color: AppTheme.successGreen,
                                fontSize: AppTheme.fontSizeCaption,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // زر نشر على السوشال (للمالك خصوصاً)
                  if (isOwner)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _offer!.socPub >= 1
                            ? null
                            : (_publishing ? null : _shareAndMark),
                        icon: _publishing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primaryGold),
                              )
                            : Icon(
                                _offer!.socPub >= 1
                                    ? Icons.check_circle
                                    : Icons.campaign,
                                color: AppTheme.primaryGold),
                        label: Text(
                          _publishing
                              ? 'جاري النشر...'
                              : (_offer!.socPub >= 1
                                  ? 'تم النشر ✅'
                                  : 'نشر على وسائل التواصل'),
                          style:
                              const TextStyle(color: AppTheme.primaryGold),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                              color: AppTheme.primaryGold),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  if (isOwner) AppTheme.gapHeightSmall,

                  // 🚀 زر ترقية بالنقاط للمالك أو تعيين أولوية للإدارة
                  if (isOwner && !auth.isAdmin)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () =>
                            context.push('/user/boost-offer/${offer.id}'),
                        icon: const Icon(Icons.rocket_launch,
                            color: AppTheme.deepBlack),
                        label: const Text('ترقية العرض بالنقاط 🚀',
                            style: TextStyle(
                                color: AppTheme.deepBlack,
                                fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryGold,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),

                                    // أزرار مراجعة العرض — للإدارة فقط للعروض غير المنشورة
                  if (auth.isAdmin && offer.iPub == 0) ...[
                    AppTheme.gapHeightSmall,
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.warningOrange.withOpacity(0.08),
                        borderRadius: AppTheme.radiusLarge,
                        border: Border.all(color: AppTheme.warningOrange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => _rejectOffer(offer),
                              icon: const Icon(Icons.cancel, color: AppTheme.errorRed, size: 20),
                              label: const Text('رفض',
                                  style: TextStyle(color: AppTheme.errorRed, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium)),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                          Container(width: 1, height: 32, color: AppTheme.warningOrange.withOpacity(0.3)),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: () => _approveOffer(offer),
                              icon: const Icon(Icons.check_circle, color: AppTheme.successGreen, size: 20),
                              label: const Text('قبول',
                                  style: TextStyle(color: AppTheme.successGreen, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeMedium)),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // خيار أولوية النشر للإدارة + زر الحذف
                  if (auth.isAdmin) ...[
                    AppTheme.gapHeightSmall,
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _showAdminPrioritySheet(context, offer),
                            icon: const Icon(Icons.admin_panel_settings,
                                color: AppTheme.deepBlack),
                            label: const Text('أولوية (إدارة)',
                                style: TextStyle(
                                    color: AppTheme.deepBlack,
                                    fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeBody)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.lightGold,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        AppTheme.gapWidthSmall,
                        ElevatedButton(
                          onPressed: () => _showAdminDeleteDialog(context, offer),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.errorRed,
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          ),
                          child: const Icon(Icons.delete_forever, color: AppTheme.scaffoldBackground),
                        ),
                      ],
                    ),
                  ],

                  if (isOwner || auth.isAdmin) AppTheme.gapHeightMedium,

                  // زر الحجز — مخفي عن المالك والإدارة
                  if (!isOwner && !auth.isAdmin)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: offer.avl.isEmpty
                          ? null // تعطيل إذا لا مواعيد
                          : () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) =>
                                  BookAppointmentSheet(offer: offer)),
                      style: offer.avl.isEmpty
                          ? ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.surfaceBlack,
                              disabledForegroundColor: AppTheme.textGrey,
                            )
                          : null,
                      child: Text(
                        offer.avl.isEmpty
                            ? 'لا توجد مواعيد متاحة حالياً'
                            : 'حجز موعد للمعاينة',
                      ),
                    ),
                  ),
                  // ⭐ تم إزالة زر التقييم من صفحة العرض — التقييم متاح فقط
                  // من شاشة المواعيد/الصفقات المكتملة حيث يكون هناك تعامل فعلي
                  // بين الطرفين (check_rating_valid trigger يمنع التقييم بدون صفقة)
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _shareAndMark() async {
    if (_offer == null || _publishing) return;

    // ✅ منع التكرار: إذا تم النشر مسبقاً (soc_pub >= 1)
    if (_offer!.socPub >= 1) {
      if (mounted) {
        AppTheme.showSnackBar(
          context,
          const SnackBar(
              content: Text('تم نشر هذا العرض مسبقاً ✅'),
              duration: Duration(seconds: 2)),
        );
      }
      return;
    }

    setState(() => _publishing = true);

    try {
      final config = context.read<ConfigProvider>().config;
      final auth = context.read<AuthProvider>();
      final userId = auth.userModel?.uid ?? '';

      // 📱 مشاركة يدوية (النشر التلقائي يتم عند موافقة الأدمن عبر _shared/social_publisher)
      final text =
          BusinessService().generateSocialPost(_offer!, config: config);
      await SharePlus.instance
          .share(ShareParams(text: text, subject: _offer!.ttl));

      // تعليم + منح نقاط
      final marked = await BusinessService().markSocialPublished(
        _offer!.id,
        text,
        userId: userId,
      );
      if (marked) {
        final pts = config?.socialSharePoints ?? 100;
        await BusinessService()
            .awardEvent(userId, config, 'soc', fallback: pts);
        await _load();
        await auth.refreshUser();
        if (mounted) {
          AppTheme.showSnackBar(
            context,
            SnackBar(content: Text('تم المشاركة ✅ (+$pts نقطة)')),
          );
        }
      } else {
        await _load();
        if (mounted) {
          AppTheme.showSnackBar(
            context,
            const SnackBar(content: Text('تم نشر هذا العرض مسبقاً ✅')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showSnackBar(
          context,
          const SnackBar(content: Text('حدث خطأ أثناء النشر')),
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _openImageViewer(List<String> images, int initialIndex) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _FullScreenImageViewer(images: images, initialIndex: initialIndex),
    ));
  }

  // ✅ Fix for Bug #10: تشغيل الفيديو مباشرة بدون حجز موعد
  void _playVideo(String videoUrl) {
    if (videoUrl.isEmpty) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => OfferVideoPlayer(videoUrl: videoUrl),
    ));
  }

  /// 🎬 VID-001: هل `vdo` عَلَم «الفيديو عند الطلب» لا رابطاً؟
  ///
  /// عند إنشاء العرض، اختيار «أريد إرفاق فيديو» يحفظ العَلَم النصّي `"wa"`
  /// بدل رابط. أي قيمة ليست رابط `http(s)` تُعامَل كطلب عبر واتساب — وهذا
  /// أأمن من فحص `== 'wa'` وحده: أي قيمة قديمة أو مشوّهة لن تصل للمشغّل
  /// فتنهار عليه، بل تُوجَّه للمسار الآمن.
  bool _isVideoOnRequest(String vdo) {
    final v = vdo.trim();
    if (v.isEmpty) return false;
    return !v.startsWith('http://') && !v.startsWith('https://');
  }

  /// 🎬 VID-001: يفتح واتساب المكتب برسالة تلقائية فيها رقم العرض.
  ///
  /// ⚠️ قاعدة المالك الصارمة: لا معلومات تواصل لصاحب العرض أبداً — الطلب
  /// يذهب لواتساب **المكتب** (`txts.videoRequestWhatsApp`) لا للمُعلِن.
  Future<void> _requestVideoViaWhatsApp(OfferModel offer) async {
    final config = context.read<ConfigProvider>().config;
    final raw = (config?.videoRequestWhatsApp ?? '').trim();

    // §13: لا نبتلع نقص الإعداد — نعلنه بالعربية بدل فشل صامت.
    if (raw.isEmpty) {
      if (!mounted) return;
      AppTheme.showSnackBar(context, const SnackBar(
        content: Text('خدمة طلب الفيديو غير متاحة حالياً — يرجى مراسلة المكتب'),
      ));
      return;
    }

    // تطبيع الرقم للصيغة الدولية التي يقبلها wa.me (بلا + ولا أصفار بادئة).
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = '963${digits.substring(1)}';
    if (!digits.startsWith('963')) digits = '963$digits';

    final num0 = offer.offerNumber ?? 0;
    final msg = '🎬 طلب مشاهدة فيديو\n'
        'رقم العرض: #$num0\n'
        'العنوان: ${offer.ttl}';
    final uri = Uri.parse(
        'https://wa.me/$digits?text=${Uri.encodeComponent(msg)}');

    try {
      // نستخدم wa.me لا whatsapp:// — يعمل حتى لو تعذّر فتح التطبيق
      // (يفتح المتصفح ثم يحوّل)، فلا يفشل الطلب بصمت.
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        AppTheme.showSnackBar(context, const SnackBar(
          content: Text('تعذّر فتح واتساب — تأكد من تثبيته'),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      AppTheme.showSnackBar(context, const SnackBar(
        content: Text('تعذّر فتح واتساب — تأكد من تثبيته'),
      ));
    }
  }

  Widget _spec(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: AppTheme.surfaceBlack,
          borderRadius: AppTheme.radiusMedium,
          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.2))),
      child: // 🧱 UI-OVF-001: يُستخدم داخل شبكة بنسبة 3.0 — سطر نص أطول = فيضان.
             FitTile(child: Row(children: [
        Icon(icon, color: AppTheme.primaryGold, size: 18),
        AppTheme.gapWidthSmall,
        Expanded(
            child: Text('$label: $value',
                style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeMedium),
                overflow: TextOverflow.ellipsis)),
      ])),
    );
  }
}

/// عارض صور بملء الشاشة — تصفح + زوم + إغلاق
class _FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  const _FullScreenImageViewer({required this.images, required this.initialIndex});

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _ctrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppTheme.scaffoldBackground, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_current + 1} / ${widget.images.length}',
          style: const TextStyle(color: AppTheme.scaffoldBackground, fontSize: AppTheme.fontSizeSubtitle),
        ),
        centerTitle: true,
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Center(
            child: Image.network(
              widget.images[i],
              fit: BoxFit.contain,
              width: double.infinity,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image, color: AppTheme.textGrey, size: 80),
            ),
          ),
        ),
      ),
    );
  }
}
