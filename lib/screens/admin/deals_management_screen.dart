import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/admin_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/deal_model.dart';
import '../../models/offer_model.dart';
import '../../core/network/supabase_service.dart';
import '../../core/theme/app_theme.dart';
import 'complete_deal_screen.dart';

/// 🤝 إدارة الصفقات — عرض + إتمام + تسجيل العمولة
class DealsManagementScreen extends StatefulWidget {
  const DealsManagementScreen({super.key});

  @override
  State<DealsManagementScreen> createState() => _DealsManagementScreenState();
}

class _DealsManagementScreenState extends State<DealsManagementScreen> {
  List<DealModel> _all = [];
  bool _loading = true;
  int _filter = -1; // -1=الكل, 0=نشطة, 1=مكتملة

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final list = await context.read<AdminProvider>().getAllDeals(adminUid);
    if (mounted) {
      setState(() {
        _all = list;
        _loading = false;
      });
    }
  }

  List<DealModel> get _filtered =>
      _filter == -1 ? _all : _all.where((d) => d.sts == _filter).toList();

  double get _totalCommission =>
      _all.where((d) => d.sts == 1).fold<double>(0, (s, d) => s + d.comVal);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        title: const Text('إدارة الصفقات'),
        backgroundColor: AppTheme.scaffoldBackground,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.primaryGold),
            onPressed: _load,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDealDialog,
        backgroundColor: AppTheme.primaryGold,
        icon: const Icon(Icons.add, color: AppTheme.deepBlack),
        label: const Text('صفقة جديدة',
            style: TextStyle(
                color: AppTheme.deepBlack, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // ملخّص العمولات
          Container(
            margin: AppTheme.paddingAllLarge,
            padding: AppTheme.paddingAllLarge,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primaryGold.withOpacity(0.25),
                  AppTheme.surfaceBlack
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: AppTheme.radiusLarge,
              border: Border.all(color: AppTheme.primaryGold.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_balance,
                    color: AppTheme.primaryGold, size: 34),
                AppTheme.gapWidthMedium,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('إجمالي عمولات المكتب',
                        style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall)),
                    Text('${_totalCommission.toStringAsFixed(0)} \$',
                        style: const TextStyle(
                            color: AppTheme.primaryGold,
                            fontSize: AppTheme.fontSizeLarge,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _chip('الكل', -1),
                _chip('نشطة', 0),
                _chip('مكتملة', 1),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGold))
                : _filtered.isEmpty
                    ? const Center(
                        child: Text('لا توجد صفقات',
                            style: TextStyle(color: AppTheme.textGrey)))
                    : RefreshIndicator(
                        color: AppTheme.primaryGold,
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: AppTheme.paddingAllMedium,
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _dealTile(_filtered[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int value) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
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
      ),
    );
  }

  Widget _dealTile(DealModel d) {
    final done = d.sts == 1;
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
              Text('صفقة #${_short(d.id)}',
                  style: const TextStyle(
                      color: AppTheme.textWhite, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: (done ? AppTheme.successGreen : AppTheme.warningOrange).withOpacity(0.15),
                  borderRadius: AppTheme.radiusSmall,
                  border: Border.all(
                      color: (done ? AppTheme.successGreen : AppTheme.warningOrange).withOpacity(0.5)),
                ),
                child: Text(done ? 'مكتملة' : 'نشطة',
                    style: TextStyle(
                        color: done ? AppTheme.successGreen : AppTheme.warningOrange, fontSize: AppTheme.fontSizeCaption)),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 18),
          _row('السعر النهائي',
              '${d.finPrc.toStringAsFixed(0)} ${d.cur == 0 ? '\$' : 'ل.س'}'),
          _row('نسبة العمولة', '${d.comPct.toStringAsFixed(1)}%'),
          _row('قيمة العمولة', '${d.comVal.toStringAsFixed(0)} \$', highlight: true),
          if (d.comNote != null && d.comNote!.isNotEmpty)
            _row('ملاحظة', d.comNote!),
          if (!done)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ElevatedButton.icon(
                  onPressed: () => _openCompleteDealScreen(d),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('إتمام الصفقة'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// ✅ فتح صفحة إتمام المعاملة الكاملة (Bug #21)
  Future<void> _openCompleteDealScreen(DealModel d) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CompleteDealScreen(deal: d),
      ),
    );
    
    if (result == true && mounted) {
      _snack('✅ تم إتمام الصفقة بنجاح');
      _load();
    }
  }

  /// 🤝 إنشاء صفقة جديدة — يختار العرض + السعر النهائي + العمولة
  Future<void> _showCreateDealDialog() async {
    // جلب العروض المنشورة
    List<OfferModel> offers = [];
    try {
      final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
      final res = await SupabaseService().invokeFunction('admin-offers',
          body: {'action': 'list', 'admin_uid': adminUid});
      if (res.data is Map && res.data['success'] == true) {
        offers = (res.data['offers'] as List)
            .map((r) => OfferModel.fromSupabase(
                Map<String, dynamic>.from(r), r['id'] as String))
            .where((o) => o.sts == 2 && o.iPub == 1) // منشورة فقط
            .toList();
      }
    } catch (_) {}

    if (!mounted) return;
    if (offers.isEmpty) {
      _snack('لا توجد عروض منشورة لإنشاء صفقة عليها');
      return;
    }

    OfferModel? selectedOffer;
    final priceCtrl = TextEditingController();
    final comPctCtrl = TextEditingController(text: '3');
    final comValCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    void recalcCom() {
      final price = double.tryParse(priceCtrl.text.trim()) ?? 0;
      final pct = double.tryParse(comPctCtrl.text.trim()) ?? 0;
      comValCtrl.text = (price * pct / 100).toStringAsFixed(0);
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: AppTheme.surfaceBlack,
          title: const Text('إنشاء صفقة جديدة',
              style: TextStyle(color: AppTheme.primaryGold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<OfferModel>(
                  dropdownColor: AppTheme.surfaceBlack,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration:
                      const InputDecoration(labelText: 'العرض *'),
                  items: offers
                      .map((o) => DropdownMenuItem(
                          value: o,
                          child: Text(o.ttl,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: AppTheme.fontSizeBody))))
                      .toList(),
                  onChanged: (v) {
                    setDlg(() {
                      selectedOffer = v;
                      if (v != null) {
                        priceCtrl.text =
                            v.prc.toStringAsFixed(0);
                        recalcCom();
                      }
                    });
                  },
                ),
                AppTheme.gapHeightMedium,
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                      labelText: 'السعر النهائي *'),
                  onChanged: (_) => recalcCom(),
                ),
                AppTheme.gapHeightMedium,
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: comPctCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(
                              decimal: true),
                      style:
                          const TextStyle(color: AppTheme.textWhite),
                      decoration: const InputDecoration(
                          labelText: 'نسبة العمولة %'),
                      onChanged: (_) => recalcCom(),
                    ),
                  ),
                  AppTheme.gapWidthMedium,
                  Expanded(
                    child: TextField(
                      controller: comValCtrl,
                      keyboardType: TextInputType.number,
                      style:
                          const TextStyle(color: AppTheme.textWhite),
                      decoration: const InputDecoration(
                          labelText: 'قيمة العمولة'),
                    ),
                  ),
                ]),
                AppTheme.gapHeightMedium,
                TextField(
                  controller: noteCtrl,
                  style: const TextStyle(color: AppTheme.textWhite),
                  decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء',
                    style: TextStyle(color: AppTheme.textGrey))),
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('إنشاء')),
          ],
        ),
      ),
    );

    if (ok != true || selectedOffer == null || !mounted) return;

    final adminUid = context.read<AuthProvider>().userModel?.uid ?? '';
    final deal = DealModel(
      id: '',
      offId: selectedOffer!.id,
      sellUid: selectedOffer!.usrId,
      buyUid: '', // يُحدد لاحقاً
      finPrc: double.tryParse(priceCtrl.text.trim()) ?? 0,
      cur: selectedOffer!.cur,
      comPct: double.tryParse(comPctCtrl.text.trim()) ?? 3,
      comVal: double.tryParse(comValCtrl.text.trim()) ?? 0,
      comNote: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      tsCrt: DateTime.now(),
    );

    if (await context.read<AdminProvider>().createDeal(adminUid, deal)) {
      _snack('✅ تم إنشاء الصفقة');
      _load();
    } else {
      _snack('فشل إنشاء الصفقة');
    }
  }

  Widget _row(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.left,
                style: TextStyle(
                    color: highlight ? AppTheme.primaryGold : AppTheme.textWhite,
                    fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
                    fontSize: AppTheme.fontSizeBody)),
          ),
        ],
      ),
    );
  }

  String _short(String s) => s.length >= 8 ? s.substring(0, 8) : s;

  void _snack(String msg) {
    if (!mounted) return;
    AppTheme.showSnackBar(context, SnackBar(content: Text(msg)));
  }
}
