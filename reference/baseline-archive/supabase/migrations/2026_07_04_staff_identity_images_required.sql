-- =====================================================================
-- Migration: 2026_07_04_staff_identity_images_required.sql
-- الغرض:
--   ضمان أن الموظف/المحامي/المعقب المضاف من الإدارة يعتبر موثقاً وظيفياً
--   عند إنشائه، وأن حقول الهوية محفوظة ضمن users.
--   شرط صورتين الهوية يُفرض في Edge Function create-user قبل استدعاء RPC.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.admin_create_staff_user(
  p_admin_uid uuid,
  p_full_name text,
  p_phone text,
  p_email text DEFAULT ''::text,
  p_username text DEFAULT ''::text,
  p_password text DEFAULT ''::text,
  p_role integer DEFAULT 4
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'FULL_IDENTITY_REQUIRED';
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_create_staff_user(
  p_admin_uid uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_username text,
  p_password text,
  p_role integer,
  p_address text DEFAULT ''::text,
  p_sid text DEFAULT ''::text,
  p_img text DEFAULT ''::text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_admin_role INT;
  v_phone TEXT;
  v_username TEXT;
  v_new_id UUID;
BEGIN
  v_admin_role := public._admin_employee_assert_actor(p_admin_uid, 5);

  IF p_role NOT IN (2, 3, 4, 5, 7, 8) THEN
    RAISE EXCEPTION 'INVALID_ROLE';
  END IF;

  IF v_admin_role < 6 AND p_role >= 5 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_CREATE_DEPUTY';
  END IF;

  IF LENGTH(TRIM(COALESCE(p_full_name, ''))) < 2 THEN
    RAISE EXCEPTION 'NAME_REQUIRED';
  END IF;

  IF LENGTH(COALESCE(p_password, '')) < 8 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  IF LENGTH(TRIM(COALESCE(p_address, ''))) < 3 THEN
    RAISE EXCEPTION 'ADDRESS_REQUIRED';
  END IF;

  IF LENGTH(TRIM(COALESCE(p_sid, ''))) < 3 THEN
    RAISE EXCEPTION 'SID_REQUIRED';
  END IF;

  v_phone := public.normalize_sy_phone(p_phone);
  IF v_phone = '' THEN
    RAISE EXCEPTION 'PHONE_REQUIRED';
  END IF;

  v_username := NULLIF(public.normalize_arabic_username(p_username), '');

  IF EXISTS (SELECT 1 FROM public.users WHERE public.normalize_sy_phone(ph) = v_phone AND i_del = 0) THEN
    RAISE EXCEPTION 'PHONE_EXISTS';
  END IF;

  IF v_username IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.users
    WHERE public.normalize_arabic_username(usr) = v_username
      AND i_del = 0
  ) THEN
    RAISE EXCEPTION 'USERNAME_EXISTS';
  END IF;

  INSERT INTO public.users (
    nm, ph, eml, usr, pwd,
    role, ad, sid, img,
    sts, vrf, i_del, ts_crt, ts_upd
  ) VALUES (
    TRIM(p_full_name),
    v_phone,
    NULLIF(TRIM(COALESCE(p_email, '')), ''),
    v_username,
    crypt(p_password, gen_salt('bf', 10)),
    p_role,
    TRIM(COALESCE(p_address, '')),
    TRIM(COALESCE(p_sid, '')),
    COALESCE(p_img, ''),
    0,
    2,
    0,
    NOW(),
    NOW()
  ) RETURNING id INTO v_new_id;

  PERFORM public._admin_employee_log(
    p_admin_uid,
    'create_staff_full',
    v_new_id,
    jsonb_build_object('role', p_role, 'nm', p_full_name, 'sid', p_sid)
  );

  RETURN jsonb_build_object('success', true, 'user_id', v_new_id, 'role', p_role);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) TO service_role;

-- تصحيح الحسابات الداخلية الحالية التي أُنشئت سابقاً بدون vrf=2.
UPDATE public.users
SET vrf = 2,
    ts_upd = NOW()
WHERE role IN (2, 3, 4, 5, 6, 7, 8)
  AND i_del = 0
  AND vrf <> 2;
