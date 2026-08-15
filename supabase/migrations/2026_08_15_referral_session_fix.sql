-- ============================================================================
-- 2026_08_15 — REF-001: الإحالة معطّلة كلياً (حارس auth.uid + لا مُدخِل للكود)
-- ============================================================================
-- بلاغ المالك: «دعوة الأصدقاء بمشاركة الكود يربح كل واحد 1500 نقطة منهم،
-- لكن لا يوجد مكان لإدخال الكود صح؟ وتحقق أن الآلية تعمل بشكل كامل».
--
-- التشخيص كشف عطلين:
--   ① 🔴 `apply_referral` تبدأ بـ:
--         IF auth.uid() IS NULL OR auth.uid() <> p_new_uid THEN RAISE ...
--      والتطبيق يسجّل الدخول **بجلسة مخصّصة** (staff_session_token) لا
--      بجلسة Supabase ⇒ `auth.uid()` = NULL **دائماً** ⇒ الدالة ترفض كل
--      استدعاء. (نفس جذر عطل UX-003 في الدفعات وRATE-001 في التقييم.)
--   ② لا يوجد أي حقل في الواجهة لإدخال كود المُحيل (عولج في الواجهة).
--
-- دليل حي قاطع: `SELECT COUNT(*) FROM users WHERE ref_by IS NOT NULL` = **0**
-- و`ref_cnt > 0` = **0** ⇒ صفر إحالة منذ إطلاق التطبيق. الميزة معلنة
-- للمستخدم (1500 نقطة) ولم تعمل ولا مرة.
--
-- الإصلاح: الدالة تُستدعى حصراً من Edge `user-rewards` بمفتاح الخدمة بعد
-- تحقق الجلسة، فالحارس الصحيح هو منع `anon`/`authenticated` من تنفيذها
-- (§7) لا `auth.uid()`. نُبقي فحص auth.uid **فقط** إن كانت موجودة فعلاً
-- (مسار jwt المستقبلي) — وهو نفس نمط بقية الدوال الداخلية في المشروع.
--
-- ⚠️ كل حمايات مكافحة الاحتيال تبقى كما هي بلا مساس:
--    نفس الجهاز · نفس الـIP · سقف 5 إحالات/ساعة · منع الإحالة الذاتية ·
--    منع تكرار الإحالة لنفس المستخدم.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_referral(
  p_new_uid       uuid,
  p_referrer_code text,
  p_pts           integer DEFAULT 1500
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_referrer_uid UUID;
  v_recent_refs  INT;
  v_new_dev TEXT;  v_ref_dev TEXT;
  v_new_ip  INET;  v_ref_ip  INET;
BEGIN
  -- 🔑 REF-001: كان `auth.uid() IS NULL` يرفض كل استدعاء لأن الجلسة مخصّصة.
  -- الآن: نتحقق فقط عند وجود جلسة Supabase حقيقية (نفس نمط باقي الدوال).
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_new_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  IF p_new_uid IS NULL OR COALESCE(TRIM(p_referrer_code), '') = '' THEN
    RETURN FALSE;
  END IF;

  -- الكود = أول أحرف الـUID بلا شرطات. نطلب 6 أحرف على الأقل حتى لا
  -- يطابق كودٌ قصيرٌ عدة مستخدمين عشوائياً.
  IF LENGTH(TRIM(p_referrer_code)) < 6 THEN
    RETURN FALSE;
  END IF;

  SELECT id INTO v_referrer_uid
    FROM users
   WHERE REPLACE(id::text, '-', '') ILIKE TRIM(p_referrer_code) || '%'
     AND i_del = 0
   LIMIT 1;

  IF v_referrer_uid IS NULL OR v_referrer_uid = p_new_uid THEN
    RETURN FALSE;
  END IF;

  IF EXISTS (SELECT 1 FROM users WHERE id = p_new_uid AND ref_by IS NOT NULL) THEN
    RETURN FALSE;
  END IF;

  -- 🛡️ مكافحة مزرعة الإحالات (بلا تغيير)
  SELECT device_id, COALESCE(signup_ip, last_ip) INTO v_new_dev, v_new_ip
    FROM users WHERE id = p_new_uid;
  SELECT device_id, COALESCE(signup_ip, last_ip) INTO v_ref_dev, v_ref_ip
    FROM users WHERE id = v_referrer_uid;

  IF v_new_dev IS NOT NULL AND v_new_dev = v_ref_dev THEN
    RAISE EXCEPTION 'FRAUD_DETECTED: Same device.';
  END IF;
  IF v_new_ip IS NOT NULL AND v_new_ip = v_ref_ip THEN
    RAISE EXCEPTION 'FRAUD_DETECTED: Same IP.';
  END IF;

  SELECT COUNT(*) INTO v_recent_refs FROM users
   WHERE ref_by = v_referrer_uid AND ts_crt > NOW() - INTERVAL '1 hour';
  IF v_recent_refs >= 5 THEN
    RAISE EXCEPTION 'RATE_LIMIT: Referrer reached 5 referrals/hour cap.';
  END IF;

  UPDATE users SET ref_by  = v_referrer_uid WHERE id = p_new_uid;
  UPDATE users SET ref_cnt = COALESCE(ref_cnt, 0) + 1 WHERE id = v_referrer_uid;
  UPDATE users SET pt = COALESCE(pt, 0) + p_pts WHERE id IN (p_new_uid, v_referrer_uid);

  PERFORM update_user_badge(p_new_uid);
  PERFORM update_user_badge(v_referrer_uid);

  RETURN TRUE;
END;
$function$;

-- §7 رباعي التحصين — هذا هو الحارس الحقيقي بدل auth.uid()
REVOKE ALL ON FUNCTION public.apply_referral(uuid, text, integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.apply_referral(uuid, text, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_referral(uuid, text, integer) TO service_role;
