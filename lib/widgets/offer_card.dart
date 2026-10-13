import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart' show Box;
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../models/offer_model.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/app_utils.dart';
import '../core/services/local_cache_service.dart';
import '../core/services/business_service.dart';
import '../providers/auth_provider.dart';
import '../providers/config_provider.dart';

class OfferCard extends StatefulWidget {
  final OfferModel offer;
  const OfferCard({super.key, required this.offer});

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  // لا نخزّن حالة القلب — تُقرأ حيّاً من favoritesListenable حتى تتزامن البطاقة
  // مع شاشة التفاصيل وأي شاشة ثانية تلقائياً (إصلاح 2026-07-27)

  Widget _favButton(BuildContext ctx, bool isFav, bool own) {
    return GestureDetector(
      onTap: _toggleFav,
      child: Opacity(
        opacity: own ? 0.35 : 1,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isFav
                ? AppTheme.errorRed.withOpacity(0.1)
                : Colors.white.withOpacity(0.05),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? AppTheme.errorRed : AppTheme.textGrey,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildFavButton(BuildContext ctx) {
    final own =
        ctx.read<AuthProvider>().userModel?.uid == widget.offer.usrId;
    final listenable = LocalCacheService().favoritesListenable;
    if (listenable == null) {
      return _favButton(ctx, LocalCacheService().isFavorite(widget.offer.id), own);
    }
    return ValueListenableBuilder<Box>(
      valueListenable: listenable,
      builder: (_, __, ___) => _favButton(
          ctx, LocalCacheService().isFavorite(widget.offer.id), own),
    );
  }

  Future<void> _toggleFav() async {
    // 🚫 عرضي الخاص: لا إعجاب ولا نقاط (حسم نهائي عند السيرفر أيضاً)
    final myUid = context.read<AuthProvider>().userModel?.uid;
    if (myUid != null && widget.offer.usrId == myUid) {
      if (mounted) {
        AppTheme.showSnackBar(context, const SnackBar(
          content: Text('لا يمكن الإعجاب بالعرض الخاص بك 👌'),
          duration: Duration(seconds: 1),
        ));
      }
      return;
    }
    final added = await LocalCacheService().toggleFavorite(widget.offer.id);
    // لا setState — الـ listenable يعيد بناء القلب تلقائياً
    if (mounted) {
      AppTheme.showSnackBar(context, SnackBar(
        content: Text(added ? 'أُضيف للمفضلة ❤️' : 'أُزيل من المفضلة'),
        duration: const Duration(seconds: 1),
      ));
    }
    if (added && mounted) {
      final auth = context.read<AuthProvider>();
      if (auth.isLoggedIn) {
        final config = context.read<ConfigProvider>().config;
        final result = await BusinessService().awardEventDetailed(
          auth.userModel!.uid,
          config,
          'like',
          fallback: 10,
          offerId: widget.offer.id,
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
          // بلغ الحد اليومي — الإعجاب انحفظ، بس بلا منحة وهمية
          AppTheme.showSnackBar(context, SnackBar(
            content: Text(
                'إعجابك انحفظ ❤️ — بس وصلت للحد اليومي (${result.limit} إعجابات)، النقاط ترجع بكرا 🌙'),
            duration: const Duration(seconds: 2),
          ));
        }
      }
    }
    // إزالة الإعجاب لا تخصم نقاط (2026-07-27): المنح محدود سيرفرياً بـ ١٠ إعجابات/يوم
    // والخصم كان يعاقب حتى من لم تقُبل نقاطه أصلاً (سقف يومي/رفض السيرفر).
  }

  static Widget _boostBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Text(text,
          style: const TextStyle(
              color: Colors.white, fontSize: AppTheme.fontSizeXS, fontWeight: FontWeight.bold)),
    );
  }

  // ✅ Fix for Bug #27: عداد تنازلي للإعلان المميز
  static Widget _countdownBadge(DateTime endDate) {
    final now = DateTime.now();
    final remaining = endDate.difference(now);
    
    String text;
    Color color;
    
    if (remaining.isNegative) {
      text = 'منتهي';
      color = Colors.grey;
    } else if (remaining.inDays > 0) {
      text = '${remaining.inDays} يوم';
      color = remaining.inDays <= 3 ? Colors.orange : AppTheme.primaryGold;
    } else if (remaining.inHours > 0) {
      text = '${remaining.inHours} ساعة';
      color = Colors.orange;
    } else if (remaining.inMinutes > 0) {
      text = '${remaining.inMinutes} دقيقة';
      color = Colors.red;
    } else {
      text = 'منتهي';
      color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer, color: Colors.white, size: 12),
          const SizedBox(width: 2),
          Text(text,
              style: const TextStyle(
                  color: Colors.white, fontSize: AppTheme.fontSizeXS, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSpecItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.primaryGold.withOpacity(0.7), size: 14),
        AppTheme.gapWidthXS,
        Text(
          text,
          style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.offer;
    final priceLabel = AppUtils.formatPrice(offer.prc, currency: offer.cur);
    final isProperty = offer.typ == 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: AppTheme.primaryGold.withOpacity(0.15), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 15,
              offset: const Offset(0, 8))
        ],
      ),
      child: InkWell(
        onTap: () => context.push('/offer/${offer.id}'),
        borderRadius: BorderRadius.circular(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // 🖼️ الصورة الرئيسية مع Gradient خفيف
                Hero(
                  tag: 'off_${offer.id}',
                  child: Container(
                    height: 220,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                      color: AppTheme.surfaceBlack,
                      image: offer.imgs.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(offer.imgs[0]),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.6),
                          ],
                        ),
                      ),
                      child: offer.imgs.isEmpty
                          ? Center(
                              child: Icon(Icons.apartment_outlined,
                                  color: AppTheme.primaryGold.withOpacity(0.2),
                                  size: 64),
                            )
                          : null,
                    ),
                  ),
                ),

                // 🏷️ شارات الحالة (للبيع / للإيجار)
                Positioned(
                  top: 15,
                  right: 15,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: offer.trx == 0 ? AppTheme.successGreen : AppTheme.infoBlue,
                      borderRadius: AppTheme.radiusMedium,
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                    ),
                    child: Text(
                      offer.trx == 0 ? 'للبيع' : 'للإيجار',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: AppTheme.fontSizeSmall),
                    ),
                  ),
                ),

                // 🏷️ شارات الترقية (spd)
                Positioned(
                  top: 15,
                  left: 15,
                  child: Wrap(
                    spacing: 4,
                    children: [
                      if (offer.iPin == 1) _boostBadge('📌 مثبت', AppTheme.warningOrange),
                      if (offer.iFms == 1) ...[
                        _boostBadge('⭐ مميز', AppTheme.primaryGold),
                        // ✅ Fix for Bug #27: عداد تنازلي للإعلان المميز
                        if (offer.fmsEnd != null)
                          _countdownBadge(offer.fmsEnd!),
                      ],
                    ],
                  ),
                ),

                // 💰 السعر (بتصميم عصري أسفل الصورة)
                Positioned(
                  bottom: 12,
                  right: 15,
                  child: Text(
                    priceLabel,
                    style: const TextStyle(
                      color: AppTheme.primaryGold,
                      fontWeight: FontWeight.w900,
                      fontSize: AppTheme.fontSizeHeadline,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                ),

                // ⏱️ الوقت (منذ متى أضيف)
                Positioned(
                  bottom: 12,
                  left: 15,
                  child: Text(
                    AppUtils.formatTimestamp(offer.tsCrt.toIso8601String()),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: AppTheme.fontSizeXS,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            Padding(
              padding: AppTheme.paddingAllLarge,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🏠 العنوان + رقم العرض
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          offer.ttl,
                          style: const TextStyle(
                              color: AppTheme.textWhite,
                              fontSize: 17,
                              fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (offer.offerNumber != null)
                        Text(
                          '#${offer.offerNumber}',
                          style: TextStyle(
                              color: AppTheme.primaryGold.withOpacity(0.6),
                              fontSize: AppTheme.fontSizeSmall,
                              fontFamily: 'monospace'),
                        ),
                    ],
                  ),
                  AppTheme.gapHeightSmall,

                  // 📊 المواصفات السريعة (أيقونات)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSpecItem(Icons.location_on_outlined, offer.loc['city'] ?? 'جرمانا'),
                        const SizedBox(width: 15),
                        if (isProperty) ...[
                          if (offer.specs['area'] != null)
                            _buildSpecItem(Icons.straighten, '${offer.specs['area']} م²'),
                          if (offer.specs['rooms'] != null) ...[
                            const SizedBox(width: 15),
                            _buildSpecItem(Icons.bed_outlined, '${offer.specs['rooms']} غرف'),
                          ],
                        ] else ...[
                          if (offer.specs['brand'] != null)
                            _buildSpecItem(Icons.directions_car_outlined, '${offer.specs['brand']}'),
                          if (offer.specs['year'] != null) ...[
                            const SizedBox(width: 15),
                            _buildSpecItem(Icons.calendar_today_outlined, '${offer.specs['year']}'),
                          ],
                        ],
                      ],
                    ),
                  ),

                  AppTheme.gapHeightLarge,
                  const Divider(color: Colors.white10, height: 1),
                  AppTheme.gapHeightMedium,

                  // 🛡️ هوية المكتب (التصميم الاحترافي)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryGold.withOpacity(0.08),
                          borderRadius: AppTheme.radiusMedium,
                          border: Border.all(color: AppTheme.primaryGold.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon((offer.ownerLabel ?? '').contains('✓') ? Icons.verified_rounded : Icons.storefront_outlined,
                                color: (offer.ownerLabel ?? '').contains('✓') ? AppTheme.successGreen : AppTheme.primaryGold, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              offer.ownerLabel ?? 'إدارة المكتب العقاري',
                              style: const TextStyle(
                                  color: AppTheme.primaryGold,
                                  fontSize: AppTheme.fontSizeCaption,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                      // زر المفضلة (يتعتّم على عروضك الخاصة) — حيّ ومتزامن مع كل الشاشات
                      Builder(builder: _buildFavButton),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
