import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/offer_provider.dart';
import '../../providers/config_provider.dart';
import '../../core/constants/db_constants.dart';
import '../../models/offer_model.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/offer_card.dart';
import '../../widgets/shimmer_loading.dart';

/// 🔎 شاشة البحث — بحث نصّي + فلترة بالنوع والمعاملة
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  int? _type; // 0=عقار, 1=سيارة
  int? _trx;  // 0=بيع, 1=إيجار
  int? _currency; // 0=دولار, 1=ل.س
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();

  List<OfferModel> _results = [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _doSearch() async {
    final hasPriceRange = _minPriceCtrl.text.trim().isNotEmpty ||
        _maxPriceCtrl.text.trim().isNotEmpty;
    if (hasPriceRange && _currency == null) {
      AppTheme.showSnackBar(
        context,
        const SnackBar(
          content: Text('اختر العملة أولاً قبل تحديد نطاق السعر'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _searched = true;
    });
    final results = await context.read<OfferProvider>().searchOffers(
          query: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
          type: _type,
          transaction: _trx,
          currency: _currency,
          minPrice: double.tryParse(_minPriceCtrl.text.trim()),
          maxPrice: double.tryParse(_maxPriceCtrl.text.trim()),
        );
    if (mounted) {
      setState(() {
        _results = results;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowedCurrencies =
        context.watch<ConfigProvider>().config?.allowedOfferCurrencies ??
            Currency.supported;
    final selectedCurrency = allowedCurrencies.contains(_currency)
        ? _currency
        : null;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.scaffoldBackground,
        // رجوع صريح: الوصول للبحث من شريط التنقل السفلي (context.go) يمسح الستاك
        // فلا يظهر سهم تلقائي — نرجع للرئيسية عند غياب ما يُغلَق
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textWhite),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
        title: const Text('بحث'),
      ),
      body: Column(
        children: [
          // ── شريط البحث ──
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 6),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: AppTheme.textWhite),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
              decoration: InputDecoration(
                hintText: 'ابحث عن عقار أو سيارة...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.primaryGold),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_circle_left,
                      color: AppTheme.primaryGold),
                  onPressed: _doSearch,
                ),
                filled: true,
                fillColor: AppTheme.surfaceBlack,
                border: OutlineInputBorder(
                  borderRadius: AppTheme.radiusMedium,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // ── الفلاتر ──
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
              children: [
                _chip('🏠 عقار', _type == 0, () {
                  setState(() => _type = _type == 0 ? null : 0);
                }),
                AppTheme.gapWidthSmall,
                _chip('🚗 سيارة', _type == 1, () {
                  setState(() => _type = _type == 1 ? null : 1);
                }),
                AppTheme.gapWidthSmall,
                _chip('بيع', _trx == 0, () {
                  setState(() => _trx = _trx == 0 ? null : 0);
                }),
                AppTheme.gapWidthSmall,
                _chip('إيجار', _trx == 1, () {
                  setState(() => _trx = _trx == 1 ? null : 1);
                }),
              ],
            ),
          ),

          // ── فلتر السعر ──
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 6),
            child: Row(children: [
              // العملة
              DropdownButton<int?>(
                value: selectedCurrency,
                dropdownColor: AppTheme.surfaceBlack,
                style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
                hint: const Text('العملة', style: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody)),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('الكل')),
                  ...allowedCurrencies.map((currency) => DropdownMenuItem<int?>(
                        value: currency,
                        child: Text(Currency.labelOf(currency)),
                      )),
                ],
                onChanged: (v) => setState(() => _currency = v),
              ),
              AppTheme.gapWidthSmall,
              Expanded(
                child: TextField(
                  controller: _minPriceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
                  decoration: const InputDecoration(
                    hintText: 'سعر من',
                    hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                    filled: true, fillColor: AppTheme.surfaceBlack,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(8))),
                    isDense: true,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Text('—', style: TextStyle(color: AppTheme.textGrey)),
              ),
              Expanded(
                child: TextField(
                  controller: _maxPriceCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody),
                  decoration: const InputDecoration(
                    hintText: 'سعر إلى',
                    hintStyle: TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
                    filled: true, fillColor: AppTheme.surfaceBlack,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(8))),
                    isDense: true,
                  ),
                ),
              ),
            ]),
          ),

          // ── زر البحث ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _doSearch,
                icon: const Icon(Icons.search),
                label: Text(_loading ? 'جارٍ البحث...' : 'بحث'),
              ),
            ),
          ),

          // ── النتائج ──
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) return ShimmerLoading.offerList();

    if (!_searched) {
      return _hint(
          Icons.search, 'ابحث عن عقارات وسيارات\nاستخدم الكلمات أو الفلاتر بالأعلى');
    }

    if (_results.isEmpty) {
      return _hint(Icons.search_off, 'لا توجد نتائج مطابقة\nجرّب كلمات أو فلاتر مختلفة');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      itemCount: _results.length,
      itemBuilder: (_, i) => OfferCard(offer: _results[i]),
    );
  }

  Widget _hint(IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: AppTheme.textGrey.withOpacity(0.3)),
          AppTheme.gapHeightLarge,
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textGrey, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
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
      onSelected: (_) => onTap(),
    );
  }
}
