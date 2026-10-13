-- =====================================================================
-- Migration: 2026_07_02_arabic_phone_and_username_support.sql
-- الغرض: تمكين إدخال أرقام الهاتف بالأرقام العربية (المشرقية والفارسية)
-- ودعم أسماء المستخدمين باللغة العربية مع قواعد التطبيع ومنع الخلط والانتحال.
-- =====================================================================

-- 1. تحديث normalize_sy_phone لتحويل الأرقام العربية والفارسية إلى أرقام لاتينية قبل المعالجة
CREATE OR REPLACE FUNCTION public.normalize_sy_phone(p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := COALESCE(p_phone, '');
  -- ترجمة الأرقام العربية المشرقية (٠-٩) والفارسية (۰-۹) إلى لاتينية (0-9)
  v := translate(v, '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹', '01234567890123456789');
  v := regexp_replace(v, '[^0-9+]', '', 'g');

  IF v = '' THEN
    RETURN '';
  END IF;

  IF left(v, 1) = '+' THEN
    IF left(v, 4) = '+963' THEN
      RETURN v;
    END IF;
    RETURN v;
  END IF;

  IF left(v, 5) = '00963' THEN
    RETURN '+963' || substring(v from 6);
  END IF;

  IF left(v, 3) = '963' THEN
    RETURN '+' || v;
  END IF;

  IF left(v, 1) = '0' THEN
    RETURN '+963' || substring(v from 2);
  END IF;

  IF left(v, 1) = '9' THEN
    RETURN '+963' || v;
  END IF;

  RETURN v;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.normalize_sy_phone(TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_sy_phone(TEXT) TO service_role;

-- 2. دالة تطبيع أسماء المستخدمين العربية لمنع الانتحال عبر التشابه البصري والتشكيل
CREATE OR REPLACE FUNCTION public.normalize_arabic_username(p_str TEXT)
 RETURNS TEXT
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := lower(btrim(COALESCE(p_str, '')));
  -- إزالة التشكيل والحركات والشدة والتطويل (الكشيدة)
  v := regexp_replace(v, '[\u064B-\u065F\u0670\u0640]', '', 'g');
  -- توحيد أشكال الألف (أ إ آ -> ا)
  v := regexp_replace(v, '[أإآ]', 'ا', 'g');
  -- توحيد التاء المربوطة والهاء (ة -> ه)
  v := replace(v, 'ة', 'ه');
  -- توحيد الياء والألف المقصورة (ى ئ -> ي)
  v := regexp_replace(v, '[ىئ]', 'ي', 'g');
  RETURN v;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.normalize_arabic_username(TEXT) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.normalize_arabic_username(TEXT) TO service_role;

-- 3. تحديث app_assert_username للسماح بالعربية ومنع خلط اللغات (Script Mixing Prohibition)
CREATE OR REPLACE FUNCTION public.app_assert_username(p_username text, p_required boolean DEFAULT true)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v TEXT;
BEGIN
  v := lower(btrim(COALESCE(p_username, '')));
  IF v = '' THEN
    IF p_required THEN
      RAISE EXCEPTION 'USERNAME_REQUIRED';
    END IF;
    RETURN NULL;
  END IF;
  IF length(v) < 3 OR length(v) > 30 THEN
    RAISE EXCEPTION 'USERNAME_LENGTH';
  END IF;
  -- منع خلط اللغات: إما أحرف لاتينية وأرقام ورمزين، أو أحرف عربية وأرقام ورمزين
  IF NOT v ~ '^([a-z0-9_.]+|[\u0600-\u06FF0-9_.]+)$' THEN
    RAISE EXCEPTION 'USERNAME_INVALID_CHARS';
  END IF;
  RETURN v;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.app_assert_username(TEXT, BOOLEAN) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.app_assert_username(TEXT, BOOLEAN) TO service_role;

-- 4. تحديث check_username_available لاعتماد المقارنة الموحدة normalize_arabic_username
CREATE OR REPLACE FUNCTION public.check_username_available(p_username text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_usr TEXT;
  v_norm TEXT;
BEGIN
  v_usr := LOWER(TRIM(p_username));
  IF LENGTH(v_usr) < 3 THEN RETURN FALSE; END IF;
  v_norm := normalize_arabic_username(v_usr);
  RETURN NOT EXISTS (
    SELECT 1 FROM users WHERE normalize_arabic_username(usr) = v_norm AND i_del = 0
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.check_username_available(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_username_available(TEXT) TO service_role;

-- 5. تحديث register_password لاعتماد المقارنة الموحدة في فحص التكرار
CREATE OR REPLACE FUNCTION public.register_password(p_user_uid uuid, p_username text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_usr TEXT;
  v_norm TEXT;
  v_existing UUID;
BEGIN
  v_usr := app_assert_username(p_username, TRUE);
  v_norm := normalize_arabic_username(v_usr);
  PERFORM app_assert_password(p_password, 8);

  SELECT id INTO v_existing
  FROM users
  WHERE normalize_arabic_username(usr) = v_norm
    AND i_del = 0
    AND id <> p_user_uid;

  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'USERNAME_TAKEN';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_uid AND i_del = 0) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  UPDATE users
  SET usr = v_usr,
      pwd = crypt(p_password, gen_salt('bf', 8)),
      ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN jsonb_build_object('success', true, 'username', v_usr);
END;
$function$;
REVOKE ALL ON FUNCTION public.register_password(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_password(UUID, TEXT, TEXT) TO service_role;

-- 6. تحديث login_with_password لاعتماد المقارنة الموحدة في تسجيل الدخول
CREATE OR REPLACE FUNCTION public.login_with_password(p_identifier text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user RECORD;
  v_identifier TEXT;
  v_norm TEXT;
  v_session JSONB := NULL;
BEGIN
  v_identifier := LOWER(TRIM(p_identifier));
  v_norm := normalize_arabic_username(v_identifier);

  SELECT id, nm, role, pwd, sts, i_del INTO v_user
  FROM users
  WHERE (normalize_arabic_username(usr) = v_norm
         OR normalize_sy_phone(ph) = normalize_sy_phone(v_identifier))
    AND i_del = 0
  LIMIT 1;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING HINT = 'لم يتم العثور على حساب بهذا الاسم أو الرقم';
  END IF;

  IF v_user.pwd IS NULL THEN
    RAISE EXCEPTION 'NO_PASSWORD_SET' USING HINT = 'لم يتم تعيين كلمة مرور لهذا الحساب، سجّل دخولك عبر واتساب أولاً';
  END IF;

  IF v_user.sts = 2 THEN
    RAISE EXCEPTION 'USER_BANNED';
  END IF;

  IF v_user.sts = 1 THEN
    RAISE EXCEPTION 'USER_FROZEN';
  END IF;

  IF v_user.pwd != crypt(p_password, v_user.pwd) THEN
    RAISE EXCEPTION 'WRONG_PASSWORD' USING HINT = 'كلمة المرور غير صحيحة';
  END IF;

  -- Always issue session for any authenticated user
  v_session := _issue_staff_session(v_user.id, '', '', INTERVAL '7 days');

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user.id,
    'role', v_user.role,
    'nm', v_user.nm,
    'staff_session', v_session
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.login_with_password(TEXT, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_with_password(TEXT, TEXT) TO service_role;