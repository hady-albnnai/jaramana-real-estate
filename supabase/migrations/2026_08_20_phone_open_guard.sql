-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — ثغرة 3/4: حارس الاستشارة الهاتفية المفتوحة بمسار V2
--
-- المشكلة (QUANTUM_FLOW_ANALYSIS_2026_08_19 §5 «ثغرة 8»):
-- prepare_consultation_intent_v2 (phone_new) كان بلا فحص الاستشارة
-- المفتوحة — الحارس OPEN_CONSULTATION_EXISTS موجود فقط بالمسار القديم
-- create_legal_consultation_internal ⇒ إمكانية استشارة هاتفية ثانية
-- مدفوعة بينما الأولى نشطة.
--
-- الإصلاح: نفس منطق الحارس القديم داخل prepare لمسار phone_new حصراً
-- (الهاتفية) — معلّقة (0/5) أو مقبولة بلا بدء أو عليها جلسة V2 حية.
-- رفض مبكر برسالة معروفة الترجمة بالواجهة قبل أي حجز أو دفع.
-- الحضورية تبقى كما هي (لم تكن مشمولة ببلاغ التحليل).
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.prepare_consultation_intent_v2(
  p_user_uid uuid,
  p_flow text,
  p_parent_consultation_id uuid,
  p_subject text,
  p_attachments text[],
  p_slot timestamptz,
  p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE
  v_existing public.consultation_intents%ROWTYPE;
  v_parent public.legal_consultations%ROWTYPE;
  v_cfg jsonb;
  v_phone numeric; v_onsite numeric; v_renew numeric;
  v_flow text := lower(trim(COALESCE(p_flow,'')));
  v_service integer; v_amount numeric; v_discount numeric := 0;
  v_lawyer uuid; v_alias text; v_intent uuid; v_reservation uuid;
  v_gap integer; v_slot_end timestamptz; v_path text;
BEGIN
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REQUIRED'; END IF;
  IF v_flow NOT IN ('phone_new','onsite_new','phone_renew','onsite_convert') THEN
    RAISE EXCEPTION 'INVALID_CONSULTATION_FLOW';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id=p_user_uid AND sts=0 AND i_del=0) THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  -- 🔒 ثغرة 3 (2026-08-20): حارس الاستشارة المفتوحة بمسار V2.
  -- كان الفحص موجوداً بالمسار القديم (create_legal_consultation_internal)
  -- فقط ⇒ بمسار V2 يمكن نظرياً إنشاء استشارة هاتفية ثانية بينما الأولى
  -- نشطة. نطبق نفس منطق الحارس القديم مع مصدر الحقيقة الحديث (جلسات V2):
  --   status IN (0,5) = معلّقة/بانتظار استكمال
  --   status=1 بلا بدء محادثة (Legacy)
  --   status=1 وعليها جلسة V2 حية (ready/join_window/active)
  IF v_flow='phone_new' THEN
    IF EXISTS (
      SELECT 1 FROM public.legal_consultations c
      WHERE c.user_uid=p_user_uid AND c.service_type=0 AND c.i_del=0
        AND (
          c.status IN (0,5)
          OR (c.status=1 AND c.chat_started_at IS NULL)
          OR EXISTS (
            SELECT 1 FROM public.consultation_chat_sessions s
            WHERE s.consultation_id=c.id AND s.status IN ('ready','join_window','active')
          )
        )
    ) THEN
      RAISE EXCEPTION 'OPEN_CONSULTATION_EXISTS';
    END IF;
  END IF;

  SELECT * INTO v_existing FROM public.consultation_intents
   WHERE user_uid=p_user_uid AND idempotency_key=p_idempotency_key;
  IF v_existing.id IS NOT NULL THEN
    RETURN jsonb_build_object('success',true,'intent_id',v_existing.id,'status',v_existing.status,
      'quoted_amount',v_existing.quoted_amount,'reservation_id',v_existing.reservation_id,'duplicate',true);
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(p_user_uid::text || ':' || v_flow,0));
  SELECT value INTO v_cfg FROM public.app_config WHERE key='main';
  v_phone := (v_cfg->'legalPrice'->>'phone')::numeric;
  v_onsite := (v_cfg->'legalPrice'->>'onsite')::numeric;
  v_renew := (v_cfg->'legalPrice'->>'renew')::numeric;
  IF v_phone IS NULL OR v_onsite IS NULL OR v_renew IS NULL OR v_phone<0 OR v_onsite<0 OR v_renew<0 THEN
    RAISE EXCEPTION 'INVALID_LEGAL_PRICE';
  END IF;
  v_gap := GREATEST(15,COALESCE((public.appt_booking_config()->>'gap_mins')::integer,60));

  IF v_flow IN ('phone_renew','onsite_convert') THEN
    SELECT * INTO v_parent FROM public.legal_consultations
     WHERE id=p_parent_consultation_id AND user_uid=p_user_uid AND service_type=0 AND i_del=0
     FOR UPDATE;
    IF v_parent.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
    IF v_parent.lawyer_uid IS NULL THEN RAISE EXCEPTION 'NO_LAWYER_ASSIGNED'; END IF;
    v_lawyer := v_parent.lawyer_uid;
  END IF;

  IF v_flow IN ('phone_new','onsite_new') AND length(trim(COALESCE(p_subject,'')))<10 THEN
    RAISE EXCEPTION 'SUBJECT_TOO_SHORT';
  END IF;
  IF COALESCE(array_length(p_attachments,1),0)>5 THEN RAISE EXCEPTION 'TOO_MANY_ATTACHMENTS'; END IF;
  FOREACH v_path IN ARRAY COALESCE(p_attachments,'{}'::text[]) LOOP
    IF v_path NOT LIKE p_user_uid::text || '/%' OR position('..' IN v_path)>0 THEN
      RAISE EXCEPTION 'INVALID_ATTACHMENT_PATH';
    END IF;
  END LOOP;

  IF v_flow='phone_new' THEN
    v_service:=0; v_amount:=v_phone;
    v_lawyer:=public.pick_next_lawyer('{}'::uuid[],false);
  ELSIF v_flow='phone_renew' THEN
    v_service:=0; v_amount:=v_renew;
    IF v_parent.chat_started_at IS NULL OR now()>v_parent.chat_started_at+interval '7 days' THEN
      RAISE EXCEPTION 'CHAT_EXPIRED_7DAYS';
    END IF;
  ELSIF v_flow='onsite_new' THEN
    v_service:=1; v_amount:=v_onsite;
    IF p_slot IS NULL THEN RAISE EXCEPTION 'SLOT_REQUIRED_FOR_ONSITE'; END IF;
    SELECT lp.uid INTO v_lawyer
    FROM public.lawyer_profiles lp JOIN public.users u ON u.id=lp.uid
    WHERE lp.is_active=true AND u.role=7 AND u.sts=0 AND u.i_del=0
      AND EXISTS (
        SELECT 1 FROM public.get_lawyer_free_slots(lp.uid,30) s
        WHERE abs(extract(epoch FROM (s.slot_dt-p_slot)))<1
      )
    ORDER BY lp.active_tasks_count,lp.created_at LIMIT 1;
  ELSE
    v_service:=1; v_discount:=v_phone; v_amount:=GREATEST(0,v_onsite-v_phone);
    IF p_slot IS NULL THEN RAISE EXCEPTION 'SLOT_REQUIRED_FOR_ONSITE'; END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.get_lawyer_free_slots(v_lawyer,30) s
      WHERE abs(extract(epoch FROM (s.slot_dt-p_slot)))<1
    ) THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END IF;
  END IF;
  IF v_lawyer IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_LAWYERS'; END IF;
  v_alias:=public.lawyer_alias_for(v_lawyer);

  INSERT INTO public.consultation_intents(
    user_uid,flow,parent_consultation_id,subject,attachments,service_type,lawyer_uid,
    quoted_amount,base_discount,price_snapshot,status,idempotency_key,expires_at
  ) VALUES (
    p_user_uid,v_flow,p_parent_consultation_id,COALESCE(NULLIF(trim(p_subject),''),v_parent.subject,''),
    COALESCE(p_attachments,'{}'::text[]),v_service,v_lawyer,v_amount,v_discount,
    jsonb_build_object('phone',v_phone,'onsite',v_onsite,'renew',v_renew,'captured_at',now()),
    'draft',p_idempotency_key,CASE WHEN v_service=1 THEN now()+interval '6 hours' ELSE NULL END
  ) RETURNING id INTO v_intent;

  IF v_service=1 THEN
    v_slot_end:=p_slot+make_interval(mins=>v_gap);
    BEGIN
      INSERT INTO public.lawyer_time_reservations(
        lawyer_uid,user_uid,consultation_intent_id,slot_start,slot_end,status,
        hold_expires_at,idempotency_key
      ) VALUES (v_lawyer,p_user_uid,v_intent,p_slot,v_slot_end,'held',now()+interval '6 hours',p_idempotency_key)
      RETURNING id INTO v_reservation;
    EXCEPTION WHEN exclusion_violation OR unique_violation THEN
      RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
    END;
    UPDATE public.consultation_intents SET reservation_id=v_reservation WHERE id=v_intent;
  END IF;

  RETURN jsonb_build_object('success',true,'intent_id',v_intent,'flow',v_flow,
    'quoted_amount',v_amount,'base_discount',v_discount,'reservation_id',v_reservation,
    'hold_expires_at',CASE WHEN v_service=1 THEN now()+interval '6 hours' ELSE NULL END,
    'lawyer_alias',COALESCE(v_alias,'محامي المكتب'));
END;
$function$;
REVOKE ALL ON FUNCTION public.prepare_consultation_intent_v2(uuid,text,uuid,text,text[],timestamptz,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.prepare_consultation_intent_v2(uuid,text,uuid,text,text[],timestamptz,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_consultation_intent_v2(uuid,text,uuid,text,text[],timestamptz,uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج: open_guard_patched = true ⇒ الثغرة 3 مغلقة
-- ──────────────────────────────────────────────────────────────────────
SELECT pg_get_functiondef('public.prepare_consultation_intent_v2(uuid,text,uuid,text,text[],timestamptz,uuid)'::regprocedure)
  LIKE '%OPEN_CONSULTATION_EXISTS%' AS open_guard_patched;
