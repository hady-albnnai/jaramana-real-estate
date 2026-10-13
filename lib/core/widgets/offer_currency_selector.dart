import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/config_provider.dart';
import '../constants/db_constants.dart';
import '../theme/app_theme.dart';

/// منتقي عملة العرض من إعدادات جرمانا المركزية.
///
/// لا يحوّل الأسعار ولا يعرض إلا العملات التي فعّلها المدير. عند تغيير
/// الإعدادات وإيقاف العملة الحالية، ينتقل الحقل إلى العملة الافتراضية فقط
/// للعروض/الطلبات الجديدة؛ العروض القديمة تعالج بقرار الإدارة على السيرفر.
class OfferCurrencySelector extends StatelessWidget {
  const OfferCurrencySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.decoration,
    this.isExpanded = true,
    this.preserveExistingValue = false,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final InputDecoration? decoration;
  final bool isExpanded;

  /// في شاشة تعديل عرض قديم: لا نبدّل عملته تلقائياً حتى لو أوقف المدير
  /// استقبالها للعروض الجديدة. القرار يبقى إعادة تسعير أو إخفاء إداري.
  final bool preserveExistingValue;

  @override
  Widget build(BuildContext context) {
    final config = context.watch<ConfigProvider>().config;
    final allowed = config?.allowedOfferCurrencies ?? Currency.supported;
    final hasUnavailableExistingValue =
        preserveExistingValue && !allowed.contains(value);
    final choices = hasUnavailableExistingValue
        ? <int>[value, ...allowed]
        : allowed;
    final resolved = hasUnavailableExistingValue
        ? value
        : (allowed.contains(value)
            ? value
            : (config?.defaultOfferCurrency ?? Currency.usd));

    // للعروض الجديدة فقط، نبقي الحالة موافقة لإعدادات المدير إن أوقف عملة.
    if (!preserveExistingValue && resolved != value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onChanged(resolved);
      });
    }

    return DropdownButtonFormField<int>(
      value: resolved,
      isExpanded: isExpanded,
      dropdownColor: AppTheme.surfaceBlack,
      style: const TextStyle(color: AppTheme.textWhite),
      decoration: decoration ?? const InputDecoration(border: OutlineInputBorder()),
      items: choices
          .map((currency) => DropdownMenuItem<int>(
                value: currency,
                child: Text(
                  hasUnavailableExistingValue && currency == value
                      ? '${Currency.labelOf(currency)} — عرض قائم'
                      : Currency.labelOf(currency),
                  overflow: TextOverflow.ellipsis,
                ),
              ))
          .toList(),
      onChanged: (selected) {
        if (selected != null) onChanged(selected);
      },
    );
  }
}
