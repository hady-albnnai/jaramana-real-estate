-- ════════════════════════════════════════════════════════════════════════════
-- Logic fixes: appointments + offer review alignment
-- Date: 2026-06-10
-- Purpose:
--   - add requester user to appointments
--   - unify appointment statuses to 0..5
--   - align pending offers to sts=1 (review)
--   - harden create_offer_internal with quota + duplicate checks
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Appointments: requester user + full status range
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE appointments
  ADD COLUMN IF NOT EXISTS req_uid UUID REFERENCES users(id) ON DELETE SET NULL;

UPDATE appointments a
SET req_uid = r.usr_id
FROM requests r
WHERE a.req_uid IS NULL
  AND a.req_id = r.id;

ALTER TABLE appointments
  DROP CONSTRAINT IF EXISTS appointments_sts_check;

ALTER TABLE appointments
  ADD CONSTRAINT appointments_sts_check CHECK (sts BETWEEN 0 AND 5);

CREATE INDEX IF NOT EXISTS idx_appointments_req_uid ON appointments(req_uid, sts);

COMMENT ON COLUMN appointments.req_uid IS
  'Requester user id (the user who booked the appointment). req_id remains optional link to requests table.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Pending offers count = review queue (sts=1)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_pending_offers_count()
RETURNS INTEGER AS $$
DECLARE
  v_cnt INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_cnt
  FROM offers
  WHERE sts = 1
    AND i_del = 0;
  RETURN v_cnt;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) create_offer_internal hardened
-- ─────────────────────────────────────────────────────────────────────────────
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
  SELECT * INTO v_user
  FROM users
  WHERE id = p_user_uid
    AND i_del = 0
    AND sts = 0;

  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  IF COALESCE(trim(p_offer->>'ttl'), '') = '' THEN
    RAISE EXCEPTION 'TITLE_REQUIRED';
  END IF;

  IF COALESCE(trim(p_offer->>'contact_ph'), '') = '' THEN
    RAISE EXCEPTION 'CONTACT_PHONE_REQUIRED';
  END IF;

  IF COALESCE((p_offer->>'prc')::NUMERIC, 0) <= 0 THEN
    RAISE EXCEPTION 'INVALID_PRICE';
  END IF;

  -- الإدارة الداخلية غير مقيّدة بحصة
  IF COALESCE(v_user.role, 0) < 2 THEN
    SELECT value INTO v_config
    FROM app_config
    WHERE key = 'main';

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

    v_used := COALESCE(v_used, 0) + COALESCE(v_recent_deleted, 0);

    IF v_used >= v_limit THEN
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
    usr_id,
    brk_id,
    brk_pct,
    typ,
    trx,
    cat,
    sub,
    contact_ph,
    ttl,
    prc,
    cur,
    loc,
    descript,
    imgs,
    vdo,
    doc_tp,
    doc_img,
    exact_loc,
    specs,
    com,
    sts,
    rsn,
    vws,
    fvs,
    i_pub,
    i_soc,
    soc_pub,
    soc_txt,
    i_dup,
    dup_of,
    avl,
    i_del,
    ts_crt,
    ts_pub,
    ts_end,
    ts_ren
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
    1,
    '',
    0,
    0,
    0,
    COALESCE((p_offer->>'i_soc')::INT, 0),
    0,
    COALESCE(p_offer->>'soc_txt', ''),
    0,
    NULLIF(p_offer->>'dup_of', '')::UUID,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    0,
    NOW(),
    NULL,
    NULL,
    NULL
  )
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_offer_internal(UUID, JSONB) TO anon, authenticated;
