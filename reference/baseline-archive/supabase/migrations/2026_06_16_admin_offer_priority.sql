CREATE OR REPLACE FUNCTION admin_set_offer_priority_internal(
  p_admin_uid UUID,
  p_offer_id UUID,
  p_priority_type TEXT,
  p_duration_days INT DEFAULT 7
)
RETURNS BOOLEAN AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- Reset all priorities first
  UPDATE offers SET
    i_pin = 0, pin_end = NULL,
    i_fms = 0, fms_end = NULL,
    i_bst = 0, bst_end = NULL
  WHERE id = p_offer_id;

  IF p_priority_type = 'pin' THEN
    UPDATE offers SET i_pin = 1, pin_end = NOW() + (p_duration_days || ' days')::interval WHERE id = p_offer_id;
  ELSIF p_priority_type = 'fms' THEN
    UPDATE offers SET i_fms = 1, fms_end = NOW() + (p_duration_days || ' days')::interval WHERE id = p_offer_id;
  ELSIF p_priority_type = 'bst' THEN
    UPDATE offers SET i_bst = 1, bst_end = NOW() + (p_duration_days || ' days')::interval WHERE id = p_offer_id;
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_set_offer_priority_internal(UUID, UUID, TEXT, INT) TO anon, authenticated;
