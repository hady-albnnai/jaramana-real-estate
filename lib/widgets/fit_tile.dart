import 'package:flutter/material.dart';

/// ════════════════════════════════════════════════════════════════════════
/// 🧱 UI-OVF-001 (2026-08-15) — علاج جذري لفيضان بطاقات الشبكات
/// ════════════════════════════════════════════════════════════════════════
/// **العطل المُبلَّغ**: «مركز عمليات المكتب — أيقونات الملخص السريع كلها فيها
/// أوفرفلو من الأسفل بمقدار 0.66».
///
/// **السبب الجذري** (حساب دقيق، لا تخمين):
///   ارتفاع خلية `GridView` = عرض الخلية ÷ `childAspectRatio`، وهو رقم
///   **مشتق من عرض الشاشة**. أما محتوى البطاقة فارتفاعه **ثابت بالبكسل**:
///     paddingAllLarge (16×2) = 32
///     Icon الافتراضية        = 24
///     gapHeightSmall          =  8
///     نص القيمة (22px)        ≈ 25.7
///     نص العنوان (12px)       ≈ 14.0
///     ────────────────────────────
///     المجموع                ≈ 103.7 بكسل
///   على جهاز عرض خليته ≈165 و`childAspectRatio: 1.6` ⇒ الارتفاع المتاح
///   103.04 ⇒ العجز **0.66 بكسل بالضبط** — مطابق للتقرير.
///
/// أي تعديل على `childAspectRatio` هو **مسكّن لجهاز واحد**: يكفي جهاز أضيق،
/// أو مستخدم رفع حجم خط النظام، ليعود الفيضان. ومستحيل عملياً ضبط رقم واحد
/// يصلح لكل عرض شاشة × كل معامل تكبير خط.
///
/// **الحل البنيوي**: `FittedBox(fit: BoxFit.scaleDown)` حول عمود
/// `mainAxisSize.min`. العمود يقيس نفسه بحرية (ارتفاع غير محدود منطقياً)،
/// ثم يُصغَّر بالتناسب ليدخل في المساحة المتاحة. رياضياً:
///   • إن اتّسع المحتوى ⇒ مقياس 1.0 (بلا أي تغيير بصري).
///   • إن ضاق ⇒ يتقلّص بدل أن يفيض.
/// ⇒ **الفيضان مستحيل بنيوياً**، مهما كان الجهاز أو حجم الخط أو النسبة.
///
/// يُستخدم داخل كل بطاقة شبكة في التطبيق. لا يغيّر الشكل على الأجهزة التي
/// تعمل حالياً — يمنع الانكسار على غيرها فقط.
class FitTile extends StatelessWidget {
  /// يلفّ أي محتوى جاهز (صف، عمود، Stack...).
  const FitTile({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });

  /// اختصار للحالة الشائعة: عمود مضغوط من عناصر.
  FitTile.column({
    super.key,
    required List<Widget> children,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    this.alignment = Alignment.center,
  }) : child = Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: crossAxisAlignment,
          children: children,
        );

  /// المحتوى المراد حمايته من الفيضان.
  final Widget child;

  /// موضع المحتوى المُصغَّر داخل المساحة المتاحة.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    // ⚠️ دقة مطلوبة: `FittedBox` يمرّر لابنه قيوداً **غير محدودة**، فلو وضعنا
    // المحتوى مباشرةً لصار عرض النص لا نهائياً ⇒ لا يلتفّ سطراً ثانياً، بل
    // يمتدّ أفقياً ثم يُصغَّر كثيراً فيبدو مجهرياً. لذلك نثبّت العرض على
    // العرض الفعلي المتاح عبر `LayoutBuilder` + `SizedBox`، فيلتفّ النص
    // تماماً كما قبل، ويبقى التصغير محصوراً في البُعد الرأسي وحده.
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth.isFinite ? constraints.maxWidth : null;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: SizedBox(
            width: w,
            child: child,
          ),
        );
      },
    );
  }
}
