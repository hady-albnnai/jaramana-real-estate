CREATE OR REPLACE FUNCTION public.verify_otp_v2(p_identifier text, p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_found BOOLEAN;
  v_attempts INT;
  c_max_attempts CONSTANT INT := 5;
BEGIN
  -- 🔒 BUG-031 (2026-08-14): لم يكن هناك أي حد لمحاولات التحقق.
  -- عمود `attempts` موجود في الجدول لكنه **لم يُستخدم إطلاقاً** — بقي 0 بعد
  -- 15 محاولة خاطئة متتالية (أُكِّد حياً).
  -- الخطورة: الرمز أرقام قليلة، فمهاجم يعرف رقم هاتف يجرّب كل الاحتمالات
  -- خلال نافذة صلاحية الرمز (10 دقائق) ويدخل الحساب بلا كلمة سر إطلاقاً —
  -- وهذا يلتفّ على SEC-005 (حد كلمات السر) لأنه مسار دخول مختلف.
  -- الآن: 5 محاولات لكل رمز، ثم يُبطَل الرمز ويُطلب واحد جديد.
  SELECT attempts INTO v_attempts
  FROM otp_codes
  WHERE identifier = p_identifier AND used = 0 AND expires_at > NOW()
  ORDER BY ts_crt DESC LIMIT 1;

  IF v_attempts IS NOT NULL AND v_attempts >= c_max_attempts THEN
    -- إبطال الرمز نهائياً حتى لا تُستأنف المحاولات عليه
    UPDATE otp_codes SET used = 1
    WHERE identifier = p_identifier AND used = 0 AND expires_at > NOW();
    RETURN FALSE;
  END IF;

  -- البحث في العمود الموحد فقط وبشكل صارم
  SELECT EXISTS(
    SELECT 1 FROM otp_codes
    WHERE identifier = p_identifier
      AND code = p_code
      AND used = 0
      AND expires_at > NOW()
  ) INTO v_found;

  IF v_found THEN
    -- تحديث الحالة لمنع إعادة استخدام الرمز
    UPDATE otp_codes SET used = 1
      WHERE identifier = p_identifier
        AND code = p_code
        AND used = 0;
    
    -- حذف الرمز فور استخدامه لزيادة الأمان وتوفير المساحة
    DELETE FROM otp_codes
      WHERE identifier = p_identifier
        AND used = 1;

    RETURN TRUE;
  END IF;

  -- محاولة فاشلة: نزيد العدّاد على الرمز النشط
  UPDATE otp_codes
  SET attempts = COALESCE(attempts, 0) + 1
  WHERE identifier = p_identifier AND used = 0 AND expires_at > NOW();

  RETURN FALSE;
END;
$function$;
