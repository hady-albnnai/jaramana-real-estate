-- ════════════════════════════════════════════════════════════════════════════
-- Migration: PostgreSQL Triggers لإرسال الإشعارات تلقائياً
-- Date: 2026-06-06
-- ════════════════════════════════════════════════════════════════════════════
-- يربط الإشعارات (داخلية + Push FCM) بالأحداث التلقائية:
--   1. موافقة/رفض عرض من الإدارة
--   2. حجز موعد جديد
--   3. قبول/رفض الموعد
--   4. إكمال صفقة
--   5. موافقة دفعة باقة
--   6. عرض جديد منشور يطابق طلباً
-- ════════════════════════════════════════════════════════════════════════════
-- يتطلب: pg_net extension مفعّل (تم سابقاً)
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Helper: تخزين إعدادات Edge Function في app_config للقراءة السهلة
-- ─────────────────────────────────────────────────────────────────────────────
-- نخزن URL الـ Edge Function + anon key في app_config (مفتاح "fcm")
-- لتفادي hardcode داخل كل trigger
INSERT INTO app_config (key, value, description)
VALUES (
  'fcm',
  jsonb_build_object(
    'url', 'https://vsgkgnjtebjxyqwpuopz.supabase.co/functions/v1/send-push-notification',
    'anon_key', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzZ2tnbmp0ZWJqeHlxd3B1b3B6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA1NzA1MzYsImV4cCI6MjA5NjE0NjUzNn0.1i81x_ne8_AciPMWaRxc-8Z-no-lXudLATKcE0A4tUw'
  ),
  'إعدادات Edge Function لإرسال FCM Push'
)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Helper Function: send_push_notification
--    يستدعي Edge Function للإرسال — يستخدمها كل الـ triggers
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION send_push_notification(
  p_uid UUID,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT AS $$
DECLARE
  v_config JSONB;
  v_request_id BIGINT;
BEGIN
  -- لا نرسل لمستخدم فارغ أو غير موجود
  IF p_uid IS NULL THEN RETURN NULL; END IF;

  SELECT value INTO v_config FROM app_config WHERE key = 'fcm';
  IF v_config IS NULL THEN
    RAISE WARNING 'FCM config not found in app_config';
    RETURN NULL;
  END IF;

  -- استدعاء غير متزامن (لا يبطئ trigger)
  SELECT net.http_post(
    url := v_config->>'url',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_config->>'anon_key'
    ),
    body := jsonb_build_object(
      'uid', p_uid,
      'title', p_title,
      'body', p_body,
      'data', p_data
    )
  ) INTO v_request_id;

  RETURN v_request_id;
EXCEPTION WHEN OTHERS THEN
  -- لا نريد فشل trigger بسبب خطأ في الإشعار
  RAISE WARNING 'send_push_notification failed: %', SQLERRM;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION send_push_notification TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Trigger: على تغيير حالة العرض (موافقة/رفض من الإدارة)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_offer_status_changed()
RETURNS TRIGGER AS $$
DECLARE
  v_offer_title TEXT;
  v_title TEXT;
  v_body TEXT;
  v_type INT;
BEGIN
  -- نهتم فقط بتغير الحالة
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;

  v_offer_title := COALESCE(NEW.ttl, 'عرض');

  -- الحالة 2 = منشور (موافقة الإدارة)
  IF NEW.sts = 2 AND OLD.sts = 1 THEN
    v_title := '✅ تم نشر العرض الخاص بك';
    v_body := 'تمت الموافقة على "' || v_offer_title || '" وهو متاح الآن للجمهور.';
    v_type := 0; -- offers

  -- الحالة 3 = مرفوض
  ELSIF NEW.sts = 3 AND OLD.sts = 1 THEN
    v_title := '❌ تم رفض العرض الخاص بك';
    v_body := 'عرض "' || v_offer_title || '" مرفوض. السبب: ' || COALESCE(NEW.rsn, 'غير محدد');
    v_type := 0;

  -- الحالة 4 = منتهي (cron)
  ELSIF NEW.sts = 4 AND OLD.sts = 2 THEN
    v_title := '⏰ انتهت صلاحية العرض الخاص بك';
    v_body := 'عرض "' || v_offer_title || '" انتهت مدته. يمكنك تجديده بـ 500 نقطة.';
    v_type := 0;

  -- الحالة 5 = محجوز
  ELSIF NEW.sts = 5 AND OLD.sts = 2 THEN
    v_title := '🔒 العرض الخاص بك محجوز';
    v_body := 'تم حجز عرض "' || v_offer_title || '" بانتظار إتمام الصفقة.';
    v_type := 0;

  ELSE
    RETURN NEW; -- لا إشعار للحالات الأخرى
  END IF;

  -- إنشاء سجل داخلي
  PERFORM notify_user(NEW.usr_id, v_type, v_title, v_body, NEW.id::text, 'offer');

  -- إرسال FCM
  PERFORM send_push_notification(
    NEW.usr_id,
    v_title,
    v_body,
    jsonb_build_object('type', 'offer', 'id', NEW.id::text)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_offer_status_notify ON offers;
CREATE TRIGGER trg_offer_status_notify
AFTER UPDATE OF sts ON offers
FOR EACH ROW EXECUTE FUNCTION trg_offer_status_changed();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Trigger: حجز موعد جديد (INSERT)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_appointment_created()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
BEGIN
  v_title := '📅 طلب معاينة جديد';
  v_body := 'لديك طلب معاينة جديد في ' ||
            TO_CHAR(NEW.dt, 'YYYY/MM/DD HH24:MI');

  -- إشعار لصاحب العرض
  IF NEW.own_id IS NOT NULL THEN
    PERFORM notify_user(NEW.own_id, 2, v_title, v_body, NEW.id::text, 'appointment');
    PERFORM send_push_notification(
      NEW.own_id, v_title, v_body,
      jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
    );
  END IF;

  -- إشعار للسمسار (إذا موجود ومختلف عن المالك)
  IF NEW.bkr_id IS NOT NULL AND NEW.bkr_id != NEW.own_id THEN
    PERFORM notify_user(NEW.bkr_id, 2, v_title, v_body, NEW.id::text, 'appointment');
    PERFORM send_push_notification(
      NEW.bkr_id, v_title, v_body,
      jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_appointment_notify ON appointments;
CREATE TRIGGER trg_appointment_notify
AFTER INSERT ON appointments
FOR EACH ROW EXECUTE FUNCTION trg_appointment_created();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) Trigger: تغيير حالة الموعد (قبول/رفض/إكمال)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_appointment_status_changed()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_target_uid UUID;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;

  -- المستلم = طالب الموعد (req_id إن وُجد، وإلا own_id)
  -- في schema الحالي: own_id غالباً المالك، نستخدمه افتراضياً
  v_target_uid := NEW.own_id;

  CASE NEW.sts
    WHEN 1 THEN -- مقبول
      v_title := '✅ تم تأكيد موعدك';
      v_body := 'تم قبول موعد المعاينة. يُرجى الالتزام بالحضور في الوقت المحدد.';
    WHEN 2 THEN -- مرفوض
      v_title := '❌ تم رفض موعدك';
      v_body := 'لم يُقبل طلب المعاينة. سبب الرفض: ' || COALESCE(NEW.cnl_rsn, 'غير محدد');
    WHEN 3 THEN -- مكتمل
      v_title := '🎉 تمت المعاينة';
      v_body := 'تم إكمال المعاينة بنجاح. شكراً لاستخدامك التطبيق.';
    WHEN 4 THEN -- ملغي
      v_title := '⚠️ تم إلغاء الموعد';
      v_body := 'تم إلغاء موعد المعاينة. ' || COALESCE(NEW.cnl_rsn, '');
    WHEN 5 THEN -- لم يحضر
      v_title := '😞 سُجّل عدم حضور';
      v_body := 'لم تحضر للموعد. سيتم خصم 500 نقطة من رصيدك.';
    ELSE
      RETURN NEW;
  END CASE;

  IF v_target_uid IS NOT NULL THEN
    PERFORM notify_user(v_target_uid, 2, v_title, v_body, NEW.id::text, 'appointment');
    PERFORM send_push_notification(
      v_target_uid, v_title, v_body,
      jsonb_build_object('type', 'appointment', 'id', NEW.id::text)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_appointment_status_notify ON appointments;
CREATE TRIGGER trg_appointment_status_notify
AFTER UPDATE OF sts ON appointments
FOR EACH ROW EXECUTE FUNCTION trg_appointment_status_changed();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Trigger: إكمال صفقة
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_deal_completed()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- نهتم فقط لما الحالة تتغير لـ 1 (مكتملة)
  IF NEW.sts != 1 OR (TG_OP = 'UPDATE' AND OLD.sts = 1) THEN
    RETURN NEW;
  END IF;

  v_title := '🎉 تمت الصفقة بنجاح';
  v_body := 'مبروك! تم إتمام الصفقة بمبلغ ' || COALESCE(NEW.fin_prc::text, '—') || '.';

  -- إشعار للبائع
  IF NEW.sell_uid IS NOT NULL THEN
    PERFORM notify_user(NEW.sell_uid, 3, v_title, v_body, NEW.id::text, 'payment');
    PERFORM send_push_notification(
      NEW.sell_uid, v_title, v_body,
      jsonb_build_object('type', 'payment', 'id', NEW.id::text)
    );
  END IF;

  -- إشعار للمشتري (إن وجد ومختلف)
  IF NEW.buy_uid IS NOT NULL AND NEW.buy_uid != NEW.sell_uid THEN
    PERFORM notify_user(NEW.buy_uid, 3, v_title, v_body, NEW.id::text, 'payment');
    PERFORM send_push_notification(
      NEW.buy_uid, v_title, v_body,
      jsonb_build_object('type', 'payment', 'id', NEW.id::text)
    );
  END IF;

  -- إشعار للسمسار إن وجد
  IF NEW.brk_uid IS NOT NULL THEN
    PERFORM notify_user(
      NEW.brk_uid, 3,
      '💰 صفقة جديدة لك',
      'تم إتمام صفقة وستحصل على عمولتك.',
      NEW.id::text, 'payment'
    );
    PERFORM send_push_notification(
      NEW.brk_uid,
      '💰 صفقة جديدة لك',
      'تم إتمام صفقة وستحصل على عمولتك.',
      jsonb_build_object('type', 'payment', 'id', NEW.id::text)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_deal_notify ON deals;
CREATE TRIGGER trg_deal_notify
AFTER INSERT OR UPDATE OF sts ON deals
FOR EACH ROW EXECUTE FUNCTION trg_deal_completed();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Trigger: موافقة الإدارة على دفعة باقة
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_payment_approved()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_pkg_name TEXT;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;

  v_pkg_name := CASE NEW.pkg
    WHEN 1 THEN 'الفضية'
    WHEN 2 THEN 'الذهبية'
    ELSE 'المجانية'
  END;

  IF NEW.sts = 1 THEN -- موافقة
    v_title := '✅ تم تفعيل اشتراكك';
    v_body := 'تم تفعيل الباقة ' || v_pkg_name || ' بنجاح. استمتع بالمزايا الجديدة!';
  ELSIF NEW.sts = 2 THEN -- رفض
    v_title := '❌ تم رفض الدفعة';
    v_body := 'لم تُقبل الدفعة. يرجى مراجعة بيانات الدفع والمحاولة مرة أخرى.';
  ELSE
    RETURN NEW;
  END IF;

  PERFORM notify_user(NEW.uid, 3, v_title, v_body, NEW.id::text, 'payment');
  PERFORM send_push_notification(
    NEW.uid, v_title, v_body,
    jsonb_build_object('type', 'payment', 'id', NEW.id::text)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_payment_notify ON payments;
CREATE TRIGGER trg_payment_notify
AFTER UPDATE OF sts ON payments
FOR EACH ROW EXECUTE FUNCTION trg_payment_approved();

-- ─────────────────────────────────────────────────────────────────────────────
-- 8) Trigger: عرض جديد منشور يطابق طلباً موجوداً
--    عند نشر عرض، نبحث عن طلبات نشطة بنفس النوع وسعر ضمن ±20%
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_offer_published_match_requests()
RETURNS TRIGGER AS $$
DECLARE
  v_request RECORD;
  v_title TEXT;
  v_body TEXT;
BEGIN
  -- فقط عند تغيّر i_pub من 0 إلى 1
  IF NEW.i_pub != 1 OR OLD.i_pub = 1 THEN RETURN NEW; END IF;

  v_title := '🎯 عرض جديد يطابق بحثك';
  v_body := 'تم إضافة عرض جديد: "' || COALESCE(NEW.ttl, 'عرض') || '" بسعر ' ||
            COALESCE(NEW.prc::text, '—') || ' — يطابق طلبك.';

  -- ابحث عن طلبات تطابق
  FOR v_request IN
    SELECT id, usr_id FROM requests
    WHERE i_del = 0
      AND sts IN (0, 1) -- نشط أو قيد البحث
      AND typ = NEW.typ
      AND usr_id != NEW.usr_id -- لا نرسل لصاحب العرض نفسه
      AND (
        prc = 0 -- لا قيد سعر
        OR (NEW.prc BETWEEN prc * 0.8 AND prc * 1.2)
      )
    LIMIT 20 -- حد أقصى 20 إشعار لكل عرض
  LOOP
    PERFORM notify_user(
      v_request.usr_id, 1,
      v_title, v_body,
      NEW.id::text, 'offer'
    );
    PERFORM send_push_notification(
      v_request.usr_id, v_title, v_body,
      jsonb_build_object('type', 'offer', 'id', NEW.id::text)
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_offer_match_notify ON offers;
CREATE TRIGGER trg_offer_match_notify
AFTER UPDATE OF i_pub ON offers
FOR EACH ROW EXECUTE FUNCTION trg_offer_published_match_requests();
