-- ══════════════════════════════════════════════════════════════════════
-- Migration: Fix secure purchase_offer_boost lifecycle
-- Date: 2026-06-28 (Updated 2026-06-30)
-- Purpose:
--   - Remove references to offers.ts_upd because offers has no ts_upd column.
--   - Keep boost cost server-calculated from app_config.main.spd.
--   - Keep the function callable by service_role only; app access stays through
--     the user-offers Edge Function.
--   - Write activity_log using the current schema: act INT + det TEXT.
--   - Enforcement: Free users (b_pkg=0) can only renew ('ren') if offer expires within 2 days.
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.purchase_offer_boost(
  p_uid UUID,
  p_offer_id UUID,
  p_boost_type TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_owner_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_result JSONB;
  v_cost INTEGER;
  v_offer_status INTEGER;
  v_offer_end TIMESTAMPTZ;
  v_user_pkg INTEGER;
  v_config JSONB;
  v_new_balance INTEGER;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT usr_id, sts, ts_end
  INTO v_owner_id, v_offer_status, v_offer_end
  FROM public.offers
  WHERE id = p_offer_id
    AND i_del = 0;

  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND');
  END IF;

  IF v_owner_id <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER');
  END IF;

  -- 1. Fetch User Package to enforce renewal rules
  SELECT b_pkg INTO v_user_pkg FROM public.users WHERE id = p_uid AND i_del = 0;

  SELECT value
  INTO v_config
  FROM public.app_config
  WHERE key = 'main';

  v_cost := CASE p_boost_type
    WHEN 'ren' THEN COALESCE((v_config->'spd'->>'ren')::INT, 500)
    WHEN 'pin' THEN COALESCE((v_config->'spd'->>'pin')::INT, 2000)
    WHEN 'bst' THEN COALESCE((v_config->'spd'->>'bst')::INT, 4000)
    WHEN 'dsc5' THEN COALESCE((v_config->'spd'->>'dsc5')::INT, 3000)
    WHEN 'fms' THEN COALESCE((v_config->'spd'->>'fms')::INT, 8000)
    ELSE NULL
  END;

  IF v_cost IS NULL OR v_cost <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_BOOST_TYPE');
  END IF;

  -- 2. Renewal-specific validations
  IF p_boost_type = 'ren' THEN
    -- Cannot renew rejected offers
    IF v_offer_status = 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'REJECTED_OFFER');
    END IF;

    -- Free users (b_pkg=0) can only renew if the offer is close to expiring (<= 2 days)
    -- If ts_end is NULL or in the past, it's allowed.
    IF v_user_pkg = 0 AND v_offer_end > (v_now + INTERVAL '2 days') THEN
      RETURN jsonb_build_object('success', false, 'error', 'RENEWAL_TOO_EARLY');
    END IF;
  END IF;

  -- Atomic points deduction prevents race conditions and forged/negative costs.
  UPDATE public.users
  SET pt = pt - v_cost,
      ts_upd = v_now
  WHERE id = p_uid
    AND i_del = 0
    AND sts = 0
    AND COALESCE(pt, 0) >= v_cost
  RETURNING pt INTO v_new_balance;

  IF v_new_balance IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_POINTS', 'required', v_cost);
  END IF;

  CASE p_boost_type
    WHEN 'ren' THEN
      UPDATE public.offers
      SET ts_end = GREATEST(COALESCE(ts_end, v_now), v_now) + INTERVAL '30 days',
          ts_ren = v_now,
          sts = CASE WHEN sts = 4 THEN 2 ELSE sts END,
          i_pub = CASE WHEN sts = 4 THEN 1 ELSE i_pub END
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'ren', 'duration_days', 30);

    WHEN 'pin' THEN
      UPDATE public.offers
      SET i_pin = 1,
          pin_end = v_now + INTERVAL '7 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'pin', 'duration_days', 7);

    WHEN 'bst' THEN
      UPDATE public.offers
      SET i_bst = 1,
          bst_end = v_now + INTERVAL '14 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'bst', 'duration_days', 14);

    WHEN 'dsc5' THEN
      UPDATE public.offers
      SET dsc_pct = 5,
          dsc_end = v_now + INTERVAL '60 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'dsc5', 'discount_pct', 5, 'duration_days', 60);

    WHEN 'fms' THEN
      UPDATE public.offers
      SET i_fms = 1,
          fms_end = v_now + INTERVAL '30 days'
      WHERE id = p_offer_id
        AND usr_id = p_uid
        AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'fms', 'duration_days', 30);
  END CASE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_UPDATE_FAILED';
  END IF;

  INSERT INTO public.activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (
    p_uid,
    20,
    'offer_boost: type=' || p_boost_type || ' cost=' || v_cost::TEXT,
    p_offer_id::TEXT,
    'offers',
    v_now
  );

  RETURN jsonb_build_object(
    'success', true,
    'result', v_result,
    'new_balance', v_new_balance,
    'cost', v_cost
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.purchase_offer_boost(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.purchase_offer_boost(UUID, UUID, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.purchase_offer_boost(UUID, UUID, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.purchase_offer_boost(UUID, UUID, TEXT) TO service_role;
