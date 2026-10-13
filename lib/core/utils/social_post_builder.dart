import '../../models/config_model.dart';
import '../../models/offer_model.dart';

/// 📋 مولّد نصوص منشورات التواصل الاجتماعي — قالبان مصممان لكل منصة:
///
/// • [facebook]: روابط قابلة للنقر + نص مريح — للنشر اليدوي على صفحة المكتب.
/// • [instagram]: «أنبوبة الإعلان» (السطور 1-3) مضبوطة رياضياً لتقع قبل قصّ
///   إنستغرام (~126 حرف)، بلا روابط (لا تُنقر هناك — «الرابط بالباو»)
///   وهاشتاغات اكتشاف أكثر (تعمل حتى خلف «المزيد»).
///
/// 2026-08-31 (قرار المالك): الاسم الرسمي «المكتب العقاري الالكتروني»
/// (لا «المكتب العقاري الالكتروني - جرمانا»)، وجملة التطبيق: «لمتابعة كل العروض وحجز
/// المواعيد والاستفادة من خدماتنا»، والهاشتاغ الأول #المكتب_العقاري_الالكتروني.
///
/// يُولَّد وقت النسخ من بيانات العرض نفسها — لا يعتمد على `soc_txt`
/// المخزَّن (القالب القديم كان يترك أسطراً فارغة عشوائية عند غياب الحقول).
class SocialPostBuilder {
  SocialPostBuilder._();

  static const String _brand = 'المكتب العقاري الالكتروني';
  static const String _brandHashtag = '#المكتب_العقاري_الالكتروني';

  /// 📘 نسخة فيسبوك — الروابط تعمل والنص مريح.
  static String facebook(OfferModel o, ConfigModel? config) {
    final wa1 = (config?.contactWhatsApp ?? '').trim();
    final wa2 = (config?.whatsapp2 ?? '').trim();
    final wa = wa1.isEmpty ? wa2 : (wa2.isEmpty ? wa1 : '$wa1 أو $wa2');
    final fb = (config?.facebookPage ?? '').trim();
    final tg = ((config?.socialPages ?? const {})['telegram'] ?? '').toString().trim();
    final link = (config?.appDownloadLink ?? '').trim();
    final sections = <List<String>>[
      [
        '${_emoji(o.typ)} ${o.ttl.trim()} — ${_trans(o.trx)}',
        '💰 السعر: ${_price(o.prc, o.cur)}',
        if (_specs(o).isNotEmpty) '${o.typ == 0 ? '📐' : '🔧'} ${_specs(o).join(' • ')}',
      ],
      if (o.descript.trim().isNotEmpty) [o.descript.trim()],
      [
        wa.isEmpty
            ? '📞 للمعاينة والتواصل حصراً عبر $_brand'
            : '📞 للمعاينة والتواصل حصراً عبر $_brand (واتساب): $wa',
        if (fb.isNotEmpty) '📘 تابعنا على فيسبوك: $fb',
        if (tg.isNotEmpty) '📢 قناتنا على تلغرام: $tg',
        if (link.isNotEmpty) ...[
          '📲 حمّل تطبيق $_brand:',
          link,
        ],
      ],
      [_hashtags(o, long: false)],
    ];
    return _assemble(sections);
  }

  /// 📸 نسخة إنستغرام — مختصرة ومضبوطة على قاعدة الـ126 حرف.
  static String instagram(OfferModel o, ConfigModel? config) {
    final wa1 = (config?.contactWhatsApp ?? '').trim();
    final wa2 = (config?.whatsapp2 ?? '').trim();
    final wa = wa1.isEmpty ? wa2 : (wa2.isEmpty ? wa1 : '$wa1 أو $wa2');
    final priceLine = '💰 ${_price(o.prc, o.cur)}';
    final specs = _specs(o);
    final specsLine = specs.isEmpty ? '' : '${o.typ == 0 ? '📐' : '🔧'} ${specs.join(' • ')}';

    // 🔢 حماية أول 126 حرف (قصّ إنستغرام): ميزانية العنوان = 126 ناقص
    // سطري السعر والمواصفات. إن تجاوزها يُقصّ العنوان بـ«…» — فتبقى
    // أنبوبة الإعلان كاملة قبل «المزيد» مهما طال العنوان.
    var titleLine = '${_emoji(o.typ)} ${o.ttl.trim()} — ${_trans(o.trx)}';
    final budget = 126 - priceLine.length - specsLine.length - 3;
    if (budget > 20 && titleLine.length > budget) {
      titleLine = '${titleLine.substring(0, budget - 1)}…';
    }

    final sections = <List<String>>[
      [
        titleLine,
        priceLine,
        if (specsLine.isNotEmpty) specsLine,
      ],
      if (o.descript.trim().isNotEmpty) [o.descript.trim()],
      [
        wa.isEmpty
            ? '📩 للمعاينة والتواصل: راسلنا على خاص الصفحة'
            : '📩 للمعاينة والتواصل: راسلنا على الخاص أو واتساب المكتب $wa',
        '📲 حمّل تطبيق $_brand — كل روابطنا في البايو',
      ],
      [_hashtags(o, long: true)],
    ];
    return _assemble(sections);
  }

  // ─── تركيب الأقسام: كل قسم بأسطر متلاصقة، وبين الأقسام سطر فاصل واحد ───

  static String _assemble(List<List<String>> sections) {
    return sections
        .map((s) => s.join('\n'))
        .where((s) => s.trim().isNotEmpty)
        .join('\n\n')
        .trim();
  }

  // ─── العناصر المشتركة ───

  static String _emoji(int typ) => typ == 0 ? '🏠' : '🚗';

  static String _trans(int trx) => trx == 0 ? 'للبيع' : 'للإيجار';

  static String _price(double v, int cur) {
    final isWhole = v == v.roundToDouble();
    final raw = isWhole ? v.round().toString() : v.toStringAsFixed(2);
    final parts = raw.split('.');
    final whole = parts[0].replaceAll(RegExp(r'\B(?=(\d{3})+(?!\d))'), ',');
    final formatted = parts.length == 2 ? '$whole.${parts[1]}' : whole;
    return cur == 0 ? '\$$formatted' : '$formatted ل.س';
  }

  static List<String> _specs(OfferModel o) {
    final s = o.specs;
    String val(String k) => (s[k] ?? '').toString().trim();
    if (o.typ == 0) {
      return [
        if (val('area').isNotEmpty) 'مساحة ${val('area')} م²',
        if (val('finishing').isNotEmpty) 'إكساء ${val('finishing')}',
        if (val('floor').isNotEmpty) 'طابق ${val('floor')}',
        if (val('direction').isNotEmpty) 'اتجاه ${val('direction')}',
      ];
    }
    return [
      if (val('brand').isNotEmpty) 'ماركة ${val('brand')}',
      if (val('model').isNotEmpty) 'موديل ${val('model')}',
      if (val('year').isNotEmpty) 'سنة ${val('year')}',
      if (val('color').isNotEmpty) 'اللون ${val('color')}',
      if (val('fuel').isNotEmpty) 'وقود ${val('fuel')}',
      if (val('transmission').isNotEmpty) 'ناقل ${val('transmission')}',
    ];
  }

  static String _hashtags(OfferModel o, {required bool long}) {
    final city = o.loc['city']?.toString().trim() ?? '';
    final cityTag = city.isEmpty ? '#جرمانا' : '#${city.replaceAll(' ', '_')}';
    final base = '$_brandHashtag $cityTag ${o.typ == 0 ? '#عقارات' : '#سيارات'}';
    if (!long) return base;
    return '$base #عقارات_سوريا #عقارات_للبيع ${o.typ == 0 ? '#شقق_للبيع' : '#سيارات_للبيع'}';
  }
}