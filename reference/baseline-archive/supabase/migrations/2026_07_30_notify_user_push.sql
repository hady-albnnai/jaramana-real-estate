-- ============================================================================
-- 🔔 البوش الخارجي لكل مسارات الإشعار — 2026-07-30
--
-- الاكتشاف: جرد شامل لمسارات الإشعار الحية (28 دالة) كشف أن **22 منها**
-- تُدرج صف notifications بلا أي استدعاء لـ send_push_notification ⇒ الإشعار
-- يظهر داخل التطبيق فقط، ولا يصل الجهاز إطلاقاً وهو مغلق.
--
-- الجذر: الدالة المركزية notify_user() — التي تستخدمها أغلب المسارات —
-- تكتفي بـ INSERT. فالمشكلة ليست 22 عطلاً منفصلاً بل عطل واحد بالمنبع.
--
-- المتضررون (أمثلة حرجة):
--   • trg_offer_status_changed  ⇒ نشر/رفض/انتهاء/حجز العرض — أهم إشعار للمالك
--   • owner_respond_appointment ⇒ رد صاحب العرض على طلب المعاينة
--   • book_appointment_internal ⇒ طلب معاينة جديد
--   • trg_appt_notify_supervisor ⇒ إسناد موعد للمشرف
--   • expire_packages / expire_requests ⇒ انتهاء الاشتراك والطلب
--   • كل مسارات المحامي/المعقّب (expediting) والتحقق (verification)
--
-- الإصلاح: استدعاء البوش داخل notify_user نفسها ⇒ الـ22 مساراً تُصلَح دفعة
-- واحدة. الاستدعاء دفاعي (EXCEPTION WHEN OTHERS) فلا يكسر أي معاملة إن تعذّر
-- البوش، ولا يُرسَل لمستخدم محذوف/موقوف.
--
-- ملاحظة: الدوال الست التي تستدعي البوش صراحةً لا تتأثر — هي لا تمر عبر
-- notify_user أصلاً (تُدرج مباشرةً)، فلا ازدواج.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_user(
  p_uid uuid,
  p_type integer,
  p_title text,
  p_body text,
  p_ref_id text DEFAULT ''::text,
  p_action text DEFAULT ''::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
  VALUES (p_uid, p_type, p_title, p_body, p_ref_id, p_action, 0, 0, NOW())
  RETURNING id INTO v_id;

  -- 🔔 البوش الخارجي (أُضيف 2026-07-30): ثانوي تماماً — أي فشل هنا لا يُبطل
  -- الإشعار الداخلي ولا يكسر المعاملة التي استدعت الدالة.
  BEGIN
    IF p_uid IS NOT NULL THEN
      PERFORM public.send_push_notification(
        p_uid,
        COALESCE(p_title, ''),
        COALESCE(p_body, ''),
        jsonb_build_object('act', COALESCE(p_action, ''), 'ref_id', COALESCE(p_ref_id, ''))
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;  -- تجاهل صامت: البوش إجراء ثانوي
  END;

  RETURN v_id;
END;
$function$;

-- رباعي التحصين (الدالة كانت محصّنة — نعيد التأكيد بعد إعادة الإنشاء)
REVOKE ALL     ON FUNCTION public.notify_user(uuid, integer, text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_user(uuid, integer, text, text, text, text) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.notify_user(uuid, integer, text, text, text, text) TO service_role;

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① الدالة صارت تستدعي البوش → المتوقع: true
SELECT position('send_push_notification' in pg_get_functiondef(p.oid)) > 0 AS has_push
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'notify_user';

-- ② التحصين سليم → المتوقع: secdef=true · anon=false · service=true
SELECT p.prosecdef AS secdef,
       array_to_string(p.proconfig, ',') AS cfg,
       has_function_privilege('anon',         p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS svc_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'notify_user';

-- ③ عدد المسارات التي صارت تصل للبوش (مباشرةً أو عبر notify_user)
SELECT count(*) AS paths_with_push
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (pg_get_functiondef(p.oid) LIKE '%send_push_notification%'
       OR pg_get_functiondef(p.oid) LIKE '%notify_user(%');
