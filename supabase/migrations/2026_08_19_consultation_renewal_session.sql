-- ══════════════════════════════════════════════════════════════════════
-- 2026-08-19 — إصلاح مسار تجديد المحادثة (ربط الدفعة بالمحادثة)
-- المشاكل (من بلاغ المالك 2026-08-19):
--   • بعد اعتماد دفعة التجديد تبقى المحادثة القديمة «منتهية» بلا جلسة V2
--     جديدة ⇒ لا يمكن متابعتها رغم الدفع، وتظهر «جدد/ادفع» من جديد.
--   • المحامي لا يُشعر بوجود مدة مدفوعة جاهزة للاستئناف.
-- الحل: عند اعتماد دفعة phone_renew يُنشأ تريغر الجلسة جلسة V2 جديدة
--   (kind='renewal', status='ready') مرتبطة بالدفعة، مع إشعار المحامي.
--   والعكس (admin_reverse_payment_v2) يعمل أصلاً على جلسات 'ready'
--   بالـ payment_id — متوافق تلقائياً.
-- ══════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────
-- ① دالة إنشاء جلسة تجديد V2 (idempotent: لا تكرر إن وُجدت جلسة حية)
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ensure_renewal_chat_session_v2(
  p_consultation_id uuid,
  p_payment_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE
  v_cons public.legal_consultations%ROWTYPE;
  v_cfg jsonb;
  v_minutes integer;
  v_session_id uuid;
BEGIN
  SELECT * INTO v_cons FROM public.legal_consultations
   WHERE id=p_consultation_id AND i_del=0 FOR UPDATE;
  IF v_cons.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  IF v_cons.service_type<>0 THEN RAISE EXCEPTION 'PHONE_CONSULTATION_REQUIRED'; END IF;

  -- منع التكرار: إن وُجدت جلسة حية (ready/join_window/active) نكتفي بها
  SELECT id INTO v_session_id FROM public.consultation_chat_sessions
   WHERE consultation_id=v_cons.id AND status IN ('ready','join_window','active')
   ORDER BY ordinal DESC LIMIT 1;
  IF v_session_id IS NOT NULL THEN
    RETURN jsonb_build_object('success',true,'session_id',v_session_id,'duplicate',true);
  END IF;

  SELECT value INTO v_cfg FROM public.app_config WHERE key='main';
  v_minutes := GREATEST(1, COALESCE((v_cfg->'legalPrice'->>'durationMins')::integer, 15));

  INSERT INTO public.consultation_chat_sessions(
    consultation_id, ordinal, kind, payment_id, duration_minutes,
    free_extension_minutes, status, ts_crt, ts_upd
  ) VALUES (
    v_cons.id,
    COALESCE((SELECT MAX(ordinal)+1 FROM public.consultation_chat_sessions
              WHERE consultation_id=v_cons.id), 1),
    'renewal', p_payment_id, v_minutes, 0, 'ready', now(), now()
  ) RETURNING id INTO v_session_id;

  RETURN jsonb_build_object('success',true,'session_id',v_session_id,
    'duration_minutes',v_minutes,'ordinal',
    (SELECT ordinal FROM public.consultation_chat_sessions WHERE id=v_session_id));
END;
$function$;

REVOKE ALL ON FUNCTION public.ensure_renewal_chat_session_v2(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ensure_renewal_chat_session_v2(uuid,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_renewal_chat_session_v2(uuid,uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- ② trg_consultation_payment_v2 — النسخة الحالية + إنشاء جلسة التجديد
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_consultation_payment_v2()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_intent public.consultation_intents%ROWTYPE; v_title text; v_body text; v_act text;
  v_session jsonb; v_lawyer uuid; v_lname text;
BEGIN
  IF NEW.sts=OLD.sts OR NEW.consultation_intent_id IS NULL THEN RETURN NEW; END IF;
  SELECT * INTO v_intent FROM public.consultation_intents WHERE id=NEW.consultation_intent_id;
  IF v_intent.id IS NULL THEN RETURN NEW; END IF;
  IF NEW.sts=1 THEN
    IF v_intent.flow='phone_new' THEN
      v_title:='✅ تم اعتماد دفعة الاستشارة';
      v_body:='تم إرسال استشارتك تلقائياً إلى المحامي. لا تحتاج لإرسال الطلب مرة ثانية.';
      v_act:='legal_consultation_update';
    ELSIF v_intent.flow='phone_renew' THEN
      v_title:='✅ تم اعتماد تجديد المحادثة';
      v_body:='تم تجهيز مدة جديدة وإشعار المحامي. يبدأ الوقت عند استئنافه وانضمامك أو بعد مهلة الدقيقتين.';
      v_act:='legal_renewal_paid_ready';

      -- 🔄 2026-08-19 (ربط الدفعة بالمحادثة): إنشاء جلسة V2 جديدة للتجديد
      -- حتى تفتح المحادثة بحالة «بانتظار استئناف المحامي» بدل «انتهت».
      IF v_intent.parent_consultation_id IS NOT NULL THEN
        v_session := public.ensure_renewal_chat_session_v2(
          v_intent.parent_consultation_id, NEW.id);

        -- إشعار المحامي: مدة مدفوعة جاهزة للاستئناف
        SELECT lawyer_uid INTO v_lawyer FROM public.legal_consultations
         WHERE id=v_intent.parent_consultation_id AND i_del=0;
        IF v_lawyer IS NOT NULL THEN
          SELECT nm INTO v_lname FROM public.users WHERE id=v_lawyer;
          INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
          VALUES(v_lawyer,1,'🔄 تجديد مدفوع جاهز للاستئناف',
            'اعتمد العميل تجديد المحادثة. اضغط «أنا جاهز» لفتح الجلسة وبدء العداد.',
            v_intent.parent_consultation_id::text,'legal_renewal_paid_ready',0,0,now());
          PERFORM public.send_push_notification(v_lawyer,
            '🔄 تجديد مدفوع جاهز للاستئناف',
            COALESCE(NULLIF(v_lname,''),'العميل')||' جدّد المحادثة — اضغط «أنا جاهز»',
            jsonb_build_object('act','legal_renewal_paid_ready',
              'ref_id',v_intent.parent_consultation_id::text));
        END IF;
      END IF;
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
  VALUES(NEW.uid,3,v_title,v_body,NEW.id::text,v_act,0,0,now());
  PERFORM public.send_push_notification(NEW.uid,v_title,v_body,
    jsonb_build_object('act',v_act,'ref_id',COALESCE(v_intent.materialized_consultation_id,NEW.id)::text));
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_consultation_payment_v2() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_consultation_payment_v2() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.trg_consultation_payment_v2() TO service_role;

-- التريغرات تبقى كما هي (لا حاجة لإعادة إنشائها — نفس الأسماء)
-- DROP TRIGGER IF EXISTS trg_payment_notify_v2 ON public.payments;
-- CREATE TRIGGER trg_payment_notify_v2 AFTER UPDATE OF sts ON public.payments
-- FOR EACH ROW WHEN (NEW.consultation_intent_id IS NOT NULL)
-- EXECUTE FUNCTION public.trg_consultation_payment_v2();
