-- ═══════════════════════════════════════════════════════════════════════
-- إصلاحات سيرفر — 2026-07-11
-- 1. منع تكرار الطلبات (نفس المستخدم + نفس الهاتف + نفس النوع خلال 5 دقائق)
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_request_internal(
  p_user_uid UUID,
  p_request JSONB
)
RETURNS SETOF public.requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user public.users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_name TEXT;
  v_phone TEXT;
  v_notes TEXT;
  v_price NUMERIC;
  v_days INT;
  v_is_duplicate BOOLEAN;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM public.users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  v_name := public.app_assert_text_len(p_request->>'cl_nm', 'client_name', 2, 60);
  v_phone := public.app_assert_phone(p_request->>'cl_ph');
  v_notes := public.app_clean_text(p_request->>'notes', 1000);
  v_price := COALESCE((p_request->>'prc')::NUMERIC, 0);

  IF v_price < 0 OR v_price > 999999999999 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  -- ✅ فحص التكرار: نفس المستخدم + نفس الهاتف + نفس النوع خلال 5 دقائق
  SELECT EXISTS (
    SELECT 1 FROM public.requests
    WHERE usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1)
      AND cl_ph = v_phone
      AND typ = COALESCE((p_request->>'typ')::INT, 0)
      AND elm = COALESCE((p_request->>'elm')::INT, 0)
      AND ts_crt > NOW() - INTERVAL '5 minutes'
  ) INTO v_is_duplicate;

  IF v_is_duplicate THEN
    RAISE EXCEPTION 'DUPLICATE_REQUEST';
  END IF;

  IF COALESCE(v_user.role, 0) < 4 THEN
    SELECT value INTO v_config FROM public.app_config WHERE key = 'main';
    v_limit := CASE WHEN COALESCE(v_user.role, 0) = 1
      THEN COALESCE((v_config->'qta'->'b'->>'r')::INT, 5)
      ELSE COALESCE((v_config->'qta'->'u'->>'r')::INT, 3)
    END;

    SELECT COUNT(*) INTO v_used
    FROM public.requests
    WHERE usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1);

    IF COALESCE(v_used, 0) >= COALESCE(v_limit, 3) THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  v_days := public.request_lifecycle_days('d', 30);

  RETURN QUERY
  INSERT INTO public.requests (
    typ, elm, cl_nm, cl_ph, prc, cur, notes, specs,
    usr_id, sts, matches, i_del, ts_crt, ts_end, rmnd_ren,
    closed_reason, closed_note
  ) VALUES (
    COALESCE((p_request->>'typ')::INT, 0),
    COALESCE((p_request->>'elm')::INT, 0),
    v_name,
    v_phone,
    v_price,
    COALESCE((p_request->>'cur')::INT, 0),
    v_notes,
    COALESCE(p_request->>'specs', '{}'::jsonb),
    p_user_uid,
    0,
    COALESCE(p_request->>'matches', '{}'::jsonb),
    0,
    NOW(),
    NOW() + (v_days || ' days')::INTERVAL,
    0,
    '',
    ''
  ) RETURNING *;
END;
$$;
