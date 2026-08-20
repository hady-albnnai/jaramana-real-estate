-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — م7 (قرار المالك): المحامي يشارك بتخفيض التحويل للحضوري
--
-- الاكتشاف الحي (عينات lawyer_earnings): عند تحويل هاتفية (1000) إلى
-- حضورية (2000 — يدفع العميل الفرق 1000) كان المحامي يبقي حصة الهاتفية
-- (500) + حصة الحضورية (1000) = 1500 من أصل 2000 مقبوض (75%).
-- قرار المالك: المحامي يشارك بالتخفيض — حصة الهاتفية المنجزة تنعكس
-- عند التحويل، فيصير صافي حصته 50% من إجمالي المقبوض.
-- وكذلك: عند عكس دفعة التحويل تُستعاد حصة الهاتفية المعكوسة.
-- ⚠️ اسم الملف zz يجعله يُطبَّق بعد كل ملفات 08_20 أبجدياً — نسخته
--    من v3 (المبنية على z7days بشكلي الثغرة 2+4) هي النهائية.
-- تصحيح البيانات القائمة: حصص هواتف محوَّلة (converted_to_onsite مع ابن
-- حضوري مؤكد) تنعكس الآن.
-- ══════════════════════════════════════════════════════════════════

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
  staff RECORD; -- حلقة إشعار الإدارة (لا يُنشأ ضمنياً بأمان — نمط التريغر الحي)
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
    IF v_intent.flow='phone_new' THEN
      v_lawyer:=public.pick_next_lawyer('{}'::uuid[],false);
    ELSIF v_intent.flow='phone_renew' THEN
      -- 🔴 ثغرة 2 (2026-08-20): كان RAISE خام يُفشل الاعتماد صامتاً وتعلق
      -- الدفعة sts=0 بلا تفسير. الآن: رد منظم + إشعار فوري للإدارة بالخطوتين
      -- الممكنتين (تفعيل المحامي ثم إعادة الاعتماد، أو عكس الدفعة).
      -- الدفعة تبقى معلّقة كما كانت — لا تغيير سلوك آخر.
      FOR staff IN
        SELECT id FROM public.users
        WHERE role IN (5,6) AND i_del=0 AND sts=0
      LOOP
        INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
        VALUES(staff.id,1,'🔄 تجديد معلّق — المحامي غير نشط',
          'دفعة تجديد بانتظار الاعتماد والمحامي المسؤول غير نشط. فعّل المحامي ثم أعد الاعتماد — أو اعكس الدفعة.',
          v_payment.id::text,'payment_review',0,0,now());
        PERFORM public.send_push_notification(staff.id,'🔄 تجديد معلّق — المحامي غير نشط',
          'فعّل المحامي ثم أعد الاعتماد — أو اعكس الدفعة.',
          jsonb_build_object('act','payment_review','ref_id',v_payment.id::text));
      END LOOP;
      RETURN jsonb_build_object('success',false,'type','consultation_v2','flow',v_intent.flow,
        'error','LAWYER_INACTIVE_FOR_RENEWAL','payment_id',v_payment.id);
    ELSE
      RAISE EXCEPTION 'ASSIGNED_LAWYER_UNAVAILABLE';
    END IF;
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

    -- 🔒 ثغرة 4 (2026-08-20): إعادة فحص الـ7 أيام لحظة الاعتماد — كان الفحص
    -- وقت الدفع فقط (prepare)، وتأخير الإدارة كان يخلق جلسة تجديد لمحادثة
    -- منتهية ورسائلها ترفض لاحقاً. نفس الشرط الحرفي لفحص الدفع.
    IF v_parent.chat_started_at IS NULL OR now()>v_parent.chat_started_at+interval '7 days' THEN
      FOR staff IN
        SELECT id FROM public.users
        WHERE role IN (5,6) AND i_del=0 AND sts=0
      LOOP
        INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
        VALUES(staff.id,1,'🔄 تجديد منتهي الصلاحية',
          'دفعة تجديد لمحادثة تجاوزت 7 أيام — اعكس الدفعة لإعادة المبلغ أو وجّه العميل لاستشارة جديدة.',
          v_payment.id::text,'payment_review',0,0,now());
        PERFORM public.send_push_notification(staff.id,'🔄 تجديد منتهي الصلاحية',
          'اعكس الدفعة أو وجّه العميل لاستشارة جديدة.',
          jsonb_build_object('act','payment_review','ref_id',v_payment.id::text));
      END LOOP;
      RETURN jsonb_build_object('success',false,'type','consultation_v2','flow',v_intent.flow,
        'error','CHAT_EXPIRED_7DAYS','payment_id',v_payment.id);
    END IF;
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
      -- 🔒 2026-08-20 (قرار المالك): المحامي يشارك بتخفيض التحويل —
      -- حصة الهاتفية المنجزة تنعكس فيكون صافي حصته 50% من إجمالي المقبوض
      UPDATE public.lawyer_earnings SET status='reversed',reversed_at=now(),ts_upd=now()
       WHERE consultation_id=v_parent.id AND service_kind='phone_initial'
         AND status IN ('pending','earned');
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

CREATE OR REPLACE FUNCTION public.admin_reverse_payment_v2(
  p_admin_uid uuid,p_payment_id uuid,p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer; v_pay public.payments%ROWTYPE; v_intent public.consultation_intents%ROWTYPE;
  v_cons public.legal_consultations%ROWTYPE; v_session public.consultation_chat_sessions%ROWTYPE;
  v_appt public.appointments%ROWTYPE;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id=p_admin_uid AND sts=0 AND i_del=0;
  IF v_role<>6 THEN RAISE EXCEPTION 'ONLY_MANAGER_CAN_REVERSE'; END IF;
  IF length(trim(COALESCE(p_reason,'')))<3 THEN RAISE EXCEPTION 'REVERSAL_REASON_REQUIRED'; END IF;
  SELECT * INTO v_pay FROM public.payments WHERE id=p_payment_id FOR UPDATE;
  IF v_pay.id IS NULL THEN RAISE EXCEPTION 'PAYMENT_NOT_FOUND'; END IF;
  IF v_pay.consultation_intent_id IS NULL THEN
    RETURN public.admin_reverse_payment(p_admin_uid,p_payment_id,p_reason);
  END IF;
  IF v_pay.sts<>1 THEN RAISE EXCEPTION 'PAYMENT_NOT_APPROVED'; END IF;
  SELECT * INTO v_intent FROM public.consultation_intents WHERE id=v_pay.consultation_intent_id FOR UPDATE;
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=v_intent.materialized_consultation_id FOR UPDATE;

  IF v_intent.flow='phone_renew' THEN
    SELECT * INTO v_session FROM public.consultation_chat_sessions WHERE payment_id=v_pay.id FOR UPDATE;
    IF v_session.status<>'ready' THEN RAISE EXCEPTION 'CONSULTATION_SERVICE_ALREADY_CONSUMED'; END IF;
    UPDATE public.consultation_chat_sessions SET status='reversed',ts_upd=now() WHERE id=v_session.id;
    UPDATE public.legal_consultations SET renew_count=GREATEST(0,COALESCE(renew_count,0)-1),ts_upd=now()
     WHERE id=v_intent.parent_consultation_id;
  ELSIF v_intent.flow='phone_new' THEN
    IF EXISTS(SELECT 1 FROM public.consultation_chat_sessions WHERE consultation_id=v_cons.id AND status IN ('join_window','active','ended')) THEN
      RAISE EXCEPTION 'CONSULTATION_SERVICE_ALREADY_CONSUMED';
    END IF;
    UPDATE public.legal_consultations SET status=3,notes='عكس دفعة: '||trim(p_reason),ts_upd=now() WHERE id=v_cons.id;
  ELSE
    SELECT * INTO v_appt FROM public.appointments WHERE consultation_id=v_cons.id FOR UPDATE;
    IF v_appt.sts=2 OR v_appt.dt<=now() THEN RAISE EXCEPTION 'CONSULTATION_SERVICE_ALREADY_CONSUMED'; END IF;
    UPDATE public.appointments SET sts=3,cnl_by=p_admin_uid,cnl_rsn='عكس دفعة: '||trim(p_reason) WHERE id=v_appt.id;
    UPDATE public.legal_consultations SET status=3,notes='عكس دفعة: '||trim(p_reason),ts_upd=now() WHERE id=v_cons.id;
    UPDATE public.lawyer_time_reservations SET status='cancelled',ts_upd=now()
     WHERE appointment_id=v_appt.id AND status='confirmed';
    IF v_intent.flow='onsite_convert' THEN
      UPDATE public.legal_consultations SET converted_to_onsite=false,onsite_discount=0,ts_upd=now()
       WHERE id=v_intent.parent_consultation_id;
      -- استعادة حصة الهاتفية المعكوسة عند التراجع عن التحويل
      UPDATE public.lawyer_earnings SET status='earned',reversed_at=NULL,ts_upd=now()
       WHERE consultation_id=v_intent.parent_consultation_id AND service_kind='phone_initial'
         AND status='reversed';
    END IF;
  END IF;

  UPDATE public.consultation_intents SET status='cancelled',failure_code='PAYMENT_REVERSED',ts_upd=now() WHERE id=v_intent.id;
  UPDATE public.payments SET sts=3,meta=meta||jsonb_build_object('reversed_by',p_admin_uid,
    'reversed_at',now(),'reversal_reason',trim(p_reason),'prev_sts',1) WHERE id=v_pay.id;
  PERFORM public.update_lawyer_active_tasks(v_intent.lawyer_uid);
  PERFORM public.log_admin_action(p_admin_uid,121,'عكس دفعة استشارة V2 — '||trim(p_reason),p_payment_id::text,'payments');
  RETURN jsonb_build_object('success',true,'payment_id',p_payment_id,'flow',v_intent.flow,'compensated',true);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_reverse_payment_v2(uuid,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_reverse_payment_v2(uuid,uuid,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reverse_payment_v2(uuid,uuid,text) TO service_role;


-- ──────────────────────────────────────────────────────────────────────
-- تصحيح البيانات القائمة: عكس حصص الهواتف المحوَّلة الحية
-- ──────────────────────────────────────────────────────────────────────
UPDATE public.lawyer_earnings e SET status='reversed',reversed_at=now(),ts_upd=now()
 WHERE e.service_kind='phone_initial' AND e.status IN ('pending','earned')
   AND EXISTS (
     SELECT 1 FROM public.legal_consultations p
     WHERE p.id=e.consultation_id AND p.converted_to_onsite=true
       AND EXISTS (
         SELECT 1 FROM public.legal_consultations c
         WHERE c.parent_consultation_id=p.id AND c.service_type=1
           AND c.i_del=0 AND c.status=1
       )
   );

-- استعادة الحصص المعكوسة لأبوين لم يعد لديهم تحويل حي
UPDATE public.lawyer_earnings e SET status='earned',reversed_at=NULL,ts_upd=now()
 WHERE e.service_kind='phone_initial' AND e.status='reversed'
   AND EXISTS (
     SELECT 1 FROM public.legal_consultations p
     WHERE p.id=e.consultation_id AND p.converted_to_onsite=false
   );


-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج:
--   convert_reverses_phone = true ⇒ الحصة الهاتفية تنعكس عند التحويل
--   reverse_restores_phone = true ⇒ تُستعاد عند عكس التحويل
--   active_converted_phones  = عدد هواتف محوَّلة حية بحصة معكوسة (يجب >0
--                              إذا وُجدت تحويلات حية لم تُصحَّح بعد)
-- ──────────────────────────────────────────────────────────────────────
SELECT
  pg_get_functiondef('public.approve_payment_final_v3(uuid,uuid)'::regprocedure)
    LIKE '%service_kind=%''phone_initial%' AS convert_reverses_phone,
  pg_get_functiondef('public.admin_reverse_payment_v2(uuid,uuid,text)'::regprocedure)
    LIKE '%reversed%' AS reverse_restores_phone,
  (SELECT count(*) FROM public.legal_consultations p
    WHERE p.converted_to_onsite=true AND EXISTS (
      SELECT 1 FROM public.legal_consultations c
      WHERE c.parent_consultation_id=p.id AND c.service_type=1 AND c.i_del=0 AND c.status=1
    )) AS active_converted_phones;
