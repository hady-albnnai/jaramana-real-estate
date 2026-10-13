-- ============================================================================
-- 🔔 إصلاح إشعار الموعد - إضافة تفاصيل العرض (Bug #14) — 2026-08-05
--
-- المشكلة: إشعار طلب حجز موعد لا يظهر تفاصيل العرض (العنوان، الموقع، الوقت)
--          لصاحب العرض، فقط يقول "لديك طلب معاينة جديد في YYYY/MM/DD HH24:MI"
--
-- الحل: تحديث trg_appointment_created ليشمل:
--   • عنوان العرض
--   • التاريخ والوقت بشكل واضح
--   • الموقع (إذا متوفر)
--   • اسم الطالب (إذا متوفر)
-- ============================================================================

CREATE OR REPLACE FUNCTION trg_appointment_created()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_offer_title TEXT;
  v_offer_location TEXT;
  v_student_name TEXT;
BEGIN
  -- جلب عنوان العرض والموقع
  SELECT o.ttl, COALESCE(o.loc->>'city', o.loc->>'d', 'غير محدد')
  INTO v_offer_title, v_offer_location
  FROM offers o
  WHERE o.id = NEW.off_id;
  
  -- جلب اسم الطالب
  SELECT COALESCE(u.nm, u.usr, 'مستخدم')
  INTO v_student_name
  FROM users u
  WHERE u.id = NEW.req_uid;

  -- بناء نص الإشعار المفصل
  v_title := '📅 طلب معاينة جديد';
  v_body := 'طلب معاينة جديد من ' || COALESCE(v_student_name, 'مستخدم') || E'\n'
         || 'العرض: ' || COALESCE(v_offer_title, 'عرض') || E'\n'
         || 'الموقع: ' || COALESCE(v_offer_location, 'غير محدد') || E'\n'
         || 'التاريخ: ' || TO_CHAR(NEW.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD') || E'\n'
         || 'الوقت: ' || TO_CHAR(NEW.dt AT TIME ZONE 'Asia/Damascus', 'HH24:MI');

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
    -- send_push_notification يُستدعى تلقائياً داخل notify_user (بعد migration 2026_07_30)
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
    -- send_push_notification يُستدعى تلقائياً داخل notify_user (بعد migration 2026_07_30)
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp';

-- تحصين الـ trigger
REVOKE ALL ON FUNCTION trg_appointment_created() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION trg_appointment_created() FROM anon, authenticated;
-- Triggers لا تحتاج GRANT - تُنفذ تلقائياً

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① Trigger يستخدم notify_user → المتوقع: true
SELECT position('notify_user' in pg_get_functiondef(p.oid)) > 0 AS uses_notify_user
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'trg_appointment_created';

-- ② Trigger يتضمن تفاصيل العرض → المتوقع: true
SELECT position('v_offer_title' in pg_get_functiondef(p.oid)) > 0 AS includes_offer_details
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'trg_appointment_created';
