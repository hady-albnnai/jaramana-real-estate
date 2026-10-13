-- ════════════════════════════════════════════════════════════════════════════
-- Logic fixes: boosts + payment approval
-- Date: 2026-06-10
-- Purpose:
--   - server calculates boost cost from config
--   - prevent negative/forged boost prices from client
--   - validate payment approval by admin role and pending state
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Replace purchase_offer_boost signature
-- ─────────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS purchase_offer_boost(UUID, UUID, TEXT, INTEGER);

CREATE OR REPLACE FUNCTION purchase_offer_boost(
  p_uid UUID,
  p_offer_id UUID,
  p_boost_type TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_user_pts INTEGER;
  v_owner_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_result JSONB;
  v_cost INTEGER;
  v_offer_status INTEGER;
  v_config JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT usr_id, sts INTO v_owner_id, v_offer_status
  FROM offers
  WHERE id = p_offer_id AND i_del = 0;

  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND');
  END IF;
  IF v_owner_id <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER');
  END IF;

  SELECT value INTO v_config
  FROM app_config
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

  SELECT pt INTO v_user_pts FROM users WHERE id = p_uid;
  IF v_user_pts IS NULL OR v_user_pts < v_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INSUFFICIENT_POINTS',
      'current_points', COALESCE(v_user_pts, 0),
      'required', v_cost
    );
  END IF;

  CASE p_boost_type
    WHEN 'ren' THEN
      IF v_offer_status = 3 THEN
        RETURN jsonb_build_object('success', false, 'error', 'REJECTED_OFFER');
      END IF;

      UPDATE offers SET
        ts_end = GREATEST(COALESCE(ts_end, v_now), v_now) + INTERVAL '30 days',
        ts_ren = v_now,
        sts = CASE WHEN sts = 4 THEN 2 ELSE sts END,
        i_pub = CASE WHEN sts = 4 THEN 1 ELSE i_pub END,
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'ren', 'duration_days', 30);

    WHEN 'pin' THEN
      UPDATE offers SET
        i_pin = 1,
        pin_end = v_now + INTERVAL '7 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'pin', 'duration_days', 7);

    WHEN 'bst' THEN
      UPDATE offers SET
        i_bst = 1,
        bst_end = v_now + INTERVAL '14 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'bst', 'duration_days', 14);

    WHEN 'dsc5' THEN
      UPDATE offers SET
        dsc_pct = 5,
        dsc_end = v_now + INTERVAL '60 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'dsc5', 'discount_pct', 5);

    WHEN 'fms' THEN
      UPDATE offers SET
        i_fms = 1,
        fms_end = v_now + INTERVAL '30 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'fms', 'duration_days', 30);
  END CASE;

  UPDATE users SET
    pt = pt - v_cost,
    ts_upd = v_now
  WHERE id = p_uid;

  INSERT INTO activity_log (uid, action, details, ts_crt)
  VALUES (
    p_uid,
    'offer_boost',
    jsonb_build_object(
      'offer_id', p_offer_id,
      'boost_type', p_boost_type,
      'cost', v_cost
    ),
    v_now
  );

  RETURN jsonb_build_object('success', true, 'result', v_result, 'new_balance', v_user_pts - v_cost);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION purchase_offer_boost(UUID, UUID, TEXT) TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Payment approval hardened
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION approve_payment_final(
  p_payment_id UUID,
  p_admin_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_pkg_id INT;
  v_pkg_duration INT;
  v_config JSONB;
  v_admin_role INT;
  v_payment_status INT;
  v_payment_type INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT role INTO v_admin_role
  FROM users
  WHERE id = p_admin_id
    AND i_del = 0;

  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT uid, pkg, sts, tp
    INTO v_user_id, v_pkg_id, v_payment_status, v_payment_type
  FROM payments
  WHERE id = p_payment_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND');
  END IF;

  IF COALESCE(v_payment_status, -1) <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_PENDING');
  END IF;

  IF COALESCE(v_payment_type, -1) <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_PAYMENT_TYPE');
  END IF;

  SELECT value INTO v_config FROM app_config WHERE key = 'main';
  v_pkg_duration := (v_config->'pkg'->(v_pkg_id::text)->>'d')::INT;

  IF v_pkg_duration IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PKG_DURATION_NOT_FOUND');
  END IF;

  UPDATE payments
  SET sts = 1,
      appr_by = p_admin_id,
      ts_upd = NOW()
  WHERE id = p_payment_id
    AND sts = 0;

  UPDATE users
  SET b_pkg = v_pkg_id,
      pkg_end = GREATEST(COALESCE(pkg_end, NOW()), NOW()) + (v_pkg_duration || ' days')::interval,
      ts_upd = NOW()
  WHERE id = v_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Package activated successfully',
    'duration', v_pkg_duration
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION approve_payment_final(UUID, UUID) TO authenticated;
