-- ============================================================================
-- 🔒 إصلاح إشعار الموعد - إزالة معلومات الطالب (Bug #14 - Privacy Fix)
-- ============================================================================
--
-- المشكلة: الإشعار السابق كان يعرض اسم الطالب، وهذا يخالف سياسة الخصوصية
--          التي تنص على "لا تظهر معلومات الطالب — التواصل عبر المكتب"
--
-- الحل: إزالة اسم الطالب من الإشعار، وعرض فقط:
--   • عنوان العرض
--   • الموقع
--   • التاريخ والوقت
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_appointment_created()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_offer_title TEXT;
  v_offer_location TEXT;
BEGIN
  -- جلب عنوان العرض والموقع
  SELECT o.ttl, COALESCE(o.loc->>'city', o.loc->>'d', 'غير محدد')
  INTO v_offer_title, v_offer_location
  FROM offers o
  WHERE o.id = NEW.off_id;

  -- بناء نص الإشعار (بدون معلومات الطالب)
  v_title := '📅 طلب معاينة جديد';
  v_body := 'طلب معاينة جديد على العرض الخاص بك:' || E'\n'
         || 'العرض: ' || COALESCE(v_offer_title, 'عرض') || E'\n'
         || 'الموقع: ' || COALESCE(v_offer_location, 'غير محدد') || E'\n'
         || 'التاريخ: ' || TO_CHAR(NEW.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD') || E'\n'
         || 'الوقت: ' || TO_CHAR(NEW.dt AT TIME ZONE 'Asia/Damascus', 'HH24:MI') || E'\n\n'
         || 'التواصل يتم عبر المكتب فقط';

  -- إشعار لصاحب العرض
  IF NEW.own_id IS NOT NULL THEN
    PERFORM notify_user(
      NEW.own_id,
      2,  -- type: appointment
      v_title,
      v_body,
      NEW.id::text,  -- ref_id
      'appointment_request'  -- action
    );
  END IF;

  -- إشعار للسمسار (إذا موجود ومختلف عن المالك)
  IF NEW.bkr_id IS NOT NULL AND NEW.bkr_id != NEW.own_id THEN
    PERFORM notify_user(
      NEW.bkr_id,
      2,  -- type: appointment
      v_title,
      v_body,
      NEW.id::text,  -- ref_id
      'appointment_request'  -- action
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp';

-- تحصين الـ trigger
REVOKE ALL ON FUNCTION trg_appointment_created() FROM PUBLIC;
