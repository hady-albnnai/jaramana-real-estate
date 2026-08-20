-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — الجلسة الحضورية: فلو الاعتذار الموحد + عنوان المكتب + rebook
--
-- ① rebook_legal_appointment_v2: بعد اعتذار المحامي (موعد ملغي sts=3)
--    يختار العميل موعداً جديداً من أوقات محامي الاستشارة الحالي (نفسه أو
--    الجديد) بنفس الدفعة — الموعد يُعاد تثبيته مؤكداً فوراً.
-- ② approve_payment_final_v3: إزالة إشعار المستخدم المكرر (التريغر هو
--    المُشعِر الوحيد له الآن) + إثراء إشعار المحامي بمكان الجلسة.
-- ③ trg_consultation_payment_v2: إشعار التثبيت غني بالتاريخ/العنوان/تنبيه
--    الساعة (يصل مع push فوري).
-- ④ get_lawyer_appointments: أعمدة cnl_by/cnl_rsn/consultation_id لبطاقات
--    «تم الاعتذار — بانتظار الإجراء التالي».
-- كله idempotent (CREATE OR REPLACE + DROP ضمن التعريفات).
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.rebook_legal_appointment_v2(
 p_user_uid uuid,p_appointment_id uuid,p_slot timestamptz,p_idempotency_key uuid
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE a public.appointments%ROWTYPE; c public.legal_consultations%ROWTYPE;
  old_r public.lawyer_time_reservations%ROWTYPE; new_r uuid; v_gap integer; v_addr text;
BEGIN
 IF p_slot IS NULL OR p_idempotency_key IS NULL THEN RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS'; END IF;
 SELECT * INTO a FROM public.appointments WHERE id=p_appointment_id AND kind='legal' FOR UPDATE;
 IF a.id IS NULL THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
 IF a.req_uid<>p_user_uid THEN RAISE EXCEPTION 'NOT_YOUR_APPOINTMENT'; END IF;
 -- إعادة الاختيار متاحة فقط للموعد الملغي من المحامي (busy/other) —
 -- إلغاء المستخدم النهائي بلا استرداد لا يُحيى
 IF a.sts<>3 THEN RAISE EXCEPTION 'APPOINTMENT_NOT_REBOOKABLE'; END IF;
 IF a.cnl_by IS NOT NULL AND a.cnl_by=a.req_uid THEN RAISE EXCEPTION 'APPOINTMENT_CANCELLED_NO_REFUND'; END IF;
 SELECT * INTO c FROM public.legal_consultations WHERE id=a.consultation_id AND i_del=0 FOR UPDATE;
 IF c.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
 IF c.user_uid<>p_user_uid THEN RAISE EXCEPTION 'NOT_OWNER'; END IF;
 IF c.lawyer_uid IS NULL THEN RAISE EXCEPTION 'NO_ASSIGNED_LAWYER'; END IF;
 -- الموعد الجديد من أوقات محامي الاستشارة الحالي (نفسه بعد busy، أو الجديد بعد other)
 IF NOT EXISTS(SELECT 1 FROM public.get_lawyer_free_slots(c.lawyer_uid,30) s
   WHERE abs(extract(epoch FROM(s.slot_dt-p_slot)))<1) THEN RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE'; END IF;
 SELECT * INTO old_r FROM public.lawyer_time_reservations WHERE appointment_id=a.id ORDER BY ts_crt DESC LIMIT 1 FOR UPDATE;
 IF old_r.id IS NULL THEN RAISE EXCEPTION 'RESERVATION_NOT_FOUND'; END IF;
 UPDATE public.lawyer_time_reservations SET status='released',ts_upd=now() WHERE id=old_r.id;
 v_gap:=GREATEST(15,COALESCE((public.appt_booking_config()->>'gap_mins')::integer,60));
 BEGIN
  INSERT INTO public.lawyer_time_reservations(lawyer_uid,user_uid,consultation_intent_id,
   slot_start,slot_end,status,hold_expires_at,appointment_id,idempotency_key)
  VALUES(c.lawyer_uid,p_user_uid,old_r.consultation_intent_id,p_slot,p_slot+make_interval(mins=>v_gap),
   'confirmed',now(),a.id,p_idempotency_key) RETURNING id INTO new_r;
 EXCEPTION WHEN exclusion_violation OR unique_violation THEN
  RAISE EXCEPTION 'SLOT_NO_LONGER_AVAILABLE';
 END;
 UPDATE public.appointments SET bkr_id=c.lawyer_uid,dt=p_slot,dt_end=p_slot+make_interval(mins=>v_gap),
  sts=1,cnl_by=NULL,cnl_rsn=NULL,rmnd_24=0,rmnd_2=0,rmnd_qtr=0,rmnd_end=0 WHERE id=a.id;
 UPDATE public.legal_consultations SET status=1,requested_slot=p_slot,ts_upd=now() WHERE id=c.id;
 SELECT value->'legalPrice'->>'officeAddress' INTO v_addr FROM public.app_config WHERE key='main';
 INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
 SELECT x.uid,1,'📅 تم تثبيت موعدك الجديد',
  'الموعد الجديد: '||to_char(p_slot AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI')||
  CASE WHEN COALESCE(v_addr,'')<>'' THEN ' | 📍 مكان الجلسة: '||v_addr ELSE '' END||
  ' | ☎️ الرجاء الاتصال بالمكتب قبل ساعة من الموعد للتأكيد.',
  a.id::text,'legal_appointment_update',0,0,now()
 FROM (VALUES(a.req_uid),(c.lawyer_uid)) x(uid) WHERE x.uid IS NOT NULL;
 -- push فوري للمحامي (العقد الجديد من وقته) — المستخدم داخل التطبيق
 PERFORM public.send_push_notification(c.lawyer_uid,'📅 موعد جلسة جديد من العميل',
  to_char(p_slot AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI'),
  jsonb_build_object('act','legal_appointment_update','ref_id',a.id::text));
 PERFORM public.update_lawyer_active_tasks(c.lawyer_uid);
 RETURN jsonb_build_object('success',true,'appointment_id',a.id,'lawyer_uid',c.lawyer_uid,'status',1);
END;
$function$;

REVOKE ALL ON FUNCTION public.rebook_legal_appointment_v2(uuid,uuid,timestamptz,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rebook_legal_appointment_v2(uuid,uuid,timestamptz,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.rebook_legal_appointment_v2(uuid,uuid,timestamptz,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.approve_payment_final_v3(p_payment_id uuid,p_admin_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE
  v_role integer; v_payment public.payments%ROWTYPE; v_intent public.consultation_intents%ROWTYPE;
  v_res public.lawyer_time_reservations%ROWTYPE; v_parent public.legal_consultations%ROWTYPE;
  v_consult public.legal_consultations%ROWTYPE; v_lawyer uuid; v_alias text; v_appt uuid;
  v_duration integer; v_ordinal integer; v_cfg jsonb; v_addr text;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid()<>p_admin_id THEN RAISE EXCEPTION 'AUTH_UID_MISMATCH'; END IF;
  SELECT role INTO v_role FROM public.users WHERE id=p_admin_id AND sts=0 AND i_del=0;
  IF v_role IS NULL OR v_role<5 THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT * INTO v_payment FROM public.payments WHERE id=p_payment_id FOR UPDATE;
  IF v_payment.id IS NULL THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;

  -- كل الأنواع القديمة والمسار القانوني V1 تبقى عبر الدالة المستقرة السابقة.
  IF v_payment.consultation_intent_id IS NULL THEN
    RETURN public.approve_payment_final_v2(p_payment_id,p_admin_id);
  END IF;

  SELECT * INTO v_intent FROM public.consultation_intents
   WHERE id=v_payment.consultation_intent_id FOR UPDATE;
  IF v_intent.id IS NULL OR v_intent.user_uid<>v_payment.uid THEN RAISE EXCEPTION 'CONSULTATION_INTENT_NOT_FOUND'; END IF;
  IF v_payment.sts=1 AND v_intent.status='materialized' THEN
    RETURN jsonb_build_object('success',true,'type','consultation_v2','flow',v_intent.flow,
      'consultation_id',v_intent.materialized_consultation_id,'duplicate',true);
  END IF;
  IF v_payment.sts<>0 OR v_intent.status<>'payment_pending' THEN RAISE EXCEPTION 'PAYMENT_NOT_PENDING'; END IF;

  v_lawyer:=v_intent.lawyer_uid;
  IF NOT EXISTS(SELECT 1 FROM public.lawyer_profiles lp JOIN public.users u ON u.id=lp.uid
    WHERE lp.uid=v_lawyer AND lp.is_active=true AND u.role=7 AND u.sts=0 AND u.i_del=0) THEN
    IF v_intent.flow='phone_new' THEN v_lawyer:=public.pick_next_lawyer('{}'::uuid[],false);
    ELSE RAISE EXCEPTION 'ASSIGNED_LAWYER_UNAVAILABLE'; END IF;
  END IF;
  IF v_lawyer IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_LAWYERS'; END IF;
  v_alias:=public.lawyer_alias_for(v_lawyer);
  -- 📍 عنوان المكتب (لإثراء إشعار المحامي) — قد يكون فارغاً
  SELECT value->'legalPrice'->>'officeAddress' INTO v_addr FROM public.app_config WHERE key='main';

  IF v_intent.flow='phone_new' THEN
    INSERT INTO public.legal_consultations(user_uid,lawyer_uid,service_type,subject,price,status,
      attachments,lawyer_alias,payment_id,payment_status,ts_crt,ts_upd)
    VALUES(v_intent.user_uid,v_lawyer,0,v_intent.subject,v_intent.quoted_amount,0,
      v_intent.attachments,v_alias,v_payment.id,1,now(),now()) RETURNING * INTO v_consult;

    INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
    VALUES(v_lawyer,1,'⚖️ استشارة هاتفية جديدة',
      'وصلت استشارة مدفوعة جديدة — راجع الموضوع والمرفقات.',v_consult.id::text,
      'legal_consultation_new',0,0,now());
    INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
    VALUES('new-consult:'||v_consult.id,'legal_consultation_new',v_lawyer,v_consult.id,
      jsonb_build_object('consultation_id',v_consult.id)) ON CONFLICT(event_key) DO NOTHING;

  ELSIF v_intent.flow='phone_renew' THEN
    SELECT * INTO v_parent FROM public.legal_consultations
     WHERE id=v_intent.parent_consultation_id AND user_uid=v_intent.user_uid AND i_del=0 FOR UPDATE;
    IF v_parent.id IS NULL OR v_parent.lawyer_uid<>v_lawyer THEN RAISE EXCEPTION 'CONSULTATION_OWNER_MISMATCH'; END IF;
    SELECT value INTO v_cfg FROM public.app_config WHERE key='main';
    v_duration:=(v_cfg->'legalPrice'->>'durationMins')::integer;
    IF v_duration IS NULL OR v_duration<1 THEN RAISE EXCEPTION 'INVALID_DURATION_MINS'; END IF;
    SELECT COALESCE(MAX(ordinal),0)+1 INTO v_ordinal FROM public.consultation_chat_sessions
     WHERE consultation_id=v_parent.id;
    INSERT INTO public.consultation_chat_sessions(consultation_id,ordinal,kind,payment_id,duration_minutes,status)
    VALUES(v_parent.id,v_ordinal,'renewal',v_payment.id,v_duration,'ready');
    UPDATE public.legal_consultations SET renew_count=COALESCE(renew_count,0)+1,ts_upd=now()
     WHERE id=v_parent.id RETURNING * INTO v_consult;
    INSERT INTO public.consultation_chats(consultation_id,sender_id,message_type,content)
    VALUES(v_parent.id,v_intent.user_uid,'system','تم اعتماد التجديد — '||v_duration::text||' دقيقة جاهزة عند استئناف المحامي.');
    INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
    VALUES(v_lawyer,1,'✅ تم اعتماد تجديد الاستشارة',
      'لدى العميل جلسة مدفوعة جاهزة. افتح المحادثة واضغط «استئناف».',v_parent.id::text,
      'legal_renewal_paid_ready',0,0,now());
    INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
    VALUES('renew-ready:'||v_payment.id,'legal_renewal_paid_ready',v_lawyer,v_parent.id,
      jsonb_build_object('consultation_id',v_parent.id,'duration_minutes',v_duration)) ON CONFLICT(event_key) DO NOTHING;

  ELSE
    SELECT * INTO v_res FROM public.lawyer_time_reservations
     WHERE id=v_intent.reservation_id FOR UPDATE;
    IF v_res.id IS NULL OR v_res.status<>'held' OR v_res.hold_expires_at<=now() THEN
      UPDATE public.consultation_intents SET status='payment_needs_slot',ts_upd=now() WHERE id=v_intent.id;
      RAISE EXCEPTION 'SLOT_HOLD_EXPIRED';
    END IF;
    IF v_res.lawyer_uid<>v_lawyer OR v_res.user_uid<>v_intent.user_uid THEN RAISE EXCEPTION 'RESERVATION_MISMATCH'; END IF;
    IF v_intent.flow='onsite_convert' THEN
      SELECT * INTO v_parent FROM public.legal_consultations
       WHERE id=v_intent.parent_consultation_id AND user_uid=v_intent.user_uid AND lawyer_uid=v_lawyer AND i_del=0 FOR UPDATE;
      IF v_parent.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
    END IF;

    INSERT INTO public.legal_consultations(user_uid,lawyer_uid,service_type,subject,price,status,
      attachments,lawyer_alias,payment_id,payment_status,parent_consultation_id,requested_slot,ts_crt,ts_upd)
    VALUES(v_intent.user_uid,v_lawyer,1,v_intent.subject,
      v_intent.quoted_amount+v_intent.base_discount,1,v_intent.attachments,v_alias,v_payment.id,1,
      v_intent.parent_consultation_id,v_res.slot_start,now(),now()) RETURNING * INTO v_consult;

    INSERT INTO public.appointments(kind,consultation_id,bkr_id,req_uid,dt,dt_end,sts,ts_crt,
      admin_nt,executor_notes)
    VALUES('legal',v_consult.id,v_lawyer,v_intent.user_uid,v_res.slot_start,v_res.slot_end,1,now(),
      '⚖️ جلسة قانونية مؤكدة','جلسة قانونية: '||left(v_intent.subject,180)) RETURNING id INTO v_appt;
    UPDATE public.legal_consultations SET appointment_id=v_appt WHERE id=v_consult.id;
    UPDATE public.lawyer_time_reservations SET status='confirmed',appointment_id=v_appt,ts_upd=now()
     WHERE id=v_res.id;
    IF v_parent.id IS NOT NULL THEN
      UPDATE public.legal_consultations SET converted_to_onsite=true,
        onsite_discount=v_intent.base_discount,ts_upd=now() WHERE id=v_parent.id;
    END IF;
    -- 🩹 2026-08-20: إزالة إشعار المستخدم المكرر — trg_consultation_payment_v2
    -- يُشعر المستخدم وحده (بpush فوري ونص غني بالتاريخ والعنوان). هنا يبقى
    -- إشعار المحامي فقط مع إثرائه بمكان الجلسة.
    INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
    VALUES(v_lawyer,1,'🏢 جلسة حضورية مدفوعة مؤكدة',
      'تم تثبيت جلسة قانونية في وقتك المنشور'||
      CASE WHEN COALESCE(v_addr,'')<>'' THEN ' — 📍 مكان الجلسة: '||v_addr ELSE '' END||'.',
      v_appt::text,'legal_onsite_confirmed',0,0,now());
  END IF;

  UPDATE public.consultation_intents SET status='materialized',lawyer_uid=v_lawyer,
    materialized_consultation_id=v_consult.id,ts_upd=now() WHERE id=v_intent.id;
  UPDATE public.payments SET sts=1,appr_by=p_admin_id WHERE id=v_payment.id AND sts=0;
  IF NOT FOUND THEN RAISE EXCEPTION 'PAYMENT_CONCURRENTLY_PROCESSED'; END IF;
  PERFORM public.update_lawyer_active_tasks(v_lawyer);
  RETURN jsonb_build_object('success',true,'type','consultation_v2','flow',v_intent.flow,
    'consultation_id',v_consult.id,'appointment_id',v_appt,'payment_id',v_payment.id);
END;
$function$;
REVOKE ALL ON FUNCTION public.approve_payment_final_v3(uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment_final_v3(uuid,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final_v3(uuid,uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.trg_consultation_payment_v2()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_intent public.consultation_intents%ROWTYPE; v_title text; v_body text; v_act text;
  v_ref text; v_slot timestamptz; v_addr text;
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
      -- 🏢 2026-08-20: إشعار التثبيت الوحيد للمستخدم (أُزيل المكرر من v3) —
      -- غني بالتاريخ والمكان وتنبيه الساعة.
      v_title:='✅ تم تثبيت الجلسة الحضورية';
      SELECT slot_start INTO v_slot FROM public.lawyer_time_reservations WHERE id=v_intent.reservation_id;
      SELECT value->'legalPrice'->>'officeAddress' INTO v_addr FROM public.app_config WHERE key='main';
      v_body:='تم اعتماد الدفع وتأكيد موعدك';
      IF v_slot IS NOT NULL THEN
        v_body:=v_body||' — '||to_char(v_slot AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI');
      END IF;
      IF COALESCE(v_addr,'')<>'' THEN
        v_body:=v_body||' | 📍 مكان الجلسة: '||v_addr;
      END IF;
      v_body:=v_body||' | ☎️ الرجاء الاتصال بالمكتب قبل ساعة من الموعد للتأكيد.';
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

-- ──────────────────────────────────────────────────────────────────────
-- ⑤ get_lawyer_appointments — أعمدة بطاقات «تم الاعتذار»
-- ⚠️ درس drift (2026-08-20): النسخة الحية ع توقيع قديم (sts وبدون client_phone)
-- يختلف عن 2026_08_05_fix_lawyer_appointments.sql بالريبو ⇒ CREATE OR REPLACE
-- فشل حياً بـ 42P13 (تغيير نوع الإرجاع). الحل الدستوري: DROP أولاً ثم إنشاء
-- بتوقيع يطابق **ما تقرأه الواجهة فعلياً** (sts — لا appt_sts، وبلا
-- client_phone إطلاقاً: حُذف عمداً لحماية خصوصية العميل 2026-08-14).
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
  consultation_id uuid
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
    a.consultation_id
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
-- تحقق نهائي مدمج (تظهر نتائجه في مخرجات النشر):
--   ① rebook_defined = true · ② نص التثبيت الغني مفعّل · ③ أعمدة الاعتذار مفعّلة
-- ──────────────────────────────────────────────────────────────────────
SELECT
  EXISTS(SELECT 1 FROM pg_proc WHERE proname='rebook_legal_appointment_v2') AS rebook_defined,
  pg_get_functiondef('public.trg_consultation_payment_v2()'::regprocedure) LIKE '%الاتصال بالمكتب%' AS rich_body_patched,
  pg_get_functiondef('public.get_lawyer_appointments(uuid)'::regprocedure) LIKE '%cnl_rsn%' AS appt_columns_patched;
