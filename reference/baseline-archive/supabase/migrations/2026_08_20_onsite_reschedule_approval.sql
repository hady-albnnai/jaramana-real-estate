-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — موافقة المحامي على تغيير موعد الجلسة الحضورية (تراشق)
--
-- قرار المالك: تغيير الموعد من المستخدم كان يُطبَّق فوراً بلا رأي
-- المحامي — خطأ. الآن بنفس مبدأ التراشق في مواعيد المعاينة:
--   • المستخدم يطلب التغيير (اقتراح) — الموعد الحالي يبقى مؤكداً.
--   • المحامي: قبول (يُطبَّق الاقتراح) أو رفض (يُبقى القديم) أو
--     اقتراح وقت بديل — حتى 5 جولات، والبند يخزَّن بـ appointments.neog
--     بنفس بنية التراشق الحالية ({round,by,action,proposed,at}).
-- الأطراف: by='user' (العميل) أو 'lawyer' (المحامي).
-- ══════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────
-- ① طلب العميل تغيير الموعد
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.propose_legal_appointment_change_v2(
  p_user_uid uuid, p_appointment_id uuid, p_slot timestamptz, p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE a public.appointments%ROWTYPE; c public.legal_consultations%ROWTYPE;
  v_neog jsonb; v_rounds integer; v_last jsonb;
BEGIN
  IF p_slot IS NULL OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS'; END IF;
  SELECT * INTO a FROM public.appointments WHERE id=p_appointment_id AND kind='legal' FOR UPDATE;
  IF a.id IS NULL THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  IF a.req_uid<>p_user_uid THEN RAISE EXCEPTION 'NOT_YOUR_APPOINTMENT'; END IF;
  IF a.sts<>1 OR a.dt<=now() THEN RAISE EXCEPTION 'APPOINTMENT_NOT_RESCHEDULABLE'; END IF;
  SELECT * INTO c FROM public.legal_consultations WHERE id=a.consultation_id AND i_del=0 FOR UPDATE;
  IF c.id IS NULL OR c.status<>1 THEN RAISE EXCEPTION 'CONSULTATION_NOT_CONFIRMED'; END IF;

  v_neog := COALESCE(a.neog, '[]'::jsonb);
  v_rounds := jsonb_array_length(v_neog);
  IF v_rounds > 0 THEN
    v_last := v_neog -> -1;
    IF v_last->>'action' = 'counter' THEN
      IF v_last->>'by' = 'user' THEN RAISE EXCEPTION 'CHANGE_REQUEST_PENDING';
      ELSE RAISE EXCEPTION 'LAWYER_PROPOSAL_PENDING'; END IF;
    END IF;
  END IF;
  IF v_rounds >= 5 THEN RAISE EXCEPTION 'NEGOTIATION_ROUNDS_EXCEEDED'; END IF;

  IF NOT EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(c.lawyer_uid,30) s
    WHERE abs(extract(epoch FROM(s.slot_dt-p_slot)))<1) THEN
    RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
  END IF;

  v_neog := v_neog || jsonb_build_object('round', v_rounds+1, 'by', 'user',
    'action', 'counter', 'proposed', p_slot, 'at', now());
  UPDATE public.appointments SET neog=v_neog, ts_crt=ts_crt WHERE id=a.id;

  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(c.lawyer_uid,1,'🔄 العميل يطلب تغيير موعد الجلسة',
    'طلب العميل تغيير الموعد إلى '||to_char(p_slot AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI')
    ||'. اقبل أو ارفض أو اقترح وقتاً بديلاً.',
    a.id::text,'legal_appointment_update',0,0,now());
  PERFORM public.send_push_notification(c.lawyer_uid,'🔄 العميل يطلب تغيير موعد الجلسة',
    'طلب العميل تغيير الموعد إلى '||to_char(p_slot AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI'),
    jsonb_build_object('act','legal_appointment_update','ref_id',a.id::text));

  RETURN jsonb_build_object('success',true,'appointment_id',a.id,'pending',true);
END;
$function$;

REVOKE ALL ON FUNCTION public.propose_legal_appointment_change_v2(uuid,uuid,timestamptz,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.propose_legal_appointment_change_v2(uuid,uuid,timestamptz,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.propose_legal_appointment_change_v2(uuid,uuid,timestamptz,uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- ② رد الطرف الآخر (قبول / رفض / اقتراح بديل)
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.respond_legal_appointment_change_v2(
  p_actor_uid uuid, p_appointment_id uuid, p_accept boolean,
  p_reason text, p_proposed_dt timestamptz, p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE a public.appointments%ROWTYPE; c public.legal_consultations%ROWTYPE;
  v_neog jsonb; v_last jsonb; v_rounds integer; v_target timestamptz;
  old_r public.lawyer_time_reservations%ROWTYPE; v_gap integer; v_new_r uuid;
  v_other uuid; v_other_label text; v_actor_label text; v_dt_text text;
BEGIN
  IF p_idempotency_key IS NULL THEN RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS'; END IF;
  SELECT * INTO a FROM public.appointments WHERE id=p_appointment_id AND kind='legal' FOR UPDATE;
  IF a.id IS NULL THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  IF a.sts<>1 THEN RAISE EXCEPTION 'APPOINTMENT_NOT_RESCHEDULABLE'; END IF;
  SELECT * INTO c FROM public.legal_consultations WHERE id=a.consultation_id AND i_del=0 FOR UPDATE;
  IF c.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;

  v_neog := COALESCE(a.neog, '[]'::jsonb);
  IF jsonb_array_length(v_neog) = 0 THEN RAISE EXCEPTION 'NO_PENDING_CHANGE'; END IF;
  v_last := v_neog -> -1;
  IF v_last->>'action' <> 'counter' THEN RAISE EXCEPTION 'NO_PENDING_CHANGE'; END IF;

  -- تحديد الدور: رد المستخدم يكون على اقتراح المحامي، والعكس
  IF v_last->>'by' = 'user' THEN
    IF p_actor_uid <> c.lawyer_uid THEN RAISE EXCEPTION 'NOT_ASSIGNED_LAWYER'; END IF;
    v_actor_label := 'lawyer'; v_other := c.user_uid; v_other_label := 'المحامي';
  ELSE
    IF p_actor_uid <> c.user_uid THEN RAISE EXCEPTION 'NOT_OWNER'; END IF;
    v_actor_label := 'user'; v_other := c.lawyer_uid; v_other_label := 'العميل';
  END IF;

  v_target := (v_last->>'proposed')::timestamptz;
  v_rounds := jsonb_array_length(v_neog);

  IF p_accept THEN
    -- تطبيق الاقتراح الحالي: تحقق من توفره ثم ثبّته مؤكداً
    IF v_target IS NULL THEN RAISE EXCEPTION 'INVALID_PROPOSED_SLOT'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(c.lawyer_uid,30) s
      WHERE abs(extract(epoch FROM(s.slot_dt-v_target)))<1) THEN
      RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
    END IF;
    SELECT * INTO old_r FROM public.lawyer_time_reservations
     WHERE appointment_id=a.id ORDER BY ts_crt DESC LIMIT 1 FOR UPDATE;
    IF old_r.id IS NOT NULL THEN
      UPDATE public.lawyer_time_reservations SET status='released',ts_upd=now() WHERE id=old_r.id;
    END IF;
    v_gap:=GREATEST(15,COALESCE((public.appt_booking_config()->>'gap_mins')::integer,60));
    BEGIN
      INSERT INTO public.lawyer_time_reservations(lawyer_uid,user_uid,consultation_intent_id,
       slot_start,slot_end,status,hold_expires_at,appointment_id,idempotency_key)
      VALUES(c.lawyer_uid,a.req_uid,old_r.consultation_intent_id,v_target,
       v_target+make_interval(mins=>v_gap),'confirmed',now(),a.id,p_idempotency_key)
      RETURNING id INTO v_new_r;
    EXCEPTION WHEN exclusion_violation OR unique_violation THEN
      RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
    END;
    UPDATE public.appointments SET dt=v_target,dt_end=v_target+make_interval(mins=>v_gap),
      cnl_by=NULL,cnl_rsn=NULL,rmnd_24=0,rmnd_2=0,rmnd_qtr=0,rmnd_end=0 WHERE id=a.id;
    UPDATE public.legal_consultations SET requested_slot=v_target,ts_upd=now() WHERE id=c.id;
    v_neog := v_neog || jsonb_build_object('round', v_rounds+1, 'by', v_actor_label,
      'action','accept','proposed',v_target,'at',now());
    UPDATE public.appointments SET neog=v_neog WHERE id=a.id;
    v_dt_text := to_char(v_target AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI');
    IF v_other IS NOT NULL THEN
      INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
      VALUES(v_other,1,'✅ تم تغيير موعد جلستك',
        'وافق '||v_other_label||' — الموعد الجديد: '||v_dt_text||'.',
        a.id::text,'legal_appointment_update',0,0,now());
      PERFORM public.send_push_notification(v_other,'✅ تم تغيير موعد جلستك',
        'الموعد الجديد: '||v_dt_text,
        jsonb_build_object('act','legal_appointment_update','ref_id',a.id::text));
    END IF;
    RETURN jsonb_build_object('success',true,'appointment_id',a.id,'accepted',true,'new_slot',v_target);

  ELSIF p_proposed_dt IS NOT NULL THEN
    -- اقتراح بديل (تراشق)
    IF v_rounds >= 5 THEN RAISE EXCEPTION 'NEGOTIATION_ROUNDS_EXCEEDED'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(c.lawyer_uid,30) s
      WHERE abs(extract(epoch FROM(s.slot_dt-p_proposed_dt)))<1) THEN
      RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
    END IF;
    v_neog := v_neog || jsonb_build_object('round', v_rounds+1, 'by', v_actor_label,
      'action','counter','proposed',p_proposed_dt,'at',now());
    UPDATE public.appointments SET neog=v_neog WHERE id=a.id;
    v_dt_text := to_char(p_proposed_dt AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI');
    IF v_other IS NOT NULL THEN
      INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
      VALUES(v_other,1,'🔄 اقتراح وقت بديل للجلسة',
        v_other_label||' اقترح وقتاً بديلاً: '||v_dt_text||' — اقبل أو اقترح وقتاً آخر.',
        a.id::text,'legal_appointment_update',0,0,now());
      PERFORM public.send_push_notification(v_other,'🔄 اقتراح وقت بديل للجلسة',
        v_other_label||' اقترح: '||v_dt_text,
        jsonb_build_object('act','legal_appointment_update','ref_id',a.id::text));
    END IF;
    RETURN jsonb_build_object('success',true,'appointment_id',a.id,'countered',true);

  ELSE
    -- رفض — يبقى الموعد الحالي كما هو
    v_neog := v_neog || jsonb_build_object('round', v_rounds+1, 'by', v_actor_label,
      'action','reject','reason',COALESCE(p_reason,''),'at',now());
    UPDATE public.appointments SET neog=v_neog WHERE id=a.id;
    IF v_other IS NOT NULL THEN
      INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
      VALUES(v_other,1,'❌ رُفض طلب تغيير الموعد',
        v_other_label||' رفض تغيير موعد الجلسة'
        ||CASE WHEN COALESCE(p_reason,'')<>'' THEN '. السبب: '||p_reason ELSE '' END
        ||' — موعدك الحالي باقٍ كما هو.',
        a.id::text,'legal_appointment_update',0,0,now());
      PERFORM public.send_push_notification(v_other,'❌ رُفض طلب تغيير الموعد',
        'موعدك الحالي باقٍ كما هو.',
        jsonb_build_object('act','legal_appointment_update','ref_id',a.id::text));
    END IF;
    RETURN jsonb_build_object('success',true,'appointment_id',a.id,'rejected',true);
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.respond_legal_appointment_change_v2(uuid,uuid,boolean,text,timestamptz,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.respond_legal_appointment_change_v2(uuid,uuid,boolean,text,timestamptz,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.respond_legal_appointment_change_v2(uuid,uuid,boolean,text,timestamptz,uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- ③ get_lawyer_appointments + عمود neog (لقراءة التراشق بلوحة المحامي)
--    ⚠️ DROP أولاً (تغيير توقيع — درس 42P13)
-- ──────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_lawyer_appointments(uuid);

CREATE FUNCTION public.get_lawyer_appointments(p_lawyer_uid uuid)
RETURNS TABLE(
  appt_id uuid,
  client_name text,
  dt timestamp with time zone,
  sts integer,
  notes text,
  cnl_by uuid,
  cnl_rsn text,
  consultation_id uuid,
  neog jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT
    a.id AS appt_id,
    COALESCE(u.nm, '') AS client_name,
    a.dt,
    a.sts AS sts,
    COALESCE(a.executor_notes, '') AS notes,
    a.cnl_by,
    a.cnl_rsn,
    a.consultation_id,
    COALESCE(a.neog, '[]'::jsonb) AS neog
  FROM public.appointments a
  JOIN public.users u ON u.id = a.req_uid
  WHERE a.bkr_id = p_lawyer_uid
  ORDER BY a.dt DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_lawyer_appointments(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_lawyer_appointments(uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_lawyer_appointments(uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج
-- ──────────────────────────────────────────────────────────────────────
SELECT
  (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
    AND proname='propose_legal_appointment_change_v2')) AS propose_fn,
  (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace
    AND proname='respond_legal_appointment_change_v2')) AS respond_fn,
  (SELECT pg_get_functiondef(oid) LIKE '%neog jsonb%'
    FROM pg_proc WHERE pronamespace='public'::regnamespace
    AND proname='get_lawyer_appointments' LIMIT 1) AS lawyer_appts_with_neog;
