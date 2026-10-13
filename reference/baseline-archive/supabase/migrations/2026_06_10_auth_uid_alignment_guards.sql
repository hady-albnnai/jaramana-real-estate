-- ════════════════════════════════════════════════════════════════════════════
-- Partial auth.uid alignment guards for dev-compatible RPCs
-- Date: 2026-06-10
-- Purpose:
--   If auth.uid() is available, enforce it matches the uid passed from client.
--   This hardens production/real-session mode without breaking current dev fallback
--   where auth.uid() may still be NULL.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION admin_update_user_role(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_role INT
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 3 THEN
    RAISE EXCEPTION 'FORBIDDEN: Deputy/admin role required.';
  END IF;
  IF p_role < 0 OR p_role > 4 THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  UPDATE users
  SET role = p_role,
      brk = CASE WHEN p_role = 1 THEN 1 ELSE brk END,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_set_user_status(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_status INT,
  p_reason TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;
  IF p_status < 0 OR p_status > 2 THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  UPDATE users
  SET sts = p_status,
      ban_rsn = CASE WHEN p_status = 0 THEN '' ELSE COALESCE(p_reason, '') END,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_update_user_permissions_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_perm JSONB DEFAULT '[]'::jsonb
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
  v_item TEXT;
  v_allowed TEXT[] := ARRAY[
    'admin_dashboard','office_operations','manage_users','manage_permissions',
    'review_offers','review_verifications','media_review','photography_management',
    'photographer_tasks','fraud_suspects','manage_appointments','manage_deals',
    'manage_payments','manage_reports','manage_config','view_analytics',
    'broker_dashboard','broker_offers','broker_appointments','broker_deals',
    'broker_stats','user_home','user_offers','user_requests','user_appointments','user_profile'
  ];
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 3 THEN
    RAISE EXCEPTION 'FORBIDDEN: Deputy/admin role required.';
  END IF;

  IF p_perm IS NULL THEN p_perm := '[]'::jsonb; END IF;
  IF jsonb_typeof(p_perm) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_PERMISSIONS: Expected JSON array.';
  END IF;

  FOR v_item IN SELECT jsonb_array_elements_text(p_perm)
  LOOP
    IF NOT (v_item = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'INVALID_PERMISSION: %', v_item;
    END IF;
  END LOOP;

  UPDATE users
  SET perm = p_perm,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION create_offer_internal(
  p_user_uid UUID,
  p_offer JSONB
)
RETURNS SETOF offers AS $$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_recent_deleted INT;
  v_duplicate BOOLEAN;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user
  FROM users
  WHERE id = p_user_uid
    AND i_del = 0
    AND sts = 0;

  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  SELECT value INTO v_config FROM app_config WHERE key = 'main';

  IF COALESCE(v_user.role, 0) < 2 THEN
    v_limit := COALESCE((v_config->'pkg'->(COALESCE(v_user.b_pkg, 0)::TEXT)->>'o')::INT,
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
      AND ts_upd >= NOW() - INTERVAL '24 hours';

    IF COALESCE(v_used, 0) + COALESCE(v_recent_deleted, 0) >= v_limit THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  SELECT check_offer_duplicate(
    COALESCE(p_offer->>'ttl', ''),
    COALESCE((p_offer->>'prc')::NUMERIC, 0),
    COALESCE(p_offer->'loc', '{"r":0,"d":""}'::jsonb),
    p_user_uid
  ) INTO v_duplicate;

  IF v_duplicate THEN
    RAISE EXCEPTION 'DUPLICATE_OFFER';
  END IF;

  RETURN QUERY
  INSERT INTO offers (
    usr_id, brk_id, brk_pct, typ, trx, cat, sub, contact_ph, ttl, prc,
    cur, loc, descript, imgs, vdo, doc_tp, doc_img, exact_loc, specs, com,
    sts, rsn, vws, fvs, i_pub, i_soc, soc_pub, soc_txt, i_dup, dup_of, avl,
    i_del, ts_crt, ts_pub, ts_end, ts_ren
  ) VALUES (
    p_user_uid,
    NULLIF(p_offer->>'brk_id', '')::UUID,
    COALESCE((p_offer->>'brk_pct')::NUMERIC, 0),
    COALESCE((p_offer->>'typ')::INT, 0),
    COALESCE((p_offer->>'trx')::INT, 0),
    COALESCE((p_offer->>'cat')::INT, 0),
    COALESCE((p_offer->>'sub')::INT, 0),
    COALESCE(p_offer->>'contact_ph', ''),
    COALESCE(p_offer->>'ttl', ''),
    COALESCE((p_offer->>'prc')::NUMERIC, 0),
    COALESCE((p_offer->>'cur')::INT, 1),
    COALESCE(p_offer->'loc', '{"r":0,"d":""}'::jsonb),
    COALESCE(p_offer->>'descript', ''),
    COALESCE(p_offer->'imgs', '[]'::jsonb),
    COALESCE(p_offer->>'vdo', ''),
    COALESCE((p_offer->>'doc_tp')::INT, 0),
    COALESCE(p_offer->>'doc_img', ''),
    COALESCE(p_offer->>'exact_loc', ''),
    COALESCE(p_offer->'specs', '{}'::jsonb),
    COALESCE((p_offer->>'com')::NUMERIC, 0),
    1, '', 0, 0, 0,
    COALESCE((p_offer->>'i_soc')::INT, 0),
    0, COALESCE(p_offer->>'soc_txt', ''), 0,
    NULLIF(p_offer->>'dup_of', '')::UUID,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    0, NOW(), NULL, NULL, NULL
  )
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION create_photography_task_internal(
  p_admin_uid UUID,
  p_offer_id UUID,
  p_photographer_id UUID,
  p_notes TEXT DEFAULT '',
  p_ts_scheduled TIMESTAMPTZ DEFAULT NULL
)
RETURNS SETOF photography_tasks AS $$
DECLARE
  v_admin_role INT;
  v_offer offers%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;
  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'OFFER_NOT_FOUND'; END IF;

  RETURN QUERY
  INSERT INTO photography_tasks (off_id, photographer_id, requested_by, ttl, notes, loc, sts, ts_scheduled, ts_crt, ts_upd)
  VALUES (p_offer_id, p_photographer_id, p_admin_uid, v_offer.ttl, COALESCE(p_notes, ''), COALESCE(v_offer.loc, '{}'::jsonb), 0, p_ts_scheduled, NOW(), NOW())
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION submit_photography_task_internal(
  p_photographer_uid UUID,
  p_task_id UUID,
  p_media JSONB,
  p_photographer_note TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  IF jsonb_typeof(COALESCE(p_media, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_MEDIA_ARRAY';
  END IF;

  UPDATE photography_tasks
  SET media = COALESCE(p_media, '[]'::jsonb),
      photographer_note = COALESCE(p_photographer_note, ''),
      sts = 2,
      ts_submit = NOW(),
      ts_upd = NOW()
  WHERE id = p_task_id
    AND photographer_id = p_photographer_uid
    AND sts IN (0, 1, 4);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION update_photography_task_status_internal(
  p_admin_uid UUID,
  p_task_id UUID,
  p_status INT,
  p_office_note TEXT DEFAULT ''
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;
  IF p_status < 0 OR p_status > 5 THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  UPDATE photography_tasks
  SET sts = p_status,
      office_note = COALESCE(p_office_note, office_note),
      ts_done = CASE WHEN p_status IN (3, 4, 5) THEN NOW() ELSE ts_done END,
      ts_upd = NOW()
  WHERE id = p_task_id;

  IF NOT FOUND THEN RAISE EXCEPTION 'TASK_NOT_FOUND'; END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION attach_photography_media_to_offer_internal(
  p_admin_uid UUID,
  p_task_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
  v_task photography_tasks%ROWTYPE;
  v_existing JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;

  SELECT * INTO v_task FROM photography_tasks WHERE id = p_task_id;
  IF v_task.id IS NULL THEN RAISE EXCEPTION 'TASK_NOT_FOUND'; END IF;
  IF jsonb_array_length(COALESCE(v_task.media, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'NO_MEDIA';
  END IF;

  SELECT COALESCE(imgs, '[]'::jsonb) INTO v_existing FROM offers WHERE id = v_task.off_id;

  UPDATE offers
  SET imgs = (
    SELECT jsonb_agg(DISTINCT value)
    FROM jsonb_array_elements(v_existing || v_task.media)
  )
  WHERE id = v_task.off_id;

  UPDATE photography_tasks
  SET sts = 3,
      office_note = 'تم اعتماد التصوير وربط الوسائط بالعرض',
      ts_done = NOW(),
      ts_upd = NOW()
  WHERE id = p_task_id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
