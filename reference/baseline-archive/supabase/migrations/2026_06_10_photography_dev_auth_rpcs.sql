-- ════════════════════════════════════════════════════════════════════════════
-- Photography RPCs compatible with current dev auth model
-- Date: 2026-06-10
-- ════════════════════════════════════════════════════════════════════════════

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
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;

  SELECT * INTO v_offer FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF v_offer.id IS NULL THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND';
  END IF;

  RETURN QUERY
  INSERT INTO photography_tasks (
    off_id,
    photographer_id,
    requested_by,
    ttl,
    notes,
    loc,
    sts,
    ts_scheduled,
    ts_crt,
    ts_upd
  ) VALUES (
    p_offer_id,
    p_photographer_id,
    p_admin_uid,
    v_offer.ttl,
    COALESCE(p_notes, ''),
    COALESCE(v_offer.loc, '{}'::jsonb),
    0,
    p_ts_scheduled,
    NOW(),
    NOW()
  )
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

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND';
  END IF;

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
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;

  SELECT * INTO v_task FROM photography_tasks WHERE id = p_task_id;
  IF v_task.id IS NULL THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND';
  END IF;

  IF jsonb_array_length(COALESCE(v_task.media, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'NO_MEDIA';
  END IF;

  SELECT COALESCE(imgs, '[]'::jsonb) INTO v_existing
  FROM offers
  WHERE id = v_task.off_id;

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

GRANT EXECUTE ON FUNCTION create_photography_task_internal(UUID, UUID, UUID, TEXT, TIMESTAMPTZ) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION submit_photography_task_internal(UUID, UUID, JSONB, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION update_photography_task_status_internal(UUID, UUID, INT, TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION attach_photography_media_to_offer_internal(UUID, UUID) TO anon, authenticated;
