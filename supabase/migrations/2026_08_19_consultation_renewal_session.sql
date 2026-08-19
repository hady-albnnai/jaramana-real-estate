-- ══════════════════════════════════════════════════════════════════════
-- 2026-08-19 — ربط دفعة التجديد بالمحادثة (نسخة مصححة)
--
-- 🔍 اكتشاف أثناء تحليل التغطية (2026-08-19): إنشاء جلسة التجديد (renewal
-- 'ready') + رسالة system + إشعار المحامي تتم أصلاً داخل
-- `approve_payment_final_v3` (سلسلة الاعتماد الفعلية: admin → v5 → v4 → v3
-- لمسار phone_renew). النسخة الأولى من هذا الملف أضافت المنطق نفسه في
-- التريغر ⇒ ازدواج (إشعار محامٍ مكرر). هذه النسخة:
--   ① تحذف دالة ensure_renewal_chat_session_v2 إن وُجدت (من نسخة سابقة)
--   ② تعيد تعريف التريغر بالنسخة الأصلية مع إصلاح واحد فقط: ref_id إشعار
--      المستخدم للـ phone_renew = المحادثة الأم (كان يقع على payment_id
--      فيوجّه الضغط إلى محادثة خاطئة).
-- ══════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────
-- ① تنظيف دالة النسخة السابقة (إن طُبّقت) — v3 هي مصدر إنشاء الجلسة
-- ──────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.ensure_renewal_chat_session_v2(uuid, uuid);

-- ──────────────────────────────────────────────────────────────────────
-- ② trg_consultation_payment_v2 — الأصلية + إصلاح ref_id لتجديد المحادثة
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_consultation_payment_v2()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_intent public.consultation_intents%ROWTYPE; v_title text; v_body text; v_act text;
  v_ref text;
BEGIN
  IF NEW.sts=OLD.sts OR NEW.consultation_intent_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_intent FROM public.consultation_intents WHERE id=NEW.consultation_intent_id;
  IF v_intent.id IS NULL THEN RETURN NEW; END IF;
  -- مرجع الإشعار الافتراضي: الاستشارة المُنشأة (phone_new/onsite) أو الدفعة
  v_ref := COALESCE(v_intent.materialized_consultation_id, NEW.id)::text;
  IF NEW.sts=1 THEN
    IF v_intent.flow='phone_new' THEN
      v_title:='✅ تم اعتماد دفعة الاستشارة';
      v_body:='تم إرسال استشارتك تلقائياً إلى المحامي. لا تحتاج لإرسال الطلب مرة ثانية.';
      v_act:='legal_consultation_update';
    ELSIF v_intent.flow='phone_renew' THEN
      v_title:='✅ تم اعتماد تجديد المحادثة';
      v_body:='تم تجهيز مدة جديدة وإشعار المحامي. يبدأ الوقت عند استئنافه وانضمامك أو بعد مهلة الدقيقتين.';
      v_act:='legal_renewal_paid_ready';
      -- 🔄 2026-08-19: ref_id للتجديد = المحادثة الأم (كان يقع على
      -- payment_id ⇒ الضغط على الإشعار يفتح محادثة غير موجودة)
      v_ref := v_intent.parent_consultation_id::text;
    ELSE
      v_title:='✅ تم تثبيت الجلسة الحضورية';
      v_body:='تم اعتماد الدفع وتأكيد الموعد تلقائياً ضمن وقت المحامي المنشور.';
      v_act:='legal_onsite_confirmed';
    END IF;
  ELSIF NEW.sts=2 THEN
    v_title:='❌ لم تُقبل دفعة الاستشارة';
    v_body:='لم تُقبل الدفعة. السبب: '||COALESCE(NULLIF(trim(NEW.meta->>'reject_reason'),''),'راجع البيانات وأعد المحاولة.');
    v_act:='payment';
    UPDATE public.consultation_intents SET status='failed',failure_code='PAYMENT_REJECTED',ts_upd=now()
     WHERE id=v_intent.id AND status='payment_pending';
    UPDATE public.lawyer_time_reservations SET status='released',ts_upd=now()
     WHERE consultation_intent_id=v_intent.id AND status='held';
  ELSIF NEW.sts=3 THEN
    v_title:='↩️ تم التراجع عن اعتماد الدفعة';
    v_body:='تم التراجع عن اعتماد الدفعة. راجع تفاصيل الاستشارة أو تواصل مع المكتب.';
    v_act:='payment_reversed';
  ELSE RETURN NEW;
  END IF;
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(NEW.uid,3,v_title,v_body,v_ref,v_act,0,0,now());
  PERFORM public.send_push_notification(NEW.uid,v_title,v_body,
    jsonb_build_object('act',v_act,'ref_id',v_ref));
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_consultation_payment_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_consultation_payment_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.trg_consultation_payment_v2() TO service_role;

-- التريغرات تبقى كما هي (نفس الأسماء تشير للدالة المُعاد تعريفها)
