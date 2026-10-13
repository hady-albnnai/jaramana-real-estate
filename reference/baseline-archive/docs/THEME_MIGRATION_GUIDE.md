# دليل الترحيل لنظام الثيم الموحد
# Theme System Migration Guide

## نظرة عامة - Overview

تم إنشاء نظام ثيم موحد في `lib/core/theme/app_theme.dart` يحتوي على جميع الثوابت والألوان والمسافات المستخدمة في التطبيق.

A unified theme system has been created in `lib/core/theme/app_theme.dart` containing all constants, colors, and spacing used throughout the application.

---

## 🎯 الأهداف - Goals

1. **توحيد القيم** - استبدال 759 قيمة fontSize مشفرة بثوابت دلالية
2. **توحيد المسافات** - استبدال 276 EdgeInsets و 1,096 SizedBox مشفرة بثوابت
3. **توحيد الألوان** - استبدال 22 لون مشفر بثوابت دلالية
4. **إضافة الريسبونسيڤ** - دعم كامل للأجهزة المختلفة (موبايل، تابلت، ديسكتوب)
5. **تحسين إمكانية الوصول** - دعم قارئات الشاشة وتكبير النصوص

---

## 📊 الإحصائيات الحالية - Current Statistics

| النوع | العدد | الحالة |
|------|-------|--------|
| Font Sizes مشفرة | 759 | 🔴 يحتاج ترحيل |
| EdgeInsets مشفرة | 276 | 🔴 يحتاج ترحيل |
| SizedBox مشفرة | 1,096 | 🔴 يحتاج ترحيل |
| BorderRadius مشفرة | 370 | 🔴 يحتاج ترحيل |
| ألوان مشفرة | 22 | 🟡 بعضها موحد |
| نصوص مشفرة | 974 | 🔴 يحتاج i18n |

---

## 🎨 الألوان الدلالية - Semantic Colors

### قبل - Before
```dart
Container(
  color: Colors.green,  // ❌ لون مشفر بدون معنى
)
```

### بعد - After
```dart
Container(
  color: AppTheme.successGreen,  // ✅ لون دلالي واضح
)
```

### الألوان المتاحة - Available Colors

```dart
// الألوان الأساسية - Core Colors
AppTheme.primaryGold        // #D4AF37 - الذهبي الأساسي
AppTheme.deepBlack          // #121212 - الأسود العميق
AppTheme.scaffoldBackground // #FFFBF2 - خلفية الشاشة
AppTheme.lightGold          // #F9E4B7 - الذهبي الفاتح
AppTheme.surfaceBlack       // #FFFFFF - سطح البطاقات
AppTheme.errorRed           // #B3261E - الأحمر للخطأ
AppTheme.textWhite          // #17130A - النص الأساسي
AppTheme.textGrey           // #6F6656 - النص الثانوي

// الألوان الدلالية - Semantic Colors
AppTheme.successGreen       // #2E7D32 - النجاح
AppTheme.warningOrange      // #ED6C02 - التحذير
AppTheme.infoBlue           // #0288D1 - المعلومات
AppTheme.pendingYellow      // #FFB300 - قيد الانتظار
AppTheme.disabledGrey       // #BDBDBD - معطل
AppTheme.borderGrey         // #E0E0E0 - الحدود
AppTheme.cardBackground     // #FFFFFF - خلفية البطاقات
AppTheme.inputBackground    // #F5F5F5 - خلفية الحقول
```

---

## 📝 أحجام الخطوط - Font Sizes

### قبل - Before
```dart
Text(
  'عنوان',
  style: TextStyle(fontSize: 18),  // ❌ حجم مشفر
)
```

### بعد - After
```dart
Text(
  'عنوان',
  style: TextStyle(fontSize: AppTheme.fontSizeTitle),  // ✅ حجم دلالي
)
```

### الأحجام المتاحة - Available Sizes

```dart
AppTheme.fontSizeXS        // 10.0 - نصوص صغيرة جداً
AppTheme.fontSizeCaption   // 11.0 - تسميات وتعليقات
AppTheme.fontSizeSmall     // 12.0 - نصوص ثانوية
AppTheme.fontSizeBody      // 13.0 - نصوص أساسية
AppTheme.fontSizeMedium    // 14.0 - نصوص متوسطة
AppTheme.fontSizeSubtitle  // 16.0 - عناوين فرعية
AppTheme.fontSizeTitle     // 18.0 - عناوين رئيسية
AppTheme.fontSizeHeadline  // 20.0 - عناوين بارزة
AppTheme.fontSizeLarge     // 24.0 - نصوص كبيرة
AppTheme.fontSizeXL        // 28.0 - نصوص كبيرة جداً
AppTheme.fontSizeDisplay   // 32.0 - عرض رئيسي
```

### دليل التحويل - Conversion Guide

| القيمة المشفرة | الثابت البديل | الاستخدام |
|---------------|---------------|-----------|
| `fontSize: 10` | `AppTheme.fontSizeXS` | نصوص صغيرة جداً، footnotes |
| `fontSize: 11` | `AppTheme.fontSizeCaption` | تسميات، تعليقات، timestamps |
| `fontSize: 12` | `AppTheme.fontSizeSmall` | نصوص ثانوية، تفاصيل |
| `fontSize: 13` | `AppTheme.fontSizeBody` | نصوص أساسية، فقرات |
| `fontSize: 14` | `AppTheme.fontSizeMedium` | نصوص متوسطة، أزرار |
| `fontSize: 16` | `AppTheme.fontSizeSubtitle` | عناوين فرعية، subtitles |
| `fontSize: 18` | `AppTheme.fontSizeTitle` | عناوين رئيسية، titles |
| `fontSize: 20` | `AppTheme.fontSizeHeadline` | عناوين بارزة، headlines |
| `fontSize: 24` | `AppTheme.fontSizeLarge` | نصوص كبيرة، large text |
| `fontSize: 28` | `AppTheme.fontSizeXL` | نصوص كبيرة جداً |
| `fontSize: 32+` | `AppTheme.fontSizeDisplay` | عرض رئيسي، display |

---

## 📏 المسافات والتباعد - Spacing

### قبل - Before
```dart
SizedBox(height: 12)  // ❌ قيمة مشفرة
```

### بعد - After
```dart
AppTheme.gapHeightMedium  // ✅ ثابت موحد
```

### المسافات المتاحة - Available Spacing

```dart
// القيم الأساسية - Base Values
AppTheme.spacingXXS    // 2.0
AppTheme.spacingXS     // 4.0
AppTheme.spacingSmall  // 8.0
AppTheme.spacingMedium // 12.0
AppTheme.spacingLarge  // 16.0
AppTheme.spacingXL     // 20.0
AppTheme.spacingXXL    // 24.0
AppTheme.spacingXXXL   // 32.0

// SizedBox جاهزة - Predefined SizedBox
AppTheme.gapXXS        // SizedBox(width: 2, height: 2)
AppTheme.gapXS         // SizedBox(width: 4, height: 4)
AppTheme.gapSmall      // SizedBox(width: 8, height: 8)
AppTheme.gapMedium     // SizedBox(width: 12, height: 12)
AppTheme.gapLarge      // SizedBox(width: 16, height: 16)
AppTheme.gapXL         // SizedBox(width: 20, height: 20)
AppTheme.gapXXL        // SizedBox(width: 24, height: 24)

// عرض فقط - Width Only
AppTheme.gapWidthSmall   // SizedBox(width: 8)
AppTheme.gapWidthMedium  // SizedBox(width: 12)
AppTheme.gapWidthLarge   // SizedBox(width: 16)

// ارتفاع فقط - Height Only
AppTheme.gapHeightSmall  // SizedBox(height: 8)
AppTheme.gapHeightMedium // SizedBox(height: 12)
AppTheme.gapHeightLarge  // SizedBox(height: 16)
```

### دليل التحويل - Conversion Guide

| القيمة المشفرة | الثابت البديل | الاستخدام |
|---------------|---------------|-----------|
| `SizedBox(height: 2)` | `AppTheme.gapHeightXXS` | مسافة صغيرة جداً |
| `SizedBox(height: 4)` | `AppTheme.gapHeightXS` | مسافة صغيرة |
| `SizedBox(height: 8)` | `AppTheme.gapHeightSmall` | مسافة بين العناصر المتجاورة |
| `SizedBox(height: 12)` | `AppTheme.gapHeightMedium` | مسافة متوسطة |
| `SizedBox(height: 16)` | `AppTheme.gapHeightLarge` | مسافة بين الأقسام |
| `SizedBox(height: 20)` | `AppTheme.gapHeightXL` | مسافة كبيرة |
| `SizedBox(height: 24)` | `AppTheme.gapHeightXXL` | مسافة كبيرة جداً |
| `SizedBox(width: 8)` | `AppTheme.gapWidthSmall` | مسافة أفقية صغيرة |
| `SizedBox(width: 12)` | `AppTheme.gapWidthMedium` | مسافة أفقية متوسطة |
| `SizedBox(width: 16)` | `AppTheme.gapWidthLarge` | مسافة أفقية كبيرة |

---

## 📐 الحشوة الداخلية - Padding

### قبل - Before
```dart
Container(
  padding: EdgeInsets.all(12),  // ❌ قيمة مشفرة
)
```

### بعد - After
```dart
Container(
  padding: AppTheme.paddingAllMedium,  // ✅ ثابت موحد
)
```

### الحشوات المتاحة - Available Padding

```dart
// القيم الأساسية - Base Values
AppTheme.paddingXXS    // 2.0
AppTheme.paddingXS     // 4.0
AppTheme.paddingSmall  // 8.0
AppTheme.paddingMedium // 12.0
AppTheme.paddingLarge  // 16.0
AppTheme.paddingXL     // 20.0
AppTheme.paddingXXL    // 24.0
AppTheme.paddingXXXL   // 32.0

// EdgeInsets جاهزة - Predefined EdgeInsets
AppTheme.paddingAllSmall    // EdgeInsets.all(8)
AppTheme.paddingAllMedium   // EdgeInsets.all(12)
AppTheme.paddingAllLarge    // EdgeInsets.all(16)
AppTheme.paddingAllXL       // EdgeInsets.all(20)

// أفقي فقط - Horizontal Only
AppTheme.paddingHorizontalSmall   // EdgeInsets.symmetric(horizontal: 8)
AppTheme.paddingHorizontalMedium  // EdgeInsets.symmetric(horizontal: 12)
AppTheme.paddingHorizontalLarge   // EdgeInsets.symmetric(horizontal: 16)
AppTheme.paddingHorizontalXL      // EdgeInsets.symmetric(horizontal: 20)

// عمودي فقط - Vertical Only
AppTheme.paddingVerticalSmall   // EdgeInsets.symmetric(vertical: 8)
AppTheme.paddingVerticalMedium  // EdgeInsets.symmetric(vertical: 12)
AppTheme.paddingVerticalLarge   // EdgeInsets.symmetric(vertical: 16)
AppTheme.paddingVerticalXL      // EdgeInsets.symmetric(vertical: 20)

// متماثل - Symmetric
AppTheme.paddingSymmetricSmall   // horizontal: 12, vertical: 8
AppTheme.paddingSymmetricMedium  // horizontal: 16, vertical: 12
AppTheme.paddingSymmetricLarge   // horizontal: 20, vertical: 16
```

### دليل التحويل - Conversion Guide

| القيمة المشفرة | الثابت البديل | الاستخدام |
|---------------|---------------|-----------|
| `EdgeInsets.all(8)` | `AppTheme.paddingAllSmall` | حشوة صغيرة |
| `EdgeInsets.all(12)` | `AppTheme.paddingAllMedium` | حشوة متوسطة |
| `EdgeInsets.all(16)` | `AppTheme.paddingAllLarge` | حشوة كبيرة |
| `EdgeInsets.symmetric(horizontal: 16)` | `AppTheme.paddingHorizontalLarge` | حشوة أفقية |
| `EdgeInsets.symmetric(vertical: 12)` | `AppTheme.paddingVerticalMedium` | حشوة عمودية |

---

## 🔲 زوايا الحدود - Border Radius

### قبل - Before
```dart
BorderRadius.circular(12)  // ❌ قيمة مشفرة
```

### بعد - After
```dart
AppTheme.radiusMedium  // ✅ ثابت موحد
```

### الزوايا المتاحة - Available Radius

```dart
// القيم الأساسية - Base Values
AppTheme.borderRadiusXS      // 4.0
AppTheme.borderRadiusSmall   // 8.0
AppTheme.borderRadiusMedium  // 12.0
AppTheme.borderRadiusLarge   // 16.0
AppTheme.borderRadiusXL      // 20.0
AppTheme.borderRadiusXXL     // 24.0
AppTheme.borderRadiusRound   // 999.0 (دائري تماماً)

// BorderRadius جاهزة - Predefined BorderRadius
AppTheme.radiusXS      // BorderRadius.all(Radius.circular(4))
AppTheme.radiusSmall   // BorderRadius.all(Radius.circular(8))
AppTheme.radiusMedium  // BorderRadius.all(Radius.circular(12))
AppTheme.radiusLarge   // BorderRadius.all(Radius.circular(16))
AppTheme.radiusXL      // BorderRadius.all(Radius.circular(20))
AppTheme.radiusXXL     // BorderRadius.all(Radius.circular(24))
AppTheme.radiusRound   // BorderRadius.all(Radius.circular(999))
```

### دليل التحويل - Conversion Guide

| القيمة المشفرة | الثابت البديل | الاستخدام |
|---------------|---------------|-----------|
| `BorderRadius.circular(4)` | `AppTheme.radiusXS` | زوايا صغيرة جداً |
| `BorderRadius.circular(8)` | `AppTheme.radiusSmall` | زوايا صغيرة |
| `BorderRadius.circular(12)` | `AppTheme.radiusMedium` | زوايا متوسطة (الأكثر شيوعاً) |
| `BorderRadius.circular(16)` | `AppTheme.radiusLarge` | زوايا كبيرة |
| `BorderRadius.circular(20)` | `AppTheme.radiusXL` | زوايا كبيرة جداً |
| `BorderRadius.circular(24)` | `AppTheme.radiusXXL` | زوايا كبيرة جداً |
| `BorderRadius.circular(999)` | `AppTheme.radiusRound` | دائري تماماً (للأزرار الدائرية) |

---

## 🌟 الظلال - Shadows

### قبل - Before
```dart
BoxShadow(
  color: Colors.black45,
  blurRadius: 22,
  offset: Offset(0, 8),
)  // ❌ قيم مشفرة
```

### بعد - After
```dart
AppTheme.shadowLarge  // ✅ ثابت موحد
```

### الظلال المتاحة - Available Shadows

```dart
AppTheme.shadowSmall   // ظل خفيف (blurRadius: 4, offset: 0,2)
AppTheme.shadowMedium  // ظل متوسط (blurRadius: 8, offset: 0,4)
AppTheme.shadowLarge   // ظل كبير (blurRadius: 16, offset: 0,8)
```

---

## 📱 التصميم المتجاوب - Responsive Design

### الدوال المتاحة - Available Methods

```dart
// الحصول على حجم الشاشة
AppTheme.getScreenSize(context)     // Size
AppTheme.getScreenWidth(context)    // double
AppTheme.getScreenHeight(context)   // double

// تحديد نوع الجهاز
AppTheme.isMobile(context)    // true if width < 600
AppTheme.isTablet(context)    // true if width >= 600
AppTheme.isDesktop(context)   // true if width >= 1200

// قيم متجاوبة
AppTheme.responsiveFontSize(
  context,
  mobile: AppTheme.fontSizeBody,
  tablet: AppTheme.fontSizeSubtitle,
  desktop: AppTheme.fontSizeTitle,
)

AppTheme.responsiveValue(
  context,
  mobile: 16.0,
  tablet: 20.0,
  desktop: 24.0,
)

AppTheme.responsivePadding(
  context,
  mobile: AppTheme.paddingAllSmall,
  tablet: AppTheme.paddingAllMedium,
  desktop: AppTheme.paddingAllLarge,
)

// الحصول على أعرض محتوى مناسب
AppTheme.getMaxContentWidth(context)
// يرجع: 1100 للديسكتوب، 540 للتابلت، width-32 للموبايل

// الحصول على عدد الأعمدة المناسب للشبكة
AppTheme.getGridColumns(
  context,
  mobile: 1,
  tablet: 2,
  desktop: 3,
)

// تحديد الاتجاه
AppTheme.isLandscape(context)  // true if landscape
AppTheme.isPortrait(context)   // true if portrait
```

### مثال عملي - Practical Example

#### قبل - Before
```dart
class ProductGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,  // ❌ ثابت لجميع الأجهزة
      children: products.map((p) => ProductCard(p)).toList(),
    );
  }
}
```

#### بعد - After
```dart
class ProductGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: AppTheme.getGridColumns(
          context,
          mobile: 1,
          tablet: 2,
          desktop: 3,
        ),
        crossAxisSpacing: AppTheme.spacingMedium,
        mainAxisSpacing: AppTheme.spacingMedium,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) => ProductCard(products[index]),
    );
  }
}
```

---

## 🎭 مثال كامل للتحويل - Complete Migration Example

### قبل - Before
```dart
class BrokerDashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFFFFBF2),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'مرحباً بك',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD4AF37),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'لوحة التحكم',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFD4AF37),
                      padding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'طلبات المعاينة',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black,
                      ),
                    ),
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
```

### بعد - After
```dart
class BrokerDashboardScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Padding(
        padding: AppTheme.paddingAllLarge,
        child: Column(
          children: [
            AppTheme.gapHeightXL,
            Container(
              padding: AppTheme.paddingAllMedium,
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: AppTheme.radiusMedium,
                boxShadow: AppTheme.shadowMedium,
              ),
              child: Column(
                children: [
                  Text(
                    'مرحباً بك',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeTitle,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryGold,
                    ),
                  ),
                  AppTheme.gapHeightMedium,
                  Text(
                    'لوحة التحكم',
                    style: TextStyle(
                      fontSize: AppTheme.fontSizeMedium,
                      color: AppTheme.textGrey,
                    ),
                  ),
                  AppTheme.gapHeightLarge,
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryGold,
                      padding: AppTheme.paddingSymmetricMedium,
                      shape: RoundedRectangleBorder(
                        borderRadius: AppTheme.radiusMedium,
                      ),
                    ),
                    child: Text(
                      'طلبات المعاينة',
                      style: TextStyle(
                        fontSize: AppTheme.fontSizeMedium,
                        color: AppTheme.deepBlack,
                      ),
                    ),
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
```

---

## 🚀 خطة الترحيل - Migration Plan

### المرحلة 1: الملفات الأساسية (أولوية عالية)
**Phase 1: Core Files (High Priority)**

1. ✅ `lib/core/theme/app_theme.dart` - إنشاء نظام الثيم
2. ⏳ `lib/screens/broker/broker_dashboard_screen.dart` - لوحة الوسيط
3. ⏳ `lib/screens/user/user_dashboard_screen.dart` - لوحة المستخدم
4. ⏳ `lib/screens/auth/login_screen.dart` - تسجيل الدخول
5. ⏳ `lib/screens/auth/register_screen.dart` - التسجيل

### المرحلة 2: الشاشات الرئيسية (أولوية متوسطة)
**Phase 2: Main Screens (Medium Priority)**

6. ⏳ `lib/screens/broker/broker_offers_screen.dart`
7. ⏳ `lib/screens/broker/broker_appointments_screen.dart`
8. ⏳ `lib/screens/user/user_offers_screen.dart`
9. ⏳ `lib/screens/user/user_appointments_screen.dart`
10. ⏳ جميع الشاشات الأخرى (54 شاشة)

### المرحلة 3: الـ Widgets (أولوية متوسطة)
**Phase 3: Widgets (Medium Priority)**

11. ⏳ جميع الـ Widgets (18 widget)

### المرحلة 4: الاختبارات والتوثيق (أولوية منخفضة)
**Phase 4: Testing & Documentation (Low Priority)**

12. ⏳ اختبار جميع الشاشات على أجهزة مختلفة
13. ⏳ توثيق الأمثلة الشائعة
14. ⏳ إنشاء checklist للمراجعة

---

## 📝 Checklist للمراجعة - Review Checklist

قبل عمل commit، تأكد من:

- [ ] لا توجد قيم `fontSize:` مشفرة (استخدم `AppTheme.fontSize*`)
- [ ] لا توجد `EdgeInsets` مشفرة (استخدم `AppTheme.padding*`)
- [ ] لا توجد `SizedBox` مشفرة (استخدم `AppTheme.gap*`)
- [ ] لا توجد `BorderRadius.circular()` مشفرة (استخدم `AppTheme.radius*`)
- [ ] لا توجد ألوان `Colors.*` مشفرة (استخدم `AppTheme.*Color`)
- [ ] تم اختبار الشاشة على موبايل (320px - 599px)
- [ ] تم اختبار الشاشة على تابلت (600px - 1199px)
- [ ] تم اختبار الشاشة على ديسكتوب (1200px+)
- [ ] تم اختبار الشاشة في الوضع الأفقي والعمودي
- [ ] تم اختبار إمكانية الوصول (تكبير الخط، قارئ الشاشة)

---

## 🛠️ أدوات المساعدة - Helper Tools

### سكريبت البحث عن القيم المشفرة
```bash
# البحث عن fontSize مشفرة
grep -rn "fontSize:" lib/screens/ | grep -v "AppTheme.fontSize"

# البحث عن EdgeInsets مشفرة
grep -rn "EdgeInsets\." lib/screens/ | grep -v "AppTheme.padding"

# البحث عن SizedBox مشفرة
grep -rn "SizedBox(" lib/screens/ | grep -v "AppTheme.gap"

# البحث عن BorderRadius مشفرة
grep -rn "BorderRadius.circular" lib/screens/ | grep -v "AppTheme.radius"

# البحث عن ألوان مشفرة
grep -rn "Colors\." lib/screens/ | grep -v "AppTheme\."
```

### سكريبت التحويل التلقائي (Python)
```python
#!/usr/bin/env python3
import re
import sys

def migrate_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # استبدال fontSize
    content = re.sub(r'fontSize:\s*10\b', 'fontSize: AppTheme.fontSizeXS', content)
    content = re.sub(r'fontSize:\s*11\b', 'fontSize: AppTheme.fontSizeCaption', content)
    content = re.sub(r'fontSize:\s*12\b', 'fontSize: AppTheme.fontSizeSmall', content)
    content = re.sub(r'fontSize:\s*13\b', 'fontSize: AppTheme.fontSizeBody', content)
    content = re.sub(r'fontSize:\s*14\b', 'fontSize: AppTheme.fontSizeMedium', content)
    content = re.sub(r'fontSize:\s*16\b', 'fontSize: AppTheme.fontSizeSubtitle', content)
    content = re.sub(r'fontSize:\s*18\b', 'fontSize: AppTheme.fontSizeTitle', content)
    content = re.sub(r'fontSize:\s*20\b', 'fontSize: AppTheme.fontSizeHeadline', content)
    content = re.sub(r'fontSize:\s*24\b', 'fontSize: AppTheme.fontSizeLarge', content)
    
    # استبدال EdgeInsets
    content = re.sub(r'EdgeInsets\.all\(8\)', 'AppTheme.paddingAllSmall', content)
    content = re.sub(r'EdgeInsets\.all\(12\)', 'AppTheme.paddingAllMedium', content)
    content = re.sub(r'EdgeInsets\.all\(16\)', 'AppTheme.paddingAllLarge', content)
    
    # استبدال SizedBox
    content = re.sub(r'SizedBox\(height:\s*8\)', 'AppTheme.gapHeightSmall', content)
    content = re.sub(r'SizedBox\(height:\s*12\)', 'AppTheme.gapHeightMedium', content)
    content = re.sub(r'SizedBox\(height:\s*16\)', 'AppTheme.gapHeightLarge', content)
    content = re.sub(r'SizedBox\(width:\s*8\)', 'AppTheme.gapWidthSmall', content)
    content = re.sub(r'SizedBox\(width:\s*12\)', 'AppTheme.gapWidthMedium', content)
    content = re.sub(r'SizedBox\(width:\s*16\)', 'AppTheme.gapWidthLarge', content)
    
    # استبدال BorderRadius
    content = re.sub(r'BorderRadius\.circular\(8\)', 'AppTheme.radiusSmall', content)
    content = re.sub(r'BorderRadius\.circular\(12\)', 'AppTheme.radiusMedium', content)
    content = re.sub(r'BorderRadius\.circular\(16\)', 'AppTheme.radiusLarge', content)
    
    # استبدال الألوان
    content = re.sub(r'Colors\.green', 'AppTheme.successGreen', content)
    content = re.sub(r'Colors\.red', 'AppTheme.errorRed', content)
    content = re.sub(r'Colors\.orange', 'AppTheme.warningOrange', content)
    content = re.sub(r'Colors\.blue', 'AppTheme.infoBlue', content)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f"✅ Migrated: {filepath}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python migrate_theme.py <file.dart>")
        sys.exit(1)
    
    migrate_file(sys.argv[1])
```

---

## 📚 مراجع إضافية - Additional Resources

- [Flutter Layout Cheat Sheet](https://medium.com/flutter-community/flutter-layout-cheat-sheet-5363348d037e)
- [Material Design - Spacing](https://material.io/design/layout/spacing-methods.html)
- [Flutter Responsive Design](https://docs.flutter.dev/development/ui/layout/responsive)

---

## 💡 نصائح مهمة - Important Tips

1. **لا تستخدم القيم المشفرة أبداً** - دائماً استخدم ثوابت `AppTheme`
2. **اختبر على أجهزة مختلفة** - موبايل، تابلت، ديسكتوب
3. **اختبر في الوضعين** - أفقي وعمودي
4. **اختبر إمكانية الوصول** - تكبير الخط، قارئ الشاشة
5. **استخدم المعاني الدلالية** - `successGreen` بدلاً من `Colors.green`
6. **اجعل الكود قابل للقراءة** - الثوابت توضح الهدف من القيمة
7. **لا تبالغ في الريسبونسيڤ** - استخدمه فقط عند الضرورة

---

## 🎯 الهدف النهائي - Final Goal

بعد إكمال الترحيل، سيكون لدينا:

- ✅ **0 قيمة مشفرة** - كل القيم في `AppTheme`
- ✅ **تصميم متجاوب 100%** - يعمل على جميع الأجهزة
- ✅ **إمكانية وصول كاملة** - دعم قارئات الشاشة وتكبير النصوص
- ✅ **كود نظيف وقابل للصيانة** - سهل القراءة والتعديل
- ✅ **تجربة مستخدم متسقة** - نفس التصميم في كل مكان

---

**تم الإنشاء:** 2026-08-04  
**الإصدار:** 1.0  
**الحالة:** قيد التنفيذ 🚧
