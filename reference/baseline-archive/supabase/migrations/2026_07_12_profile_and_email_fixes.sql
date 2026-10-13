-- ═══════════════════════════════════════════════════════════════════════
-- إصلاحات سيرفر — 2026-07-12
-- 1. إضافة حقل ph (رقم الهاتف) لدالة update_user_profile_internal
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.update_user_profile_internal(
  p_user_uid UUID,
  p_payload JSONB
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_nm TEXT;
  v_ph TEXT;
  v_sid TEXT;
  v_ad TEXT;
  v_img TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  v_nm := CASE WHEN p_payload ? 'nm' THEN app_assert_text_len(p_payload->>'nm', 'name', 2, 60) ELSE NULL END;
  v_ph := CASE WHEN p_payload ? 'ph' THEN app_assert_phone(p_payload->>'ph') ELSE NULL END;
  v_sid := CASE WHEN p_payload ? 'sid' THEN app_clean_text(p_payload->>'sid', 60) ELSE NULL END;
  v_ad := CASE WHEN p_payload ? 'ad' THEN app_clean_text(p_payload->>'ad', 200) ELSE NULL END;
  v_img := CASE WHEN p_payload ? 'img' THEN app_clean_text(p_payload->>'img', 500) ELSE NULL END;

  UPDATE users
  SET nm = COALESCE(v_nm, nm),
      ph = COALESCE(v_ph, ph),
      sid = COALESCE(v_sid, sid),
      ad = COALESCE(v_ad, ad),
      img = COALESCE(v_img, img),
      ts_upd = NOW()
  WHERE id = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  RETURN TRUE;
END;
$$;

-- ✅ فقط service_role يقدر يستدعيها (Edge Functions)
-- anon و authenticated ما لازم يوصلوا مباشرة عبر REST API
REVOKE EXECUTE ON FUNCTION public.update_user_profile_internal(UUID, JSONB) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_profile_internal(UUID, JSONB) TO service_role;
