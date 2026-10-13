CREATE OR REPLACE FUNCTION admin_delete_offer_internal(
  p_admin_uid UUID,
  p_offer_id UUID
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
    RAISE EXCEPTION 'FORBIDDEN: Admin permissions required';
  END IF;

  UPDATE offers
  SET i_del = 1, sts = 4
  WHERE id = p_offer_id;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION admin_delete_offer_internal(UUID, UUID) TO anon, authenticated, service_role;
