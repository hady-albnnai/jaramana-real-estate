CREATE OR REPLACE FUNCTION public.update_user_profile_internal(p_user_uid uuid, p_payload jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
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

  -- 🔒 §13 (2026-08-14): القائمة البيضاء كانت **تتجاهل المفاتيح المجهولة
  -- بصمت وتُرجع نجاحاً**. أمنياً سليم (role/pt/vrf/brk/b_pkg لا تُمَس أبداً —
  -- أُكِّد حياً بخمس محاولات تصعيد امتياز كلها بلا أثر)، لكنه يخفي أخطاء
  -- الواجهة: حقل يُرسَل باسم خاطئ يبدو محفوظاً وهو ليس كذلك، ويوهم مهاجماً
  -- بأن تصعيده نجح. الآن يُرفض أي مفتاح خارج القائمة صراحةً.
  IF EXISTS (
    SELECT 1 FROM jsonb_object_keys(p_payload) k
    WHERE k NOT IN ('nm','ph','sid','ad','img')
  ) THEN
    RAISE EXCEPTION 'PROFILE_FIELD_NOT_ALLOWED';
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
$function$;
