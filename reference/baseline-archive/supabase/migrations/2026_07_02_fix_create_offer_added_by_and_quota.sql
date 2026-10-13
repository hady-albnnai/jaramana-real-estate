-- =====================================================================
-- Migration: 2026_07_02_fix_create_offer_added_by_and_quota.sql
-- الغرض: تصحيح توثيق معرف الإداري الذي أضاف العرض بالنيابة عن العميل (added_by)
-- وإعفاء الإضافات الإدارية من فحص حصص النشر (Quotas) مع حراسة أمنية ضد الانتحال.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.create_offer_internal(
  p_user_uid UUID,
  p_offer JSONB
) RETURNS SETOF offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_recent_deleted INT;
  v_duplicate BOOLEAN;
  v_effective_pkg INT;
  v_title TEXT;
  v_contact_ph TEXT;
  v_desc TEXT;
  v_exact_loc TEXT;
  v_soc_txt TEXT;
  v_price NUMERIC;
  v_admin_role INT;
  v_added_by UUID := NULL;
  v_is_admin_action BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  -- التحقق من هوية المنفذ الإداري (added_by) وحراسته من التلاعب
  IF p_offer ? 'added_by' AND NULLIF(p_offer->>'added_by', '') IS NOT NULL THEN
    SELECT role INTO v_admin_role FROM users
    WHERE id = (p_offer->>'added_by')::UUID AND sts = 0 AND i_del = 0;

    IF COALESCE(v_admin_role, 0) >= 4 THEN
      v_added_by := (p_offer->>'added_by')::UUID;
      v_is_admin_action := TRUE;
    ELSE
      -- إذا حاول شخص غير إداري تمرير added_by نرفض القيمة ونعتبرها NULL
      v_added_by := NULL;
    END IF;
  ELSE
    -- إذا كان المنفذ هو المستخدم نفسه ولكنه موظف إداري يضيف لنفسه
    IF COALESCE(v_user.role, 0) >= 4 THEN
      v_added_by := p_user_uid;
      v_is_admin_action := TRUE;
    END IF;
  END IF;

  v_title := app_assert_text_len(COALESCE(p_offer->>'ttl', p_offer->>'title'), 'title', 2, 120);
  v_contact_ph := app_assert_phone(p_offer->>'contact_ph');
  v_price := app_assert_price(COALESCE((p_offer->>'prc')::NUMERIC, 0), TRUE);
  v_desc := app_clean_text(p_offer->>'descript', 2000);
  v_exact_loc := app_clean_text(p_offer->>'exact_loc', 300);
  v_soc_txt := app_clean_text(p_offer->>'soc_txt', 500);

  -- الإدارة الداخلية (موظف مكتب فما فوق أو إضافة إدارية لعميل) غير مقيّدة بحصة.
  IF NOT v_is_admin_action THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';

    v_effective_pkg := CASE
      WHEN COALESCE(v_user.b_pkg, 0) = 0 THEN 0
      WHEN v_user.pkg_grace IS NOT NULL AND v_user.pkg_grace > NOW() THEN v_user.b_pkg
      WHEN v_user.pkg_end IS NOT NULL AND v_user.pkg_end > NOW() THEN v_user.b_pkg
      ELSE 0
    END;

    v_limit := COALESCE((v_config->'pkg'->(v_effective_pkg::TEXT)->>'o')::INT,
      CASE WHEN COALESCE(v_user.role, 0) = 1 THEN 5 ELSE 1 END);

    SELECT COUNT(*) INTO v_used
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1, 2, 5);

    SELECT COUNT(*) INTO v_recent_deleted
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 1
      AND ts_crt >= NOW() - INTERVAL '24 hours';

    v_used := COALESCE(v_used, 0) + COALESCE(v_recent_deleted, 0);
    IF v_used >= v_limit THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  SELECT check_offer_duplicate(
    v_title,
    v_price,
    COALESCE(p_offer->'loc', '{"r":0,"d":""}'::jsonb),
    p_user_uid
  ) INTO v_duplicate;

  IF v_duplicate THEN
    RAISE EXCEPTION 'DUPLICATE_OFFER';
  END IF;

  RETURN QUERY
  INSERT INTO offers (
    usr_id, brk_id, brk_pct, typ, trx, cat, sub, contact_ph,
    ttl, prc, cur, loc, descript, imgs, vdo, doc_tp, doc_img,
    exact_loc, specs, com, sts, rsn, vws, fvs, i_pub, i_soc,
    soc_pub, soc_txt, i_dup, dup_of, avl, i_del, ts_crt, ts_pub, ts_end, ts_ren, added_by
  ) VALUES (
    p_user_uid,
    NULLIF(p_offer->>'brk_id', '')::UUID,
    COALESCE((p_offer->>'brk_pct')::NUMERIC, 0),
    COALESCE((p_offer->>'typ')::INT, 0),
    COALESCE((p_offer->>'trx')::INT, 0),
    COALESCE((p_offer->>'cat')::INT, 0),
    COALESCE((p_offer->>'sub')::INT, 0),
    v_contact_ph,
    v_title,
    v_price,
    COALESCE((p_offer->>'cur')::INT, 0),
    COALESCE(p_offer->'loc', '{}'::jsonb),
    v_desc,
    COALESCE(p_offer->'imgs', '[]'::jsonb),
    app_clean_text(p_offer->>'vdo', 500),
    COALESCE((p_offer->>'doc_tp')::INT, 0),
    app_clean_text(p_offer->>'doc_img', 500),
    v_exact_loc,
    COALESCE(p_offer->'specs', '{}'::jsonb),
    COALESCE((p_offer->>'com')::NUMERIC, 0),
    1,
    '',
    0,
    0,
    0,
    COALESCE((p_offer->>'i_soc')::INT, 0),
    0,
    v_soc_txt,
    0,
    NULL,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    0,
    NOW(),
    NULL,
    NULL,
    NULL,
    v_added_by
  ) RETURNING *;
END;
$$;
REVOKE ALL ON FUNCTION public.create_offer_internal(UUID, JSONB) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_offer_internal(UUID, JSONB) TO service_role;
