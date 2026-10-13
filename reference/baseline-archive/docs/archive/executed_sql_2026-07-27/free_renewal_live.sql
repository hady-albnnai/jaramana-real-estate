-- purchase_offer_boost (live-only drift) + منطق التجديد المجاني (قرار المالك 2026-07-26):
-- باقة فعالة → تجديد مجاني دائماً | بلا باقة + العرض الوحيد + آخر يومين (غير منتهٍ) → مجاني |
-- زيادة عن الحق بدون باقة أو عرض منتهي الصلاحية → spd.ren نقطة (500 افتراضياً)
CREATE OR REPLACE FUNCTION public.purchase_offer_boost(p_uid uuid, p_offer_id uuid, p_boost_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_owner_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_result JSONB;
  v_cost INTEGER;
  v_offer_status INTEGER;
  v_config JSONB;
  v_new_balance INTEGER;
  -- متغيرات قاعدة التجديد المجاني
  v_b_pkg INT;
  v_pkg_end TIMESTAMPTZ;
  v_pkg_grace TIMESTAMPTZ;
  v_has_pkg BOOLEAN;
  v_others INT;
  v_ts_end TIMESTAMPTZ;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT usr_id, sts INTO v_owner_id, v_offer_status
  FROM public.offers WHERE id = p_offer_id AND i_del = 0;

  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND');
  END IF;

  IF v_owner_id <> p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER');
  END IF;

  SELECT value INTO v_config FROM public.app_config WHERE key = 'main';

  IF p_boost_type = 'ren' THEN
    IF v_offer_status = 3 THEN
      RETURN jsonb_build_object('success', false, 'error', 'REJECTED_OFFER');
    END IF;

    -- (1) باقة فعالة؟ → مجاني دائماً
    SELECT b_pkg, pkg_end, pkg_grace INTO v_b_pkg, v_pkg_end, v_pkg_grace
    FROM public.users WHERE id = p_uid AND i_del = 0;
    v_has_pkg := COALESCE(v_b_pkg, 0) > 0
      AND ( (v_pkg_end IS NOT NULL AND v_pkg_end > v_now)
         OR (v_pkg_grace IS NOT NULL AND v_pkg_grace > v_now) );

    SELECT ts_end INTO v_ts_end FROM public.offers WHERE id = p_offer_id;

    IF v_has_pkg THEN
      v_cost := 0;
    ELSE
      SELECT COUNT(*) INTO v_others FROM public.offers
      WHERE usr_id = p_uid AND i_del = 0 AND id <> p_offer_id AND sts IN (0,1,2,5);

      IF COALESCE(v_others, 0) = 0 AND v_ts_end IS NOT NULL
         AND v_ts_end >= v_now AND v_ts_end <= v_now + INTERVAL '2 days' THEN
        -- (2) بلا باقة + عرض وحيد + ضمن آخر يومين ولم ينتهِ → مجاني
        v_cost := 0;
      ELSIF COALESCE(v_others, 0) = 0 AND v_ts_end IS NOT NULL
            AND v_ts_end > v_now + INTERVAL '2 days' THEN
        -- مجاني خارج نافذة اليومين → مرفوض (الواجهة تعطّل أساساً، هذا حسم خادمي)
        RETURN jsonb_build_object('success', false, 'error', 'RENEW_TOO_EARLY');
      ELSE
        -- (3) عروض زائدة بلا باقة نشطة، أو عرض منتهي الصلاحية → بالنقاط
        v_cost := COALESCE((v_config->'spd'->>'ren')::INT, 500);
      END IF;
    END IF;
  ELSE
    v_cost := CASE p_boost_type
      WHEN 'pin' THEN COALESCE((v_config->'spd'->>'pin')::INT, 2000)
      WHEN 'bst' THEN COALESCE((v_config->'spd'->>'bst')::INT, 4000)
      WHEN 'dsc5' THEN COALESCE((v_config->'spd'->>'dsc5')::INT, 3000)
      WHEN 'fms' THEN COALESCE((v_config->'spd'->>'fms')::INT, 8000)
      ELSE NULL
    END;
    IF v_cost IS NULL OR v_cost <= 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_BOOST_TYPE');
    END IF;
  END IF;

  -- خصم النقاط ذرّياً (v_cost = 0 يمر تلقائياً للتجديد المجاني)
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
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'ren', 'duration_days', 30);

    WHEN 'pin' THEN
      UPDATE public.offers
      SET i_pin = 1, pin_end = v_now + INTERVAL '7 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'pin', 'duration_days', 7);

    WHEN 'bst' THEN
      UPDATE public.offers
      SET i_bst = 1, bst_end = v_now + INTERVAL '14 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'bst', 'duration_days', 14);

    WHEN 'dsc5' THEN
      UPDATE public.offers
      SET dsc_pct = 5, dsc_end = v_now + INTERVAL '60 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'dsc5', 'discount_pct', 5, 'duration_days', 60);

    WHEN 'fms' THEN
      UPDATE public.offers
      SET i_fms = 1, fms_end = v_now + INTERVAL '30 days'
      WHERE id = p_offer_id AND usr_id = p_uid AND i_del = 0;
      v_result := jsonb_build_object('boost_type', 'fms', 'duration_days', 30);
  END CASE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_UPDATE_FAILED';
  END IF;

  INSERT INTO public.activity_log (uid, act, det, ref_id, ref_col, ts_crt)
  VALUES (
    p_uid, 20,
    'offer_boost: type=' || p_boost_type || ' cost=' || v_cost::TEXT,
    p_offer_id::TEXT, 'offers', v_now
  );

  RETURN jsonb_build_object(
    'success', true,
    'result', v_result,
    'new_balance', v_new_balance,
    'cost', v_cost
  );
END;
$function$;
REVOKE ALL ON FUNCTION purchase_offer_boost(p_uid uuid, p_offer_id uuid, p_boost_type text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION purchase_offer_boost(p_uid uuid, p_offer_id uuid, p_boost_type text) TO service_role;
