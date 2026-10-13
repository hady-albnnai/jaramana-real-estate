-- ════════════════════════════════════════════════════════════════════════════
-- 2026-07-27 — إصلاح سلسلة إشعارات FCM الكاملة (4 علل مترابطة)
-- ────────────────────────────────────────────────────────────────────────────
--  ① register_fcm_token: RPC محصّن يستبدل الكتابة المباشرة من التطبيق في
--     user_devices (كانت محظورة بـ RLS منذ 2026-06-28 → صفر أجهزة مسجلة)
--  ② unregister_fcm_token: مسار إلغاء التسجيل عند تسجيل الخروج (نفس العلة)
--  ③ send_push_notification: يرسل ترويسة x-push-secret من جدول internal_config
--     (قفل الـ edge الذي كان مفتوحاً relay للسبام) — السر يُولَّد هنا ولا
--     يُخزَّن في app_config لأن صف fcm مقروء من anon
--  ④ trg_payment_approved: جسم إشعار الرفض يتضمن سبب الرفض الحقيقي من
--     payments.meta->>'reject_reason' بدل النص العام
--
-- التشغيل: الصق الملف كاملاً في SQL Editor وشغّله — كل البلوكات idempotent.
-- بعده مباشرة: SELECT value FROM public.internal_config WHERE key='push_secret';
-- ════════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ── A) جدول أسرار داخلي: لا منح لأي دور — يُقرأ فقط عبر SECURITY DEFINER ────
CREATE TABLE IF NOT EXISTS public.internal_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT ''
);
ALTER TABLE public.internal_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.internal_config FROM PUBLIC;
REVOKE ALL ON public.internal_config FROM anon;
REVOKE ALL ON public.internal_config FROM authenticated;

-- سياسة رفض صريحة لأدوار العميل: توثّق «default-deny» بالسكيما نفسها وتُخضر linter 0008
-- (لا تغيّر سلوكاً: anon/authenticated كانوا مرفوضين أصلاً؛ service_role والمالك لا تمسهم)
DROP POLICY IF EXISTS internal_config_client_deny ON public.internal_config;
CREATE POLICY internal_config_client_deny ON public.internal_config
  FOR ALL TO anon, authenticated
  USING (false) WITH CHECK (false);

-- توليد سر الإرسال (48 محرف hex). لا يُكتب في المستودع أبداً.
INSERT INTO public.internal_config(key, value)
VALUES ('push_secret', encode(extensions.gen_random_bytes(24), 'hex'))
ON CONFLICT (key) DO NOTHING;

-- قيد UNIQUE على device_token (مطلوب لـ ON CONFLICT) — موجود أصلاً في الأغلب
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'user_devices_device_token_key'
      AND conrelid = 'public.user_devices'::regclass
  ) THEN
    ALTER TABLE public.user_devices
      ADD CONSTRAINT user_devices_device_token_key UNIQUE (device_token);
  END IF;
END $$;

-- ── B) ① register_fcm_token — تسجيل/تنشيط توكن جهاز المستخدم ────────────────
CREATE OR REPLACE FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text DEFAULT 'android')
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_token TEXT;
  v_exists BOOLEAN;
BEGIN
  -- توافق الهوية عند وجود جلسة Supabase حقيقية (نمط الدوال الداخلية)
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- المستخدم موجود وغير محذوف
  SELECT TRUE INTO v_exists FROM public.users
    WHERE id = p_user_uid AND i_del = 0;
  IF v_exists IS NULL THEN RAISE EXCEPTION 'USER_NOT_FOUND'; END IF;

  -- تحقق من التوكن والمنصة
  v_token := BTRIM(COALESCE(p_token, ''));
  IF LENGTH(v_token) < 20 OR LENGTH(v_token) > 512 THEN
    RAISE EXCEPTION 'DEVICE_TOKEN_INVALID';
  END IF;
  IF COALESCE(p_platform, '') NOT IN ('android', 'ios', 'web') THEN
    RAISE EXCEPTION 'PLATFORM_INVALID';
  END IF;

  -- جهاز نشط واحد لكل مستخدم: شطّب أي توكن آخر له
  UPDATE public.user_devices
     SET is_active = FALSE, ts_upd = NOW()
   WHERE uid = p_user_uid
     AND device_token <> v_token
     AND is_active = TRUE;

  -- سجّل/أعد تنشيط هذا التوكن؛ وإن كان مسنداً لمستخدم آخر أعِد إسناده
  INSERT INTO public.user_devices (uid, device_token, platform, is_active, ts_crt, ts_upd)
  VALUES (p_user_uid, v_token, p_platform, TRUE, NOW(), NOW())
  ON CONFLICT (device_token) DO UPDATE
    SET uid = EXCLUDED.uid,
        platform = EXCLUDED.platform,
        is_active = TRUE,
        ts_upd = NOW();

  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_fcm_token(p_user_uid uuid, p_token text, p_platform text) TO service_role;

-- ── C) ② unregister_fcm_token — إلغاء التوكن عند تسجيل الخروج ────────────────
CREATE OR REPLACE FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- يشطّب فقط سجلاً يملكه هذا المستخدم (لا يمس توكنات الآخرين)
  UPDATE public.user_devices
     SET is_active = FALSE, ts_upd = NOW()
   WHERE device_token = BTRIM(COALESCE(p_token, ''))
     AND uid = p_user_uid;

  RETURN TRUE;
END;
$function$;

REVOKE ALL ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_fcm_token(p_user_uid uuid, p_token text) TO service_role;

-- ── D) ④ trg_payment_approved — سبب الرفض الحقيقي في جسم الإشعار ────────────
CREATE OR REPLACE FUNCTION public.trg_payment_approved()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_pkg_name TEXT;
  v_reason TEXT;
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
  ELSIF NEW.sts = 2 THEN -- رفض — مع السبب المسجل في meta
    v_title := '❌ تم رفض الدفعة';
    v_reason := COALESCE(NULLIF(BTRIM(COALESCE(NEW.meta->>'reject_reason', '')), ''), '');
    IF v_reason <> '' THEN
      v_body := 'لم تُقبل الدفعة — السبب: ' || LEFT(v_reason, 140) ||
                ' · صحّح البيانات وأعد الطلب من «سجل دفعاتي».';
    ELSE
      v_body := 'لم تُقبل الدفعة. يرجى مراجعة بيانات الدفع والمحاولة مرة أخرى.';
    END IF;
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
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp';

-- ── E) ③ send_push_notification — ترويسة x-push-secret لقفل الـ edge ────────
CREATE OR REPLACE FUNCTION public.send_push_notification(
  p_uid UUID,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS BIGINT AS $$
DECLARE
  v_config JSONB;
  v_secret TEXT;
  v_request_id BIGINT;
BEGIN
  -- لا نرسل لمستخدم فارغ أو غير موجود
  IF p_uid IS NULL THEN RETURN NULL; END IF;

  SELECT value INTO v_config FROM app_config WHERE key = 'fcm';
  IF v_config IS NULL THEN
    RAISE WARNING 'FCM config not found in app_config';
    RETURN NULL;
  END IF;

  -- السر الداخلي من جدول لا يصله anon (الـ edge يرفض الطلب بدونه)
  SELECT value INTO v_secret FROM public.internal_config WHERE key = 'push_secret';
  IF v_secret IS NULL OR v_secret = '' THEN
    RAISE WARNING 'push_secret missing — شغّل مايغريشن 2026_07_27_fcm_push_fix.sql';
    RETURN NULL;
  END IF;

  -- استدعاء غير متزامن (لا يبطئ trigger)
  SELECT net.http_post(
    url := v_config->>'url',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_config->>'anon_key',
      'x-push-secret', v_secret
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
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp';

-- إبقاء التحصين الحي (مُثبت ببروبات PGRST202) كدفاع إضافي
REVOKE ALL ON FUNCTION public.send_push_notification(p_uid uuid, p_title text, p_body text, p_data jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.send_push_notification(p_uid uuid, p_title text, p_body text, p_data jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_push_notification(p_uid uuid, p_title text, p_body text, p_data jsonb) TO service_role;
