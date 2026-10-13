-- 2026-08-16 — قبول الهاتفية وإنشاء الجلسة الأساسية في transaction واحدة.
CREATE OR REPLACE FUNCTION public.accept_phone_consultation_v2(
  p_actor_uid uuid,p_consultation_id uuid,p_notes text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_cons public.legal_consultations%ROWTYPE; v_role integer; v_session jsonb;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id=p_actor_uid AND sts=0 AND i_del=0;
  SELECT * INTO v_cons FROM public.legal_consultations WHERE id=p_consultation_id AND i_del=0 FOR UPDATE;
  IF v_cons.id IS NULL THEN RAISE EXCEPTION 'CONSULTATION_NOT_FOUND'; END IF;
  IF v_cons.service_type<>0 OR v_cons.status<>0 THEN RAISE EXCEPTION 'INVALID_STATUS_TRANSITION'; END IF;
  IF NOT ((v_role=7 AND v_cons.lawyer_uid=p_actor_uid) OR v_role IN (5,6)) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;
  UPDATE public.legal_consultations SET status=1,notes=COALESCE(NULLIF(trim(p_notes),''),notes),ts_upd=now()
   WHERE id=v_cons.id;
  v_session:=public.ensure_initial_chat_session_v2(v_cons.id);
  INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
  VALUES(v_cons.user_uid,1,'✅ قبل المحامي الاستشارة',
    'قُبلت استشارتك. سيصلك إشعار جديد عندما يصبح المحامي جاهزاً لبدء المحادثة.',
    v_cons.id::text,'legal_consultation_update',0,0,now());
  RETURN jsonb_build_object('success',true,'consultation_id',v_cons.id,'status',1,
    'session_id',v_session->>'session_id');
END;
$function$;
REVOKE ALL ON FUNCTION public.accept_phone_consultation_v2(uuid,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.accept_phone_consultation_v2(uuid,uuid,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.accept_phone_consultation_v2(uuid,uuid,text) TO service_role;
