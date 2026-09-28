import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/config_provider.dart';
import '../../providers/offer_provider.dart';
import '../../models/offer_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/supabase_service.dart';
import '../../core/utils/error_utils.dart';
import '../../widgets/office_logo_placeholder.dart';

/// شاشة ترقيات العرض (spd)
/// 5 خيارات: تمديد/تجديد / تثبيت / Boost / خصم 5% / عرض مميّز
class BoostOfferScreen extends StatefulWidget {
  final String offerId;
  const BoostOfferScreen({super.key, required this.offerId});

  @override
  State<BoostOfferScreen> createState() => _BoostOfferScreenState();
}

class _BoostOfferScreenState extends State<BoostOfferScreen> {
  OfferModel? _offer;
  bool _loading = true;
  bool _processing = false;
  int _othersCount = 0; // عروضه النشطة الأخرى (لحسم التجديد المجاني)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final prov = context.read<OfferProvider>();
    final userId = context.read<AuthProvider>().userModel?.uid;
    var offer = prov.getOfferById(widget.offerId);
    offer ??= await prov.fetchOfferById(widget.offerId, userId: userId);
    var others = 0;
    if (userId != null) {
      try {
        final rows = await SupabaseService().client
            .from('offers')
            .select('id')
            .eq('usr_id', userId)
            .eq('i_del', 0)
            .inFilter('sts', [0, 1, 2, 5]);
        others = (rows as List)
            .where((r) => r['id']?.toString() != widget.offerId)
            .length;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _offer = offer;
      _othersCount = others;
      _loading = false;
    });
  }

  Future<void> _purchase(String boostType, int cost, String label) async {
    final auth = context.read<AuthProvider>();
    final user = auth.userModel;
    if (user == null || _offer == null) return;

    if (user.pt < cost) {
      _snack('رصيدك ${user.pt} نقطة، تحتاج $cost نقطة');
      return;
    }

    // تأكيد قبل الشراء
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Row(children: [
          Icon(Icons.shopping_cart, color: AppTheme.primaryGold),
          AppTheme.gapWidthSmall,
          Text('تأكيد الشراء',
              style: TextStyle(color: AppTheme.textWhite)),
        ]),
        content: Text(
          cost == 0
              ? 'سيتم تجديد العرض مجاناً لمدة 30 يوم إضافية.\n\nهل تريد المتابعة؟'
              : 'هل تريد شراء "$label" بـ $cost نقطة؟\n\n'
                  'رصيدك الحالي: ${user.pt} نقطة\n'
                  'الرصيد بعد الشراء: ${user.pt - cost} نقطة',
          style: const TextStyle(color: AppTheme.textGrey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء',
                style: TextStyle(color: AppTheme.textGrey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(cost == 0 ? 'تجديد' : 'شراء',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _processing = true);
    try {
      // ✅ Secure via Edge Function (user-offers) — purchase_offer_boost is locked to service_role
      final res = await SupabaseService().invokeFunction(
        'user-offers',
        body: {
          'action': 'purchase_boost',
          'user_uid': user.uid,
          'offer_id': _offer!.id,
          'boost_type': boostType,
        },
      );

      if (!mounted) return;
      setState(() => _processing = false);

      final data = res.data as Map<String, dynamic>?;
      final result = data?['result'] as Map<String, dynamic>? ?? data;
      if (result?['success'] == true || data?['success'] == true) {
        await auth.refreshUser();
        await context.read<OfferProvider>().fetchOffers();
        _snack('✅ تم تفعيل "$label" بنجاح');
        if (mounted) Navigator.pop(context, true);
      } else {
        final err = result?['error']?.toString() ?? 'UNKNOWN';
        _snack(ErrorUtils.arabicMessage(err));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      _snack(ErrorUtils.arabicMessage(e));
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(m)));
  }

  /// باقة فعالة (تشمل فترة السماح) — مطابق لمنطق السيرفر
  bool get _hasActivePkg {
    final u = context.read<AuthProvider>().userModel;
    if (u == null || u.bPkg == 0) return false;
    final now = DateTime.now();
    return (u.pkgEnd?.isAfter(now) ?? false) ||
        (u.pkgGrace?.isAfter(now) ?? false);
  }

  /// تكلفة التجديد الفعلية — قاعدة المالك (مطابقة لـ purchase_offer_boost):
  /// 🔁 2026-09-22: مدة صلاحية العرض من الإعدادات (qta.offerLife) — افتراضياً 90
  int get _offerLifeDays {
    final qta = context.read<ConfigProvider>().config?.data['qta'];
    if (qta is Map) {
      final v = qta['offerLife'];
      if (v is num && v >= 1) return v.toInt();
    }
    return 90;
  }

  DateTime _offerExpiry(OfferModel o) =>
      o.tsEnd ?? (o.tsPub ?? o.tsCrt).add(Duration(days: _offerLifeDays));
  /// باقة فعالة ⇒ 0 | بلا باقة + عرض وحيد + آخر يومين (غير منتهٍ) ⇒ 0 | غير ذلك ⇒ spd.ren
  int _renCost(Map<String, dynamic> spd) {
    final base = (spd['ren'] ?? 500) as int;
    if (_hasActivePkg) return 0;
    final expDate = _offer == null ? null : _offerExpiry(_offer!);
    final expired = expDate != null && expDate.isBefore(DateTime.now());
    final daysLeft = expDate?.difference(DateTime.now()).inDays ?? _offerLifeDays;
    if (_othersCount == 0 && !expired && daysLeft <= 2) return 0;
    return base;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        body: Center(
            child: CircularProgressIndicator(color: AppTheme.primaryGold)),
      );
    }
    if (_offer == null) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBackground,
        appBar: AppBar(title: const Text('ترقية العرض')),
        body: const Center(
          child: Text('العرض غير موجود',
              style: TextStyle(color: AppTheme.textGrey)),
        ),
      );
    }

    final auth = context.watch<AuthProvider>();
    final config = context.watch<ConfigProvider>().config;
    final user = auth.userModel;
    final spd = config?.data['spd'] as Map<String, dynamic>? ??
        {'ren': 500, 'pin': 2000, 'bst': 4000, 'dsc5': 3000, 'fms': 8000};

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('ترقية العرض'),
        backgroundColor: AppTheme.scaffoldBackground,
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: AppTheme.paddingAllLarge,
            child: Column(
              children: [
                _offerSummary(_offer!),
                AppTheme.gapHeightLarge,
                _pointsBalance(user?.pt ?? 0),
                AppTheme.gapHeightXL,
                const Text('🚀 خيارات الترقية',
                    style: TextStyle(
                        color: AppTheme.primaryGold,
                        fontSize: AppTheme.fontSizeSubtitle,
                        fontWeight: FontWeight.bold)),
                AppTheme.gapHeightMedium,

                _boostCard(
                  icon: Icons.refresh,
                  title: _renCost(spd) == 0 ? 'تجديد مجاني ✨' : 'تمديد العرض',
                  description: _renCost(spd) == 0
                      ? 'يتبقى يومان أو أقل على الانتهاء — 30 يوم إضافية مجاناً'
                      : 'إضافة 30 يوم فوق المدة المتبقية بالكامل',
                  cost: _renCost(spd),
                  active: false,
                  boostType: 'ren',
                  color: AppTheme.infoBlue,
                ),
                // ⓘ تنويه المصطلحات: تمديد مدفوع (+30 فوق المتبقي بأي وقت) / تجديد مجاني (قبل يومين)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.infoBlue.withOpacity(0.08),
                    borderRadius: AppTheme.radiusMedium,
                    border:
                        Border.all(color: AppTheme.infoBlue.withOpacity(0.3)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: AppTheme.infoBlue, size: 16),
                      AppTheme.gapWidthSmall,
                      Expanded(
                        child: Text(
                          '«تمديد» مدفوع: يضيف 30 يوم فوق المدة المتبقية بأي وقت.\n«تجديد» مجاني: عندما يتبقى يومان أو أقل على انتهاء العرض.',
                          style: TextStyle(
                              color: AppTheme.textGrey,
                              fontSize: 11.5,
                              height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                _boostCard(
                  icon: Icons.push_pin,
                  title: 'تثبيت في الأعلى',
                  description: 'يظهر العرض الخاص بك بأعلى نتائج البحث لمدة 7 أيام',
                  cost: (spd['pin'] ?? 2000) as int,
                  active: _offer!.iPin == 1,
                  activeUntil: _offer!.pinEnd,
                  boostType: 'pin',
                  color: AppTheme.warningOrange,
                ),
                _boostCard(
                  icon: Icons.rocket_launch,
                  title: 'Boost — وصول أكبر',
                  description: 'ضاعف ظهور العرض الخاص بك للمستخدمين لمدة 14 يوم',
                  cost: (spd['bst'] ?? 4000) as int,
                  active: _offer!.iBst == 1,
                  activeUntil: _offer!.bstEnd,
                  boostType: 'bst',
                  color: Colors.purple,
                ),
                _boostCard(
                  icon: Icons.discount,
                  title: 'خصم 5% على عمولة المكتب',
                  description: 'يخفّض عمولة البيع 5% عند إتمام الصفقة',
                  cost: (spd['dsc5'] ?? 3000) as int,
                  active: _offer!.dscPct > 0,
                  activeUntil: _offer!.dscEnd,
                  boostType: 'dsc5',
                  color: AppTheme.successGreen,
                ),
                // ⭐ الإعلان المميز أصبح مدفوعاً فقط (قرار المالك 2026-07-26 — لا نسخة نقاط)
                _featuredAdCard(),
                AppTheme.gapHeightLarge,
                _infoBox(),
                AppTheme.gapHeightXL,
              ],
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black.withOpacity(0.7),
              child: const Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGold),
              ),
            ),
        ],
      ),
    );
  }

  Widget _offerSummary(OfferModel o) {
    return Container(
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: AppTheme.radiusSmall,
            child: SizedBox(
              width: 60,
              height: 60,
              child: o.imgs.isNotEmpty
                  ? Image.network(o.imgs.first.toString(),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.image, color: AppTheme.textGrey))
                  : const OfficeLogoPlaceholder(logoSize: 26),
            ),
          ),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.ttl,
                    style: const TextStyle(
                        color: AppTheme.textWhite,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 3),
                Text(
                  '${o.prc.toStringAsFixed(0)} ${o.cur == 0 ? '\$' : 'ل.س'}',
                  style: const TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pointsBalance(int pts) {
    return Container(
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryGold, Color(0xFFFFD700)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppTheme.radiusMedium,
      ),
      // 💡 PTS-001 (2026-08-15) بطلب المالك: تنويه تحت الرصيد يشرح للمستخدم
      // أن النقاط تُكتسب باستخدام التطبيق — كان الرقم يظهر بلا أي سياق.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.stars, color: Colors.black, size: 28),
              AppTheme.gapWidthSmall,
              const Text('رصيدك من النقاط:',
                  style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeMedium)),
              const Spacer(),
              Text('$pts',
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 22,
                      fontWeight: FontWeight.bold)),
              AppTheme.gapWidthXS,
              const Text('نقطة',
                  style: TextStyle(
                      color: Colors.black87, fontSize: AppTheme.fontSizeSmall)),
            ],
          ),
          AppTheme.gapHeightXS,
          const Text(
            '💡 يمكنك اكتساب النقاط عن طريق استخدام التطبيق: إضافة العروض، '
            'الدخول اليومي، دعوة الأصدقاء، والتفاعل مع المنصة.',
            style: TextStyle(
                color: Colors.black87,
                fontSize: AppTheme.fontSizeCaption,
                height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _boostCard({
    required IconData icon,
    required String title,
    required String description,
    required int cost,
    required bool active,
    DateTime? activeUntil,
    required String boostType,
    required Color color,
  }) {
    final user = context.watch<AuthProvider>().userModel;
    final canAfford = (user?.pt ?? 0) >= cost;

    // تقييد التجديد (ren): المشترك دائماً (مجاني)، صاحب العرض الوحيد بلا باقة خلال يومين فقط (مجاني)،
    // أصحاب العروض الزائدة/المنتهية يجددون بالنقاط في أي وقت (السيرفر يحسم التكلفة)
    bool isEnabled = true;
    if (boostType == 'ren' && !_hasActivePkg) {
      final expDate = _offer == null ? null : _offerExpiry(_offer!);
      final expired = expDate != null && expDate.isBefore(DateTime.now());
      final daysLeft = expDate?.difference(DateTime.now()).inDays ?? _offerLifeDays;
      if (_othersCount == 0 && !expired && daysLeft > 2) {
        isEnabled = false;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
          color: active ? AppTheme.successGreen : color.withOpacity(0.3),
          width: active ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: AppTheme.paddingAllSmall,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: AppTheme.radiusSmall,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              AppTheme.gapWidthSmall,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontWeight: FontWeight.bold,
                            fontSize: AppTheme.fontSizeMedium)),
                    Text(description,
                        style: const TextStyle(
                            color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$cost',
                      style: TextStyle(
                          color: color,
                          fontSize: AppTheme.fontSizeTitle,
                          fontWeight: FontWeight.bold)),
                  const Text('نقطة',
                      style: TextStyle(
                          color: AppTheme.textGrey, fontSize: AppTheme.fontSizeXS)),
                ],
              ),
            ],
          ),
          if (active && activeUntil != null) ...[
            AppTheme.gapHeightSmall,
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.successGreen.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppTheme.successGreen, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    'مفعّل حتى ${activeUntil.day}/${activeUntil.month}/${activeUntil.year}',
                    style: const TextStyle(
                        color: AppTheme.successGreen,
                        fontSize: AppTheme.fontSizeCaption,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ] else ...[
            AppTheme.gapHeightSmall,
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                onPressed: (isEnabled && canAfford) ? () => _purchase(boostType, cost, title) : null,
                icon: (isEnabled && canAfford)
                    ? Icon(Icons.shopping_cart, color: Colors.black, size: 16)
                    : Icon(isEnabled ? Icons.money_off : Icons.lock,
                        color: Colors.black, size: 16),
                label: Text(!isEnabled
                    ? 'التجديد المجاني قبل يومين من الانتهاء'
                    : cost == 0
                        ? 'تجديد مجاني ✨'
                        : (canAfford
                            ? (boostType == 'ren'
                                ? 'تمديد بـ $cost نقطة'
                                : 'شراء بـ $cost نقطة')
                            : 'نقاطك غير كافية'),
                    style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: AppTheme.fontSizeBody)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: (isEnabled && canAfford) ? color : AppTheme.textGrey,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// بطاقة الإعلان المميز المدفوع — شراء بالمدة (1-4 أسابيع) عبر مسار الدفع اليدوي
  Widget _featuredAdCard() {
    final ending = _offer!.fmsEnd;
    final active = _offer!.iFms == 1 &&
        ending != null &&
        ending.isAfter(DateTime.now());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
        border: Border.all(
            color: AppTheme.primaryGold.withOpacity(active ? 0.6 : 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.star, color: AppTheme.primaryGold, size: 20),
            AppTheme.gapWidthSmall,
            const Expanded(
              child: Text('إعلان مميز',
                  style: TextStyle(
                      color: AppTheme.textWhite,
                      fontSize: AppTheme.fontSizeMedium,
                      fontWeight: FontWeight.bold)),
            ),
            if (active)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.successGreen.withOpacity(0.12),
                  borderRadius: AppTheme.radiusSmall,
                ),
                child: const Text('فعّال',
                    style: TextStyle(
                        color: AppTheme.successGreen,
                        fontSize: AppTheme.fontSizeCaption,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            active
                ? 'إعلانك المميز فعّال حتى: '
                    '${ending.day}/${ending.month}/${ending.year}'
                : 'شارة مميّز + ظهور في قسم خاص — شراء مدفوع بالمدة (1-4 أسابيع)',
            style:
                const TextStyle(color: AppTheme.textGrey, fontSize: 11.5),
          ),
          AppTheme.gapHeightSmall,
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: active
                  ? null
                  : () => context
                      .push('/user/featured-payment?offer=${_offer!.id}'),
              icon: Icon(
                active ? Icons.check_circle : Icons.shopping_cart,
                size: 16,
                color: Colors.black,
              ),
              label: Text(
                active ? 'الإعلان المميز فعّال ✓' : 'شراء إعلان مميز',
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTheme.fontSizeBody),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    active ? AppTheme.textGrey : AppTheme.primaryGold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox() {
    return Container(
      padding: AppTheme.paddingAllMedium,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusMedium,
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppTheme.primaryGold, size: 18),
          AppTheme.gapWidthSmall,
          Expanded(
            child: Text(
              'النقاط تُكتسب من النشاط بالتطبيق (إضافة عروض، إكمال صفقات، دعوة أصدقاء، تسجيل دخول يومي).',
              style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption),
            ),
          ),
        ],
      ),
    );
  }
}
