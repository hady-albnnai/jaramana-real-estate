-- ════════════════════════════════════════════════════════════════════════════
-- Offer creation RPC for current dev auth model
-- Date: 2026-06-10
-- Purpose:
--   Avoid direct INSERT failures under RLS when auth.uid() is not available
--   in the WhatsApp dev fallback flow.
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION create_offer_internal(
  p_user_uid UUID,
  p_offer JSONB
)
RETURNS SETOF offers AS $$
DECLARE
  v_user users%ROWTYPE;
BEGIN
  SELECT * INTO v_user
  FROM users
  WHERE id = p_user_uid
    AND i_del = 0
    AND sts = 0;

  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
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
    COALESCE((p_offer->>'sts')::INT, 0),
    COALESCE(p_offer->>'rsn', ''),
    COALESCE((p_offer->>'vws')::INT, 0),
    COALESCE((p_offer->>'fvs')::INT, 0),
    COALESCE((p_offer->>'i_pub')::INT, 0),
    COALESCE((p_offer->>'i_soc')::INT, 0),
    COALESCE((p_offer->>'soc_pub')::INT, 0),
    COALESCE(p_offer->>'soc_txt', ''),
    COALESCE((p_offer->>'i_dup')::INT, 0),
    NULLIF(p_offer->>'dup_of', '')::UUID,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    COALESCE((p_offer->>'i_del')::INT, 0),
    NOW(),
    NULL,
    NULL,
    NULL
  )
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_offer_internal(UUID, JSONB) TO anon, authenticated;
