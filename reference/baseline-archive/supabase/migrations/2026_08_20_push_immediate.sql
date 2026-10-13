-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — push فوري لأحداث الاستشارة الحرجة (بلا انتظار الكرون)
--
-- المشكلة الأصلية (من قائمة المالك): «تأخر push بدأ الجلسة».
-- الجذر: إشعارات الاستشارة الحرجة (بدأ الجلسة تلقائياً، انتهاؤها،
-- waitlist، تذكير الموعد، «المحامي جاهز» للمحامي…) كانت تُوضع في
-- consultation_event_outbox ويُعالجها كرون كل دقيقة واحدة
-- (process-consultation-outbox-v2) ⇒ تأخير يصل دقيقة كاملة للـ push.
--
-- الإصلاح: التريغر نفسه يصرّف الطابور **فوراً** بعد كل إدراج (نفس
-- المعاملة — الصف الجديد يظهر فيها)، فالبوش يخرج لحظياً. الكرون يبقى
-- كما هو للتعافي من أي فشل (retry بدل الانتظار الضائع).
--
-- الأمان: الاستدعاء داخل BEGIN/EXCEPTION — أي خطأ بالتصريف لا يكسر
-- معاملة الإشعار نفسها، والكرون سيلتقط الصف المتبقي بالمحاولة الجاية.
-- لا تكرر إشعاراً: المعالِج يعلّم الصف processing/sent بنفس اللحظة.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.enqueue_consultation_notification_push()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id=NEW.uid;
  IF NEW.act IN ('legal_session_auto_started','legal_session_ended','legal_waitlist_available',
     'legal_payment_needs_new_slot','legal_appointment_reminder')
     OR (NEW.act='legal_onsite_confirmed' AND v_role=7)
     OR (NEW.act='legal_consultation_update' AND NEW.ttl LIKE '✅ قبل المحامي%') THEN
    INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
    VALUES('notification:'||NEW.id,NEW.act,NEW.uid,
      CASE WHEN NEW.ref_id ~* '^[0-9a-f-]{36}$' THEN NEW.ref_id::uuid ELSE NULL END,
      jsonb_build_object('title',NEW.ttl,'body',NEW.bdy,'act',NEW.act,'ref_id',NEW.ref_id))
    ON CONFLICT(event_key) DO NOTHING;
    -- 🚀 2026-08-20: تصريف فوري (كان ينتظر كرون الدقيقة) — الصف الجديد
    -- ظاهر بنفس المعاملة فتُرسل دفعته الآن، والفشل يُترك للكرون.
    BEGIN
      PERFORM public.process_consultation_outbox_v2();
    EXCEPTION WHEN OTHERS THEN
      NULL; -- الكرون الدوري يعيد المحاولة على الصفوف المتبقية
    END;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.enqueue_consultation_notification_push() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enqueue_consultation_notification_push() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_consultation_notification_push() TO service_role;

-- التريغر trg_enqueue_consultation_push يبقى كما هو (يشير للدالة المعاد تعريفها)

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج:
--   ① immediate_drain = true ⇒ الدالة تستدعي المعالِج فوراً بعد الإدراج
--   ② worker_active = true    ⇒ كرون المعالِج لا يزال مجدولاً (retry)
-- ──────────────────────────────────────────────────────────────────────
SELECT
  pg_get_functiondef('public.enqueue_consultation_notification_push()'::regprocedure)
    LIKE '%process_consultation_outbox_v2%' AS immediate_drain,
  EXISTS(SELECT 1 FROM cron.job WHERE command='SELECT public.process_consultation_outbox_v2();')
    AS worker_active;
