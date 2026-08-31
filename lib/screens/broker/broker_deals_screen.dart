import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/broker_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/deal_model.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/bottom_nav_bar.dart';

/// 🤝 صفقات الوسيط — النشطة والمكتملة + ملخّص العمولات
class BrokerDealsScreen extends StatefulWidget {
  const BrokerDealsScreen({super.key});

  @override
  State<BrokerDealsScreen> createState() => _BrokerDealsScreenState();
}

class _BrokerDealsScreenState extends State<BrokerDealsScreen> {
  int _tab = 0; // 0=الكل, 1=نشطة, 2=مكتملة

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
      await context.read<BrokerProvider>().fetchBrokerDeals(id);
    }
  }

  List<DealModel> _apply(List<DealModel> deals) {
    switch (_tab) {
      case 1:
        return deals.where((d) => d.sts == 0).toList();
      case 2:
        return deals.where((d) => d.sts == 1).toList();
      default:
        return deals;
    }
  }

  @override
  Widget build(BuildContext context) {
    final broker = context.watch<BrokerProvider>();
    final deals = _apply(broker.deals);

    final totalCommission = broker.deals
        .where((d) => d.sts == 1)
        .fold<double>(0, (s, d) => s + d.comVal);

    return Scaffold(
      bottomNavigationBar: const CustomBottomNavBar(currentIndex: 3),
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('الصفقات'),
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
          // بطاقة ملخّص العمولات
          Container(
            margin: AppTheme.paddingAllLarge,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryGold.withOpacity(0.25),
                  AppTheme.surfaceBlack,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance_wallet,
                    color: AppTheme.primaryGold, size: 38),
                AppTheme.gapWidthLarge,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('إجمالي العمولات المحققة',
                        style:
                            TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
                    AppTheme.gapHeightXS,
                    Text('${totalCommission.toStringAsFixed(0)} \$',
                        style: const TextStyle(
                            color: AppTheme.primaryGold,
                            fontSize: 26,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),

          // تبويبات الحالة
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('الكل', 0),
                AppTheme.gapWidthSmall,
                _chip('نشطة', 1),
                AppTheme.gapWidthSmall,
                _chip('مكتملة', 2),
              ],
            ),
          ),
          Expanded(
            child: broker.isLoading && broker.deals.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : broker.error != null && broker.deals.isEmpty
                    ? _error()
                    : deals.isEmpty
                        ? _empty()
                        : RefreshIndicator(
                        color: AppTheme.primaryGold,
                        onRefresh: () async => _load(),
                        child: ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: deals.length,
                          itemBuilder: (_, i) => _dealTile(deals[i]),
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
            const Text('تعذر تحميل صفقات الوسيط',
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
            Icon(Icons.handshake,
                size: 72, color: AppTheme.textGrey.withOpacity(0.3)),
            AppTheme.gapHeightLarge,
            const Text('لا توجد صفقات',
                style: TextStyle(color: AppTheme.textGrey, fontSize: 15)),
          ],
        ),
      );

  Widget _chip(String label, int value) {
    final selected = _tab == value;
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
      onSelected: (_) => setState(() => _tab = value),
    );
  }

  Widget _dealTile(DealModel d) {
    final isDone = d.sts == 1;
    final isBroker = context.read<AuthProvider>().isBroker;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: AppTheme.paddingAllLarge,
      decoration: BoxDecoration(
        color: AppTheme.surfaceBlack,
        borderRadius: AppTheme.radiusLarge,
        border: Border.all(color: AppTheme.primaryGold.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('صفقة #${d.id.length >= 8 ? d.id.substring(0, 8) : d.id}',
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: (isDone ? AppTheme.successGreen : AppTheme.warningOrange)
                      .withOpacity(0.15),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(
                      color: (isDone ? AppTheme.successGreen : AppTheme.warningOrange)
                          .withOpacity(0.5)),
                ),
                child: Text(isDone ? 'مكتملة' : 'نشطة',
                    style: TextStyle(
                        color: isDone ? AppTheme.successGreen : AppTheme.warningOrange,
                        fontSize: AppTheme.fontSizeCaption)),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),
          _row('السعر النهائي',
              '${d.finPrc.toStringAsFixed(0)} ${d.cur == 0 ? '\$' : 'ل.س'}'),
          _row('نسبة العمولة', isBroker ? '0.0%' : '${d.comPct.toStringAsFixed(1)}%'),
          _row('قيمة العمولة', isBroker ? '0 \$' : '${d.comVal.toStringAsFixed(0)} \$',
              highlight: true),
          if (d.tsCmpl != null)
            _row('تاريخ الإتمام',
                d.tsCmpl!.toString().split(' ').first),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
          Text(value,
              style: TextStyle(
                  color: highlight ? AppTheme.primaryGold : AppTheme.textWhite,
                  fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                  fontSize: AppTheme.fontSizeBody)),
        ],
      ),
    );
  }
}
