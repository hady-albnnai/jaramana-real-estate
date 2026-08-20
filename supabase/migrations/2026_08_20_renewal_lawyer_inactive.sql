-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — ثغرة 2/4: اعتماد تجديد المحادثة والمحامي غير نشط
--
-- المشكلة (من التحليل الكمي QUANTUM_FLOW_ANALYSIS_2026_08_19 §5):
-- دفع المستخدم تجديد محادثة، وقبل اعتماد الإدارة عطّل المحامي نفسه
-- (is_active=false) ⇒ v3 كانت ترمي RAISE 'ASSIGNED_LAWYER_UNAVAILABLE'
-- فيفشل الاعتماد بلا تفسير وتبقى الدفعة sts=0 معلّقة، والإدارة تضطر
-- لعكسها يدوياً بلا معرفة السبب.
--
-- الإصلاح: بمسار phone_renew (نفس المحامي إجباري — قرار معماري لا يُمس):
--   • رد jsonb منظم: success:false + error=LAWYER_INACTIVE_FOR_RENEWAL
--     (يصل لنص واضح بشاشة المدفوعات بدل الخطأ الخام)
--   • إشعار فوري (notification + push) للنائب/المدير: «فعّل المحامي ثم
--     أعد الاعتماد — أو اعكس الدفعة»
--   • الدفعة تبقى sts=0 معلّقة كما كانت (لا تغيير سلوك آخر)
-- الهاتفية الجديدة (phone_new) تبقى على تحويلها التلقائي لمحامٍ آخر.
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

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج — تظهر نتيجته في مخرجات النشر:
--   renewal_inactive_patched = true ⇒ الثغرة 2 مغلقة على السيرفر
-- ──────────────────────────────────────────────────────────────────────
SELECT pg_get_functiondef('public.approve_payment_final_v3(uuid,uuid)'::regprocedure)
  LIKE '%LAWYER_INACTIVE_FOR_RENEWAL%' AS renewal_inactive_patched;
