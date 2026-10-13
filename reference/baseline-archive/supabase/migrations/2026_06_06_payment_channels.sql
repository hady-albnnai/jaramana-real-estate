-- ════════════════════════════════════════════════════════════════════════════
-- Migration: إضافة قنوات الدفع لـ app_config
-- Date: 2026-06-06
-- ════════════════════════════════════════════════════════════════════════════
-- يضيف payChannels لـ config مع قيم افتراضية فاضية
-- الإدارة تملأ البيانات لاحقاً من config_editor_screen
-- ════════════════════════════════════════════════════════════════════════════

-- نحضر إعدادات القنوات
DO $$
DECLARE
  v_current JSONB;
  v_pay_channels JSONB;
BEGIN
  -- اجلب config الحالي
  SELECT value INTO v_current FROM app_config WHERE key = 'main';
  IF v_current IS NULL THEN
    RAISE EXCEPTION 'app_config.main not found';
  END IF;

  -- نبني بنية القنوات الافتراضية
  v_pay_channels := jsonb_build_object(
    'haram', jsonb_build_object(
      'enabled', true,
      'name', 'الهرم للحوالات',
      'icon', '🏛️',
      'recipient_name', '',
      'recipient_phone', '',
      'instructions', 'اذهب لأي فرع هرم → اطلب تحويل للاسم والرقم أعلاه → احفظ الإيصال + ارفع صورته'
    ),
    'sham_cash', jsonb_build_object(
      'enabled', true,
      'name', 'شام كاش',
      'icon', '💚',
      'qr_image_url', '',
      'account_number', '',
      'instructions', 'افتح تطبيق شام كاش → امسح الباركود أو حوّل لرقم الحساب → احفظ رقم العملية'
    ),
    'balance', jsonb_build_object(
      'enabled', true,
      'name', 'تحويل رصيد',
      'icon', '📱',
      'syriatel_number', '',
      'mtn_number', '',
      'instructions', 'سيرياتل: *146*رقم*المبلغ# | MTN: *131*رقم*المبلغ# — احفظ رسالة التأكيد'
    ),
    'bank', jsonb_build_object(
      'enabled', true,
      'name', 'تحويل بنكي',
      'icon', '🏦',
      'bank_name', '',
      'account_holder', '',
      'account_number', '',
      'iban', '',
      'branch', '',
      'instructions', 'اذهب لأي فرع → اطلب تحويل داخلي لرقم الحساب → احفظ رقم العملية + الإيصال'
    )
  );

  -- ندمج payChannels في الـ config (دون الإخلال بالباقي)
  v_current := jsonb_set(v_current, '{payChannels}', v_pay_channels, true);

  -- نحفظ
  UPDATE app_config SET value = v_current WHERE key = 'main';

  RAISE NOTICE '✅ payChannels added to app_config.main';
END $$;
