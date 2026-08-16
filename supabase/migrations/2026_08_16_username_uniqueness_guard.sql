-- USERNAME-UNIQ-001 — منع اسم المستخدم المكرر بشكل قطعي
-- التاريخ: 2026-08-16
--
-- طبقات الحماية:
-- 1) فحص التوفر اللحظي في شاشة التسجيل الأول.
-- 2) فحص نهائي داخل register_password.
-- 3) فهرس فريد على الاسم العربي/اللاتيني بعد التطبيع، لمنع سباق طلبين متزامنين.

BEGIN;

-- تحقق قبل التطبيق: يجب ألا توجد أسماء متكررة بعد التطبيع.
DO $verify$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE i_del = 0
      AND NULLIF(BTRIM(usr), '') IS NOT NULL
    GROUP BY public.normalize_arabic_username(usr)
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_NORMALIZED_USERNAMES_EXIST';
  END IF;
END;
$verify$;

-- الفحص العام يرجع false للاسم الفارغ/غير الصالح بدلاً من تسريب استثناء.
CREATE OR REPLACE FUNCTION public.check_username_available(p_username text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_usr text;
  v_norm text;
BEGIN
  BEGIN
    v_usr := public.app_assert_username(p_username, true);
  EXCEPTION WHEN OTHERS THEN
    RETURN false;
  END;

  v_norm := public.normalize_arabic_username(v_usr);
  RETURN NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE public.normalize_arabic_username(usr) = v_norm
      AND i_del = 0
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.check_username_available(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_username_available(text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_username_available(text) TO service_role;

-- فحص نهائي + تحويل أي تعارض من الفهرس إلى رمز عربي قابل للترجمة.
CREATE OR REPLACE FUNCTION public.register_password(
  p_user_uid uuid,
  p_username text,
  p_password text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_usr text;
  v_norm text;
  v_existing uuid;
BEGIN
  v_usr := public.app_assert_username(p_username, true);
  v_norm := public.normalize_arabic_username(v_usr);
  PERFORM public.app_assert_password(p_password, 8);

  SELECT id INTO v_existing
  FROM public.users
  WHERE public.normalize_arabic_username(usr) = v_norm
    AND i_del = 0
    AND id <> p_user_uid;

  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'USERNAME_TAKEN';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = p_user_uid AND i_del = 0
  ) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  BEGIN
    UPDATE public.users
    SET usr = v_usr,
        pwd = crypt(p_password, gen_salt('bf', 8)),
        ts_upd = now()
    WHERE id = p_user_uid;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'USERNAME_TAKEN';
  END;

  RETURN jsonb_build_object('success', true, 'username', v_usr);
END;
$function$;

REVOKE ALL ON FUNCTION public.register_password(uuid, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.register_password(uuid, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_password(uuid, text, text) TO service_role;

-- الفهرس القديم يمنع اختلاف حالة الأحرف فقط. الجديد يمنع أيضاً الأشكال
-- العربية المتكافئة بعد إزالة التشكيل وتوحيد الألف/الياء/التاء المربوطة.
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username_normalized_active
ON public.users (public.normalize_arabic_username(usr))
WHERE usr IS NOT NULL AND NULLIF(BTRIM(usr), '') IS NOT NULL AND i_del = 0;

DROP INDEX IF EXISTS public.ux_users_username_active;

-- تحقق بعد التطبيق: فهرس واحد فعّال ولا تكرار حي.
DO $verify$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename = 'users'
      AND indexname = 'ux_users_username_normalized_active'
  ) THEN
    RAISE EXCEPTION 'USERNAME_UNIQUE_INDEX_MISSING';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE i_del = 0
      AND NULLIF(BTRIM(usr), '') IS NOT NULL
    GROUP BY public.normalize_arabic_username(usr)
    HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'DUPLICATE_NORMALIZED_USERNAMES_AFTER_MIGRATION';
  END IF;
END;
$verify$;

COMMIT;
