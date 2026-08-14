-- ═══════════════════════════════════════════════════════════════════
-- 2026_08_14_consultation_credit_and_assign.sql
-- قرارات المالك بعد جولة E2E الكاملة:
--  ① الطلب المخالف = «الاستشارة تمت» (رأي قانوني = خدمة مكتملة) لا رفضاً.
--  ② «رصيد استشارة» يُمنح **يدوياً من الإدارة** — المبلغ يبقى بالخزينة
--     والعميل يطلب مجدداً بلا دفع (بدل استرداد نقدي).
--  ③ عودة محامٍ لـ«متاح» ⇒ التقاط تلقائي للطلبات اليتيمة (الأقدم أولاً).
-- ═══════════════════════════════════════════════════════════════════

-- ① رصيد الاستشارات (بديل الاسترداد النقدي)
CREATE TABLE IF NOT EXISTS public.consultation_credits (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uid     uuid NOT NULL,
  service_type int  NOT NULL DEFAULT 0,      -- 0 هاتفية · 1 حضورية
  amount       numeric NOT NULL DEFAULT 0,
  reason       text NOT NULL DEFAULT '',
  granted_by   uuid,
  consumed     boolean NOT NULL DEFAULT false,
  consumed_at  timestamptz,
  consultation_id uuid,                       -- الاستشارة التي استُهلك فيها
  source_consultation_id uuid,                -- الاستشارة التي تعذّرت
  ts_crt       timestamptz NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_cc_user_open
  ON public.consultation_credits (user_uid, service_type) WHERE consumed = false;

ALTER TABLE public.consultation_credits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.consultation_credits FROM anon, authenticated;

COMMENT ON TABLE public.consultation_credits IS
  'رصيد استشارة يمنحه الأدمن بدل الاسترداد النقدي — المبلغ يبقى بالخزينة';

-- ② الإدارة تمنح رصيداً
CREATE OR REPLACE FUNCTION public.admin_grant_consultation_credit(
  p_admin_uid uuid, p_user_uid uuid, p_service_type int,
  p_reason text, p_source_consultation uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT; v_price NUMERIC; v_cfg JSONB; v_id UUID;
BEGIN
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;
  IF p_service_type NOT IN (0, 1) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_SERVICE_TYPE');
  END IF;
  IF COALESCE(BTRIM(p_reason), '') = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'REASON_REQUIRED');
  END IF;

  SELECT value INTO v_cfg FROM app_config WHERE key = 'main';
  v_price := COALESCE(
    (v_cfg->'legalPrice'->>(CASE p_service_type WHEN 1 THEN 'onsite' ELSE 'phone' END))::NUMERIC,
    CASE p_service_type WHEN 1 THEN 2000 ELSE 500 END);

  INSERT INTO consultation_credits
    (user_uid, service_type, amount, reason, granted_by, source_consultation_id)
  VALUES (p_user_uid, p_service_type, v_price, LEFT(p_reason, 300), p_admin_uid, p_source_consultation)
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'credit_id', v_id,
                            'amount', v_price, 'service_type', p_service_type);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_grant_consultation_credit(uuid,uuid,int,text,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_grant_consultation_credit(uuid,uuid,int,text,uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_grant_consultation_credit(uuid,uuid,int,text,uuid) TO service_role;

-- ③ استهلاك الرصيد (يُستدعى داخل book_consultation بدل الدفع)
CREATE OR REPLACE FUNCTION public.consume_consultation_credit(
  p_user_uid uuid, p_service_type int, p_consultation_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_id UUID;
BEGIN
  SELECT id INTO v_id FROM consultation_credits
   WHERE user_uid = p_user_uid AND service_type = p_service_type AND consumed = false
   ORDER BY ts_crt ASC LIMIT 1 FOR UPDATE SKIP LOCKED;
  IF v_id IS NULL THEN RETURN false; END IF;
  UPDATE consultation_credits
     SET consumed = true, consumed_at = NOW(), consultation_id = p_consultation_id
   WHERE id = v_id;
  RETURN true;
END;
$function$;

REVOKE ALL ON FUNCTION public.consume_consultation_credit(uuid,int,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.consume_consultation_credit(uuid,int,uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_consultation_credit(uuid,int,uuid) TO service_role;

-- ④ التقاط الطلبات اليتيمة عند عودة محامٍ (الأقدم أولاً، ويستثني من رفضها)
CREATE OR REPLACE FUNCTION public.claim_orphan_consultations(p_lawyer_uid uuid)
RETURNS TABLE(consultation_id uuid, user_uid uuid, service_type int, subject text)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT; v_active BOOLEAN; v_alias TEXT;
BEGIN
  SELECT u.role, lp.is_active INTO v_role, v_active
    FROM users u JOIN lawyer_profiles lp ON lp.uid = u.id
   WHERE u.id = p_lawyer_uid AND u.i_del = 0 AND u.sts = 0;
  IF v_role IS DISTINCT FROM 7 OR v_active IS NOT TRUE THEN RETURN; END IF;

  v_alias := public.lawyer_alias_for(p_lawyer_uid);

  RETURN QUERY
  WITH picked AS (
    SELECT lc.id FROM legal_consultations lc
     WHERE lc.lawyer_uid IS NULL AND lc.status = 0 AND lc.i_del = 0
       AND NOT (p_lawyer_uid = ANY(COALESCE(lc.rejected_by, '{}')))
     ORDER BY lc.ts_crt ASC
     FOR UPDATE SKIP LOCKED
  )
  UPDATE legal_consultations lc
     SET lawyer_uid = p_lawyer_uid, lawyer_alias = v_alias, ts_upd = NOW()
    FROM picked
   WHERE lc.id = picked.id
  RETURNING lc.id, lc.user_uid, lc.service_type, lc.subject;

  PERFORM public.update_lawyer_active_tasks(p_lawyer_uid);
END;
$function$;

REVOKE ALL ON FUNCTION public.claim_orphan_consultations(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.claim_orphan_consultations(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_orphan_consultations(uuid) TO service_role;

-- ⑤ الإدارة تُسند استشارة يدوياً لمحامٍ محدد (بعد تواصلها الخارجي)
CREATE OR REPLACE FUNCTION public.admin_assign_consultation(
  p_admin_uid uuid, p_consultation_id uuid, p_lawyer_uid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_role INT; v_lrole INT; v_status INT; v_alias TEXT;
BEGIN
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;
  SELECT u.role INTO v_lrole FROM users u JOIN lawyer_profiles lp ON lp.uid = u.id
   WHERE u.id = p_lawyer_uid AND u.i_del = 0 AND u.sts = 0;
  IF v_lrole IS DISTINCT FROM 7 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_NOT_LAWYER');
  END IF;
  SELECT status INTO v_status FROM legal_consultations
   WHERE id = p_consultation_id AND i_del = 0;
  IF v_status IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_NOT_FOUND');
  END IF;
  IF v_status NOT IN (0, 5) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ONLY_PENDING_CAN_BE_ASSIGNED');
  END IF;

  v_alias := public.lawyer_alias_for(p_lawyer_uid);
  UPDATE legal_consultations
     SET lawyer_uid = p_lawyer_uid, lawyer_alias = v_alias, status = 0, ts_upd = NOW()
   WHERE id = p_consultation_id;

  PERFORM public.update_lawyer_active_tasks(p_lawyer_uid);
  RETURN jsonb_build_object('success', true, 'lawyer_alias', v_alias);
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_assign_consultation(uuid,uuid,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_assign_consultation(uuid,uuid,uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_assign_consultation(uuid,uuid,uuid) TO service_role;
