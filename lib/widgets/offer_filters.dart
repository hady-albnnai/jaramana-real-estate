import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// ⚠️ 2026-08-14: كان المساران `../../core/...` و`../../models/...` — وهما
// يخرجان من `lib/widgets/` إلى **جذر الريبو** حيث لا وجود لـ`core/` ولا
// `models/`. الملف مستورَد فعلياً من `user_home_screen.dart` و`home_screen.dart`
// ⇒ خطأ بناء مؤكَّد. الصحيح مستوىً واحد: `lib/widgets/` ← `lib/`.
import '../core/theme/app_theme.dart';
import '../models/offer_model.dart';
import '../core/constants/jaramana_locations.dart';
import '../core/constants/db_constants.dart';
import '../providers/config_provider.dart';

/// 🎛️ الفلاتر المتقدمة — ودجت مشترك بين شاشة الزائر وشاشة المستخدم (2026-07-27)
/// نفس معايير مطابقة الطلبات حرفياً، بلا أي تكرار كود بين الشاشتين.

/// ── حالة الفلاتر المتقدمة ──
/// كائن قابل للتعديل: نافذة الفلاتر تعدّل حقوله مباشرة عبر StatefulBuilder،
/// والشاشة الأم تعيد البناء عبر onChanged (setState).
class OfferFiltersData {
  String? city;
  /// نطاق السعر والترتيب لا يُطبّقان إلا بعد اختيار عملة واحدة صراحةً.
  int? currency;
  double minPrice = 0, maxPrice = 1000000;
  int? cat, docTp, floor, minRooms, year, maxKm;
  String? finishing, direction, brand, model, fuel, transmission;
  double? minArea, maxArea;
  bool imagesOnly = false;
  String sort = 'none'; // none | newest | price_low | price_high

  /// عدد المعايير الفعّالة (يظهر كباج على الزر الذهبي)
  int get activeCount {
    var n = 0;
    if (city != null) n++;
    if (currency != null) n++;
    if (currency != null && (minPrice > 0 || maxPrice < 1000000)) n++;
    for (final v in [cat, docTp, floor, minRooms, year, maxKm]) {
      if (v != null) n++;
    }
    for (final v in [finishing, direction, brand, model, fuel, transmission]) {
      if (v != null) n++;
    }
    if (minArea != null || maxArea != null) n++;
    if (imagesOnly) n++;
    if (sort != 'none') n++;
    return n;
  }

  void reset() {
    city = null;
    currency = null;
    minPrice = 0; maxPrice = 1000000;
    cat = docTp = floor = minRooms = year = maxKm = null;
    finishing = direction = brand = model = fuel = transmission = null;
    minArea = maxArea = null;
    imagesOnly = false;
    sort = 'none';
  }

  /// تطبيق كل المعايير + الترتيب على قائمة عروض — منطق client-side خالص
  List<OfferModel> apply(List<OfferModel> offers) {
    if (activeCount == 0) return offers;

    List<OfferModel> filtered = List.from(offers);

    // الموقع (city أو d)
    if (city != null) {
      filtered = filtered.where((o) {
        final c = (o.loc['city'] ?? o.loc['d'] ?? '').toString().toLowerCase();
        return c.contains(city!.toLowerCase());
      }).toList();
    }

    // العملة أولاً: لا توجد مقارنة أو فلترة سعر مختلطة بين USD وSYP.
    if (currency != null) {
      filtered = filtered.where((o) => o.cur == currency).toList();
      filtered = filtered
          .where((o) => o.prc >= minPrice && o.prc <= maxPrice)
          .toList();
    }

    // عقارات
    if (cat != null) {
      filtered = filtered.where((o) => o.cat == cat).toList();
    }
    if (docTp != null) {
      filtered = filtered.where((o) => o.docTp == docTp).toList();
    }
    if (finishing != null) {
      filtered = filtered.where((o) =>
          (o.specs['finishing']?.toString() ?? '') == finishing).toList();
    }
    if (direction != null) {
      filtered = filtered.where((o) =>
          (o.specs['direction']?.toString() ?? '') == direction).toList();
    }
    if (minArea != null) {
      filtered = filtered.where((o) {
        final area = double.tryParse(o.specs['area']?.toString() ?? '');
        return area != null && area >= minArea!;
      }).toList();
    }
    if (maxArea != null) {
      filtered = filtered.where((o) {
        final area = double.tryParse(o.specs['area']?.toString() ?? '');
        return area != null && area <= maxArea!;
      }).toList();
    }
    if (floor != null) {
      filtered = filtered.where((o) =>
          int.tryParse(o.specs['floor']?.toString() ?? '') == floor).toList();
    }
    if (minRooms != null) {
      filtered = filtered.where((o) {
        final rooms = (o.specs['rooms'] as num?)?.toInt() ?? 0;
        return rooms >= minRooms!;
      }).toList();
    }

    // سيارات
    if (brand != null) {
      filtered = filtered.where((o) =>
          (o.specs['brand']?.toString() ?? '').toLowerCase().contains(brand!.toLowerCase())).toList();
    }
    if (model != null) {
      filtered = filtered.where((o) =>
          (o.specs['model']?.toString() ?? '').toLowerCase().contains(model!.toLowerCase())).toList();
    }
    if (year != null) {
      filtered = filtered.where((o) =>
          int.tryParse(o.specs['year']?.toString() ?? '') == year).toList();
    }
    if (fuel != null) {
      filtered = filtered.where((o) =>
          (o.specs['fuel']?.toString() ?? '') == fuel).toList();
    }
    if (transmission != null) {
      filtered = filtered.where((o) =>
          (o.specs['transmission']?.toString() ?? '') == transmission).toList();
    }
    if (maxKm != null) {
      filtered = filtered.where((o) {
        final km = (o.specs['km'] as num?)?.toInt() ?? 999999;
        return km <= maxKm!;
      }).toList();
    }

    // الصور فقط
    if (imagesOnly) {
      filtered = filtered.where((o) => o.imgs.isNotEmpty).toList();
    }

    // الترتيب
    if (sort == 'price_low' && currency != null) {
      filtered.sort((a, b) => a.prc.compareTo(b.prc));
    } else if (sort == 'price_high' && currency != null) {
      filtered.sort((a, b) => b.prc.compareTo(a.prc));
    } else if (sort == 'newest') {
      filtered.sort((a, b) => b.tsCrt.compareTo(a.tsCrt));
    }

    return filtered;
  }
}

/// ── الزر الذهبي «فلاتر» مع باج العدد — نفس الشكل بالشاشتين ──
class OfferFiltersButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const OfferFiltersButton({super.key, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primaryGold,
      borderRadius: AppTheme.radiusMedium,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.radiusMedium,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.tune, color: AppTheme.deepBlack, size: 20),
              const SizedBox(width: 6),
              const Text('فلاتر',
                  style: TextStyle(
                      color: AppTheme.deepBlack,
                      fontWeight: FontWeight.bold,
                      fontSize: AppTheme.fontSizeBody)),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: AppTheme.paddingAllSmall,
                  constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceBlack,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primaryGold, width: 1.5),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppTheme.deepBlack,
                        fontSize: AppTheme.fontSizeCaption,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ── فتح نافذة الفلاتر الكاملة ──
/// [showProp]: عرض قسم العقارات (false إذا كان التشيب الحالي «سيارة») — والعكس لـ showCar.
/// مصادر التصنيفات تُمرَّر محلولة من ConfigProvider عند الفتح.
/// [onChanged] تُستدعى عند الإغلاق/التطبيق ليعيد الأب بناء العدّاد والقائمة.
Future<void> showOfferFiltersSheet(
  BuildContext context, {
  required OfferFiltersData f,
  required bool showProp,
  required bool showCar,
  required Map<String, dynamic> catPropSrc,
  required Map<String, dynamic> docTpSrc,
  required Map<String, dynamic> carDocTpSrc,
  required VoidCallback onChanged,
}) async {
  await showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.surfaceBlack,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, sheetSet) => Padding(
        padding: EdgeInsets.only(
          left: 16, right: 16, top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: _OfferFiltersBody(
          f: f,
          showProp: showProp,
          showCar: showCar,
          catPropSrc: catPropSrc,
          docTpSrc: docTpSrc,
          carDocTpSrc: carDocTpSrc,
          sheetSet: sheetSet,
          onApply: () {
            onChanged();
            Navigator.of(sheetCtx).pop();
          },
        ),
      ),
    ),
  );
  onChanged(); // تحديث العدّاد والنتائج بعد الإغلاق بأي طريقة
}

class _OfferFiltersBody extends StatelessWidget {
  final OfferFiltersData f;
  final bool showProp, showCar;
  final Map<String, dynamic> catPropSrc, docTpSrc, carDocTpSrc;
  final StateSetter sheetSet;
  final VoidCallback onApply;

  const _OfferFiltersBody({
    required this.f,
    required this.showProp,
    required this.showCar,
    required this.catPropSrc,
    required this.docTpSrc,
    required this.carDocTpSrc,
    required this.sheetSet,
    required this.onApply,
  });

  List<DropdownMenuItem<int>> _catItems(Map<String, dynamic> src) => src.entries
      .where((e) => int.tryParse(e.key) != null)
      .map((e) => DropdownMenuItem<int>(
            value: int.parse(e.key),
            child: Text(
              e.value is Map ? (e.value['nm'] ?? e.value.toString()) : e.value.toString(),
              overflow: TextOverflow.ellipsis,
            ),
          ))
      .toList();

  @override
  Widget build(BuildContext context) {
    final allowedCurrencies =
        context.watch<ConfigProvider>().config?.allowedOfferCurrencies ??
            Currency.supported;
    final selectedCurrency = allowedCurrencies.contains(f.currency)
        ? f.currency
        : null;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.tune, color: AppTheme.primaryGold),
            AppTheme.gapWidthSmall,
            const Expanded(
              child: Text('الفلاتر الكاملة',
                  style: TextStyle(
                      color: AppTheme.primaryGold,
                      fontSize: AppTheme.fontSizeTitle,
                      fontWeight: FontWeight.bold)),
            ),
            TextButton(
              onPressed: () => sheetSet(f.reset),
              child: const Text('تصفير', style: TextStyle(color: AppTheme.errorRed)),
            ),
          ]),
          AppTheme.gapHeightMedium,

          // الموقع
          DropdownButtonFormField<String>(
            value: f.city,
            decoration: _fDeco('الموقع'),
            items: JaramanaLocations.all
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => sheetSet(() => f.city = v),
          ),
          AppTheme.gapHeightMedium,

          // السعر: تُختار العملة قبل النطاق حتى لا تختلط USD وSYP.
          DropdownButtonFormField<int>(
            value: selectedCurrency,
            decoration: _fDeco('عملة السعر'),
            items: [
              const DropdownMenuItem<int>(value: null, child: Text('اختر العملة')),
              ...allowedCurrencies.map((currency) => DropdownMenuItem<int>(
                    value: currency,
                    child: Text(Currency.labelOf(currency)),
                  )),
            ],
            onChanged: (value) => sheetSet(() {
              f.currency = value;
              if (value == null &&
                  (f.sort == 'price_low' || f.sort == 'price_high')) {
                f.sort = 'none';
              }
            }),
          ),
          AppTheme.gapHeightSmall,
          RangeSlider(
            values: RangeValues(f.minPrice, f.maxPrice),
            min: 0, max: 1000000, divisions: 20,
            activeColor: AppTheme.primaryGold,
            labels: RangeLabels(
              '${f.minPrice.toInt()}', '${f.maxPrice.toInt()}'),
            onChanged: f.currency == null
                ? null
                : (v) => sheetSet(() {
                      f.minPrice = v.start;
                      f.maxPrice = v.end;
                    }),
          ),
          Text(
            f.currency == null
                ? 'اختر العملة لتفعيل نطاق السعر'
                : 'السعر: ${f.minPrice.toInt()} — ${f.maxPrice.toInt()} ${Currency.labelOf(f.currency!)}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeSmall),
          ),
          AppTheme.gapHeightSmall,

          if (showProp) ...[
            const _FSectionTitle('🏠 فلاتر العقارات'),
            DropdownButtonFormField<int>(
              value: f.cat,
              decoration: _fDeco('التصنيف'),
              items: [const DropdownMenuItem(value: null, child: Text('الكل')),
                  ..._catItems(catPropSrc)],
              onChanged: (v) => sheetSet(() => f.cat = v),
            ),
            AppTheme.gapHeightSmall,
            DropdownButtonFormField<int>(
              value: f.docTp,
              decoration: _fDeco('نوع السند'),
              items: [const DropdownMenuItem(value: null, child: Text('الكل')),
                  ..._catItems(docTpSrc)],
              onChanged: (v) => sheetSet(() => f.docTp = v),
            ),
            AppTheme.gapHeightSmall,
            DropdownButtonFormField<String>(
              value: f.finishing,
              decoration: _fDeco('التشطيب'),
              items: ['ملكي', 'سوبر ديلوكس', 'ديلوكس', 'عادي', 'هيكل']
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => sheetSet(() => f.finishing = v),
            ),
            AppTheme.gapHeightSmall,
            DropdownButtonFormField<String>(
              value: f.direction,
              decoration: _fDeco('الاتجاه'),
              items: ['شمالي', 'جنوبي', 'شرقي', 'غربي', 'شمالي شرقي', 'شمالي غربي',
                      'جنوبي شرقي', 'جنوبي غربي', 'مفتوح']
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) => sheetSet(() => f.direction = v),
            ),
            AppTheme.gapHeightSmall,
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: f.minArea?.toInt().toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _fDeco('مساحة من'),
                onChanged: (v) => f.minArea = double.tryParse(v),
              )),
              AppTheme.gapWidthSmall,
              Expanded(child: TextFormField(
                initialValue: f.maxArea?.toInt().toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _fDeco('مساحة إلى'),
                onChanged: (v) => f.maxArea = double.tryParse(v),
              )),
            ]),
            AppTheme.gapHeightSmall,
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: f.floor?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _fDeco('الطابق'),
                onChanged: (v) => f.floor = int.tryParse(v),
              )),
              AppTheme.gapWidthSmall,
              Expanded(child: DropdownButtonFormField<int>(
                value: f.minRooms,
                decoration: _fDeco('غرف (أدنى)'),
                items: [1, 2, 3, 4]
                    .map((r) => DropdownMenuItem(value: r, child: Text('$r+')))
                    .toList(),
                onChanged: (v) => sheetSet(() => f.minRooms = v),
              )),
            ]),
            AppTheme.gapHeightSmall,
          ],

          if (showCar) ...[
            const _FSectionTitle('🚗 فلاتر السيارات'),
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: f.brand ?? '',
                decoration: _fDeco('الماركة'),
                onChanged: (v) => f.brand = v.trim().isEmpty ? null : v.trim(),
              )),
              AppTheme.gapWidthSmall,
              Expanded(child: TextFormField(
                initialValue: f.model ?? '',
                decoration: _fDeco('الموديل'),
                onChanged: (v) => f.model = v.trim().isEmpty ? null : v.trim(),
              )),
            ]),
            AppTheme.gapHeightSmall,
            Row(children: [
              Expanded(child: TextFormField(
                initialValue: f.year?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: _fDeco('سنة الصنع'),
                onChanged: (v) => f.year = int.tryParse(v),
              )),
              AppTheme.gapWidthSmall,
              Expanded(child: DropdownButtonFormField<int>(
                value: f.maxKm,
                decoration: _fDeco('كم (أقصى)'),
                items: [50000, 100000, 150000]
                    .map((k) => DropdownMenuItem(
                        value: k, child: Text('< ${k ~/ 1000} ألف')))
                    .toList(),
                onChanged: (v) => sheetSet(() => f.maxKm = v),
              )),
            ]),
            AppTheme.gapHeightSmall,
            Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                value: f.fuel,
                decoration: _fDeco('الوقود'),
                items: ['بنزين', 'ديزل', 'هجين', 'كهرباء']
                    .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                    .toList(),
                onChanged: (v) => sheetSet(() => f.fuel = v),
              )),
              AppTheme.gapWidthSmall,
              Expanded(child: DropdownButtonFormField<String>(
                value: f.transmission,
                decoration: _fDeco('القير'),
                items: ['عادي', 'أوتوماتيك', 'نصف أوتوماتيك']
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => sheetSet(() => f.transmission = v),
              )),
            ]),
            AppTheme.gapHeightSmall,
          ],

          // خيارات عامة
          SwitchListTile(
            value: f.imagesOnly,
            title: const Text('عروض لها صور فقط',
                style: TextStyle(color: AppTheme.textWhite, fontSize: AppTheme.fontSizeBody)),
            activeColor: AppTheme.primaryGold,
            contentPadding: EdgeInsets.zero,
            onChanged: (v) => sheetSet(() => f.imagesOnly = v),
          ),
          DropdownButtonFormField<String>(
            value: f.sort,
            decoration: _fDeco('الترتيب'),
            items: [
              const DropdownMenuItem(value: 'none', child: Text('الافتراضي (الأولوية)')),
              const DropdownMenuItem(value: 'newest', child: Text('الأحدث')),
              if (f.currency != null) ...const [
                DropdownMenuItem(value: 'price_low', child: Text('السعر: الأقل أولاً')),
                DropdownMenuItem(value: 'price_high', child: Text('السعر: الأعلى أولاً')),
              ],
            ],
            onChanged: (v) => sheetSet(() => f.sort = v ?? 'none'),
          ),
          AppTheme.gapHeightLarge,

          ElevatedButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.check, color: AppTheme.deepBlack),
            label: Text(
              'تطبيق${f.activeCount > 0 ? ' (${f.activeCount})' : ''}',
              style: const TextStyle(
                  color: AppTheme.deepBlack, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryGold,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.radiusMedium),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _fDeco(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppTheme.textGrey, fontSize: AppTheme.fontSizeBody),
      filled: true,
      fillColor: AppTheme.scaffoldBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: AppTheme.radiusMedium,
        borderSide: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusMedium,
        borderSide: BorderSide(color: AppTheme.primaryGold.withOpacity(0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppTheme.radiusMedium,
        borderSide: const BorderSide(color: AppTheme.primaryGold),
      ),
    );

/// عنوان مقطع داخل نافذة الفلاتر
class _FSectionTitle extends StatelessWidget {
  final String text;
  const _FSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.primaryGold,
          fontWeight: FontWeight.bold,
          fontSize: AppTheme.fontSizeMedium,
        ),
      ),
    );
  }
}
