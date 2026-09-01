import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/broker_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/offer_model.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/office_logo_placeholder.dart';
import '../../widgets/bottom_nav_bar.dart';

/// 🏠 عروض الوسيط — العروض الخاصة به + المُسندة إليه
class BrokerOffersScreen extends StatefulWidget {
  const BrokerOffersScreen({super.key});

  @override
  State<BrokerOffersScreen> createState() => _BrokerOffersScreenState();
}

class _BrokerOffersScreenState extends State<BrokerOffersScreen> {
  int _filter = 0; // 0=الكل, 1=منشور, 2=قيد المراجعة

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
      await context.read<BrokerProvider>().fetchBrokerOffers(id);
    }
  }

  List<OfferModel> _apply(List<OfferModel> offers) {
    switch (_filter) {
      case 1:
        return offers.where((o) => o.sts == 2).toList();
      case 2:
        return offers.where((o) => o.sts == 1).toList();
      default:
        return offers;
    }
  }

  @override
  Widget build(BuildContext context) {
    final broker = context.watch<BrokerProvider>();
    final offers = _apply(broker.offers);

    return Scaffold(
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 1),
      // ➕ 2026-08-31 (طلب المالك): زر إضافة عرض للوسيط من شاشته مباشرة —
      // نفس مسار المستخدم مع إعادة تحميل القائمة عند العودة. حصة العروض
      // يفرضها السيرفر (create_offer_internal) برسالة عربية واضحة.
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryGold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('عرض جديد'),
        onPressed: () async {
          await context.push('/user/add-offer');
          if (mounted) _load();
        },
      ),
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('عروضي'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          // فلاتر الحالة
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _chip('الكل', 0),
                AppTheme.gapWidthSmall,
                _chip('منشور', 1),
                AppTheme.gapWidthSmall,
                _chip('قيد المراجعة', 2),
              ],
            ),
          ),
          Expanded(
            child: broker.isLoading && broker.offers.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : broker.error != null && broker.offers.isEmpty
                    ? _error()
                    : offers.isEmpty
                        ? _empty()
                        : RefreshIndicator(
                        color: AppTheme.primaryGold,
                        onRefresh: () async => _load(),
                        child: ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: offers.length,
                          itemBuilder: (_, i) => _offerTile(offers[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _error() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: AppTheme.errorRed),
            AppTheme.gapHeightLarge,
            const Text('تعذر تحميل عروض الوسيط',
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

  Widget _empty() => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_work,
                size: 72, color: AppTheme.textGrey.withOpacity(0.3)),
            AppTheme.gapHeightLarge,
            const Text('لا توجد عروض مرتبطة بك',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 15)),
          ],
        ),
      );

  Widget _chip(String label, int value) {
    final selected = _filter == value;
    return FilterChip(
      label: Text(label,
          style: TextStyle(
            color: selected ? AppTheme.deepBlack : AppTheme.textWhite,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          )),
      selected: selected,
      selectedColor: AppTheme.primaryGold,
      backgroundColor: AppTheme.surfaceBlack,
      checkmarkColor: AppTheme.deepBlack,
      side: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3)),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _offerTile(OfferModel o) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
      ),
      child: ListTile(
        contentPadding: AppTheme.paddingAllMedium,
        leading: ClipRRect(
          borderRadius: AppTheme.radiusMedium,
          child: o.imgs.isNotEmpty
              ? Image.network(o.imgs[0],
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _imgPlaceholder())
              : _imgPlaceholder(),
        ),
        title: Text(o.ttl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTheme.gapHeightXS,
            Text('${o.prc.toStringAsFixed(0)} ${o.cur == 0 ? '\$' : 'ل.س'}',
                style: const TextStyle(color: AppTheme.primaryGold, fontSize: AppTheme.fontSizeBody)),
            AppTheme.gapHeightXS,
            Row(
              children: [
                _statusBadge(o.sts),
                AppTheme.gapWidthSmall,
                Icon(Icons.visibility,
                    size: 13, color: AppTheme.textGrey.withOpacity(0.7)),
                AppTheme.gapWidthXXS,
                Text('${o.vws}',
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
                AppTheme.gapWidthSmall,
                Icon(Icons.favorite,
                    size: 13, color: AppTheme.textGrey.withOpacity(0.7)),
                AppTheme.gapWidthXXS,
                Text('${o.fvs}',
                    style: const TextStyle(
                        color: AppTheme.textGrey, fontSize: AppTheme.fontSizeCaption)),
              ],
            ),
          ],
        ),
        onTap: () => context.push('/offer/${o.id}'),
        // 🤝 أزرار تعديل/حذف للوسيط — فقط للعروض القابلة للتعديل
        trailing: (o.sts == 0 || o.sts == 1 || o.sts == 3)
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    color: AppTheme.textGrey, size: 20),
                color: AppTheme.surfaceBlack,
                onSelected: (val) async {
                  if (val == 'edit') {
                    final changed =
                        await context.push('/user/edit-offer/${o.id}');
                    if (changed == true && mounted) _load();
                  } else if (val == 'delete') {
                    _confirmDelete(o);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit, color: AppTheme.primaryGold, size: 18),
                      AppTheme.gapWidthSmall,
                      Text('تعديل',
                          style: TextStyle(color: AppTheme.textWhite)),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline, color: AppTheme.errorRed, size: 18),
                      AppTheme.gapWidthSmall,
                      Text('حذف', style: TextStyle(color: AppTheme.errorRed)),
                    ]),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  /// 🗑️ تأكيد حذف عرض — يستدعي user-offers: delete_offer
  Future<void> _confirmDelete(OfferModel o) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceBlack,
        title: const Text('حذف العرض',
            style: TextStyle(color: AppTheme.textWhite)),
        content: Text('هل أنت متأكد من حذف «${o.ttl}»؟\nلا يمكن التراجع.',
            style: const TextStyle(color: AppTheme.textGrey)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textGrey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child:
                const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final uid = context.read<AuthProvider>().userModel?.uid ?? '';
    try {
      final res = await SupabaseService().invokeFunction('user-offers',
          body: {
            'action': 'delete_offer',
            'user_uid': uid,
            'offer_id': o.id,
          });
      if (!mounted) return;
      final data = res.data;
      if (data is Map && data['success'] == true) {
        _snack('تم حذف العرض');
        _load();
      } else {
        _snack('فشل الحذف');
      }
    } catch (e) {
      if (mounted) _snack('فشل الحذف — تحقق من الاتصال');
    }
  }

  void _snack(String m) =>
      AppTheme.showSnackBar(context, SnackBar(content: Text(m)));

  Widget _imgPlaceholder() => const SizedBox(
        width: 60,
        height: 60,
        child: OfficeLogoPlaceholder(logoSize: 24),
      );

  Widget _statusBadge(int sts) {
    late String label;
    late Color color;
    switch (sts) {
      case 0:
        label = 'مسودة';
        color = AppTheme.textGrey;
        break;
      case 1:
        label = 'قيد المراجعة';
        color = AppTheme.warningOrange;
        break;
      case 2:
        label = 'منشور';
        color = AppTheme.successGreen;
        break;
      case 3:
        label = 'مرفوض';
        color = AppTheme.errorRed;
        break;
      case 4:
        label = 'منتهٍ';
        color = AppTheme.textGrey;
        break;
      case 5:
        label = 'محجوز';
        color = Colors.blueAccent;
        break;
      case 6:
        label = 'مكتمل';
        color = AppTheme.primaryGold;
        break;
      default:
        label = '—';
        color = AppTheme.textGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: AppTheme.fontSizeXS)),
    );
  }
}
