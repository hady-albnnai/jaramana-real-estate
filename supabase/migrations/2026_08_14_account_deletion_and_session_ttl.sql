-- ============================================================================
-- GP-001 — حذف الحساب ذاتياً (شرط إلزامي في Google Play)
-- ============================================================================
-- الفجوة: إقرار Data Safety المرفوع لجوجل ينصّ حرفياً على «حذف الحساب من
-- داخل التطبيق» و«تُحذف جميع البيانات الشخصية خلال 30 يوماً»، بينما
-- **الميزة غير موجودة إطلاقاً** — لا شاشة ولا فعل ولا دالة. الموجود فقط
-- delete-user وهو للإدارة (minRole=5) ويحذف موظفاً لا يحذف المستخدم نفسه.
-- هذا إقرار غير مطابق للواقع: سبب رفض شائع، وقد يُعدّ تضليلاً بعد النشر.
--
-- التصميم (حذف ناعم مع تعمية البيانات الشخصية):
--   • لا نحذف الصف فيزيائياً — سلامة المراجع تنهار (عروض · مواعيد · دفعات
--     · صفقات تشير إليه) وسجلّ المحاسبة يضيع.
--   • نعمّي ما يُعرِّف الشخص (اسم · هاتف · بريد · عنوان · صور هوية) ونضع
--     علامة الحذف، فيصبح السجل مجهول الهوية لكن الروابط تبقى سليمة.
--   • نمنع الحذف عند وجود التزام مالي أو تشغيلي قائم (دفعة معلّقة · صفقة
--     جارية · استشارة نشطة) حمايةً للطرفين.
--   • الموظفون لا يحذفون أنفسهم — الإدارة تُنهي التعيين.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.user_delete_own_account(
  p_user_uid uuid,
  p_reason   text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_user   users%ROWTYPE;
  v_blocks TEXT[] := ARRAY[]::TEXT[];
  v_n      INT;
  v_tag    TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  -- الموظفون: إنهاء التعيين قرار إداري لا ذاتي
  IF COALESCE(v_user.role, 0) > 0 THEN
    RAISE EXCEPTION 'STAFF_CANNOT_SELF_DELETE';
  END IF;

  -- ── الموانع: التزامات قائمة تمنع الحذف حمايةً للطرفين ──
  SELECT COUNT(*) INTO v_n FROM payments WHERE uid = p_user_uid AND sts = 0;
  IF v_n > 0 THEN v_blocks := v_blocks || format('دفعات قيد المراجعة (%s)', v_n); END IF;

  SELECT COUNT(*) INTO v_n FROM deals
  WHERE (buy_uid = p_user_uid OR sell_uid = p_user_uid OR brk_uid = p_user_uid)
    AND COALESCE(sts, 0) = 0 AND COALESCE(i_del, 0) = 0;
  IF v_n > 0 THEN v_blocks := v_blocks || format('صفقات جارية (%s)', v_n); END IF;

  SELECT COUNT(*) INTO v_n FROM legal_consultations
  WHERE user_uid = p_user_uid AND status IN (0, 1, 5) AND COALESCE(i_del, 0) = 0;
  IF v_n > 0 THEN v_blocks := v_blocks || format('استشارات قانونية نشطة (%s)', v_n); END IF;

  SELECT COUNT(*) INTO v_n FROM appointments
  WHERE req_uid = p_user_uid AND sts IN (0, 1);
  IF v_n > 0 THEN v_blocks := v_blocks || format('مواعيد قائمة (%s)', v_n); END IF;

  IF array_length(v_blocks, 1) > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'ACTIVE_OBLIGATIONS',
      'blocks',  v_blocks,
      'detail',  'يتعذّر حذف الحساب قبل إغلاق: ' || array_to_string(v_blocks, ' · ')
    );
  END IF;

  -- وسم فريد يمنع تعارض القيود الفريدة على الهاتف/البريد/اسم المستخدم
  v_tag := 'deleted_' || replace(p_user_uid::text, '-', '');

  -- إخفاء محتوى المستخدم العام
  UPDATE offers   SET i_del = 1, i_pub = 0 WHERE usr_id = p_user_uid AND i_del = 0;
  UPDATE requests SET i_del = 1            WHERE usr_id = p_user_uid AND i_del = 0;

  -- تعمية البيانات الشخصية مع إبقاء الروابط سليمة
  UPDATE users SET
    i_del  = 1,
    sts    = 1,
    nm     = 'حساب محذوف',
    ph     = '+000' || substr(v_tag, 9, 12),
    eml    = NULL,
    usr    = v_tag,
    ad     = '',
    img    = '',
    sid    = '',
    brk_nm = '',
    ts_upd = NOW()
  WHERE id = p_user_uid;

  -- إنهاء كل الجلسات فوراً
  PERFORM public.revoke_all_user_sessions(p_user_uid);

  -- أثر تدقيقي بلا بيانات شخصية
  INSERT INTO activity_log (act, det, ref_id, ref_col, ts_crt)
  VALUES (130, 'حذف حساب ذاتي' ||
          CASE WHEN COALESCE(trim(p_reason), '') <> ''
               THEN ' — ' || left(trim(p_reason), 200) ELSE '' END,
          p_user_uid::TEXT, 'users', NOW());

  RETURN jsonb_build_object('success', true, 'deleted_at', NOW());
END;
$fn$;

REVOKE ALL ON FUNCTION public.user_delete_own_account(uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.user_delete_own_account(uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.user_delete_own_account(uuid, text) TO service_role;
CREATE OR REPLACE FUNCTION public._issue_staff_session(p_user_uid uuid, p_device_id text DEFAULT ''::text, p_ip text DEFAULT ''::text, p_ttl interval DEFAULT '7 days'::interval)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_role INT;
  v_token TEXT;
  v_expires_at TIMESTAMPTZ;
  v_session_id UUID;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_user_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND_OR_INACTIVE';
  END IF;

  -- تسمح لكل الأدوار بإصدار جلسة مخصصة بعد تسجيل دخول صحيح بكلمة المرور.
  -- الصلاحيات الفعلية تضبط لاحقاً عند التحقق عبر p_min_role.
  v_token := encode(gen_random_bytes(32), 'hex');

  -- 🔒 SEC-009 (2026-08-14): مدة الجلسة حسب حساسية الدور.
  -- كانت 7 أيام موحّدة للجميع — بما فيهم المدير الذي يملك المدفوعات
  -- والصلاحيات وحذف الموظفين. جهاز مدير يُفقد أو يُترك مفتوحاً يعني نافذة
  -- أسبوع كاملة بصلاحيات كاملة، والتطبيق يُستخدم على هواتف شخصية ميدانياً.
  -- القاعدة: كلما زادت الصلاحية قصرت المدة.
  --   مستخدم/وسيط (0-1) : 7 أيام — راحة الاستخدام، صلاحياتهم على بياناتهم
  --   ميداني/موظف (2-4) : 3 أيام
  --   نائب/مدير   (5-6) : 24 ساعة — أخطر الأدوار
  --   محامٍ/معقّب (7-8) : 3 أيام — بيانات موكّلين حسّاسة
  -- ⚠️ تُطبَّق فقط حين يستخدم المنادي المهلة الافتراضية؛ أي استدعاء يمرّر
  -- p_ttl صراحةً يبقى محترَماً كما هو.
  IF p_ttl = INTERVAL '7 days' THEN
    v_expires_at := NOW() + CASE
      WHEN v_role BETWEEN 5 AND 6 THEN INTERVAL '24 hours'
      WHEN v_role BETWEEN 2 AND 4 THEN INTERVAL '3 days'
      WHEN v_role >= 7            THEN INTERVAL '3 days'
      ELSE INTERVAL '7 days'
    END;
  ELSE
    v_expires_at := NOW() + p_ttl;
  END IF;

  INSERT INTO public.staff_sessions (
    user_id,
    token_hash,
    role_snapshot,
    device_id,
    ip,
    expires_at
  ) VALUES (
    p_user_uid,
    crypt(v_token, gen_salt('bf', 8)),
    v_role,
    COALESCE(p_device_id, ''),
    COALESCE(p_ip, ''),
    v_expires_at
  ) RETURNING id INTO v_session_id;

  RETURN jsonb_build_object(
    'success', true,
    'session_id', v_session_id,
    'session_token', v_token,
    'expires_at', v_expires_at,
    'role', v_role
  );
END;
$function$;
