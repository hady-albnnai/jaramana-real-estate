-- ============================================================================
-- 2026_08_15 — BRK-001: طلب الوساطة يُفعَّل فوراً بلا أي مراجعة إدارية
-- ============================================================================
-- بلاغ المالك: «أرسلت طلباً لأصبح وسيطاً من حساب هناء فأصبحت وسيطاً
-- مباشرة. يجب التحقق من بيانات طالب الوساطة من قبل الإدارة، وأثناء ذلك
-- يظهر لدى المستخدم: طلبك قيد المراجعة. وعند الموافقة يصبح وسيطاً».
--
-- السبب الجذري في `submit_broker_request_internal`:
--     IF v_vrf = 2 THEN
--       UPDATE users SET role = 1, brk = 1 ...   ← تفعيل فوري!
-- أي أن **كل مستخدم موثَّق** يصير وسيطاً بضغطة زر بلا مراجعة أحد.
-- الخطورة: دور الوسيط يمنح صلاحيات أوسع (5 عروض بدل 1، لوحة وسيط،
-- عمولات، إدارة مواعيد) ⇒ منحه تلقائياً خلل تجاري وأمني معاً.
-- والأسوأ: **لا توجد أي دالة مراجعة في المشروع كله** — الميزة ناقصة.
--
-- التصميم الجديد (حالة الطلب في users.brk):
--   brk = 0 ⇒ ليس وسيطاً ولا طلب له
--   brk = 1 ⇒ **وسيط معتمد** (لا تتغير دلالتها — توافق خلفي مع كل الكود)
--   brk = 2 ⇒ 🆕 **طلب قيد المراجعة** (role يبقى 0 حتى الموافقة)
--   brk = 3 ⇒ 🆕 طلب مرفوض (مع السبب في brk_rsn)
--
-- ⚠️ اخترنا التوسّع في `brk` لا عموداً جديداً لأن كل الكود القائم يفحص
--    `brk = 1` تحديداً، فلا ينكسر شيء: من حالته 2 أو 3 ليس وسيطاً.
-- ============================================================================

-- عمود سبب الرفض (اختياري)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS brk_rsn TEXT;

-- ⚠️ القيد القائم كان CHECK (brk IN (0,1)) ⇒ يرفض الحالتين الجديدتين
-- ويُفشل كل طلب وساطة. توسيعه شرط لعمل الميزة.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_brk_check;
ALTER TABLE public.users
  ADD CONSTRAINT users_brk_check CHECK (brk = ANY (ARRAY[0, 1, 2, 3]));

-- ============================================================================
-- ① تقديم الطلب — يسجّل «قيد المراجعة» ولا يمنح الدور
-- ============================================================================
CREATE OR REPLACE FUNCTION public.submit_broker_request_internal(
  p_user_uid      uuid,
  p_business_name text,
  p_category      integer,
  p_experience    text DEFAULT ''::text,
  p_about         text DEFAULT ''::text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_vrf  INT;
  v_brk  INT;
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  IF COALESCE(TRIM(p_business_name), '') = '' THEN
    RAISE EXCEPTION 'BUSINESS_NAME_REQUIRED';
  END IF;

  SELECT vrf, COALESCE(brk, 0), role
    INTO v_vrf, v_brk, v_role
    FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v_vrf IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  -- التوثيق شرط مسبق (كما كان)
  IF v_vrf < 2 THEN
    RAISE EXCEPTION 'IDENTITY_NOT_VERIFIED';
  END IF;

  -- 🔒 BRK-001: لا تكرار للطلب ولا تقديم من وسيط قائم
  IF v_brk = 1 OR v_role = 1 THEN
    RAISE EXCEPTION 'ALREADY_BROKER';
  END IF;
  IF v_brk = 2 THEN
    RAISE EXCEPTION 'BROKER_REQUEST_PENDING';
  END IF;

  -- حفظ البيانات ووضع الطلب **قيد المراجعة** — بلا منح الدور
  UPDATE users
     SET brk_nm  = TRIM(p_business_name),
         brk_cls = COALESCE(p_category, 0),
         brk     = 2,       -- قيد المراجعة
         brk_rsn = NULL,    -- تصفير سبب رفض سابق
         ts_upd  = NOW()
   WHERE id = p_user_uid AND i_del = 0;

  -- إشعار المستخدم بأن طلبه قيد المراجعة
  INSERT INTO notifications (uid, tp, ttl, bdy, act, i_rd, i_del, ts_crt)
  VALUES (
    p_user_uid, 4,
    '⏳ طلب الوساطة قيد المراجعة',
    'استلمنا طلبك للانضمام كوسيط باسم «' || TRIM(p_business_name) ||
      '». يراجع فريق المكتب بياناتك وسيصلك الرد قريباً.',
    'broker_request_pending', 0, 0, NOW()
  );

  -- إشعار الإدارة (role >= 5) بوجود طلب جديد
  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
  SELECT u.id, 4,
         '🤝 طلب انضمام وسيط جديد',
         COALESCE((SELECT nm FROM users WHERE id = p_user_uid), 'مستخدم') ||
           ' يطلب الانضمام كوسيط باسم «' || TRIM(p_business_name) || '»',
         p_user_uid::TEXT, 'broker_request_new', 0, 0, NOW()
    FROM users u
   WHERE u.role >= 5 AND u.sts = 0 AND u.i_del = 0;

  INSERT INTO activity_log (uid, act, det, ref_id, ref_col, i_del, ts_crt)
  VALUES (p_user_uid, 4,
          'broker_request: ' || TRIM(p_business_name) ||
            ' cat=' || COALESCE(p_category::TEXT, '0') ||
            CASE WHEN COALESCE(TRIM(p_experience), '') <> ''
                 THEN ' exp=' || p_experience ELSE '' END,
          p_user_uid::TEXT, 'users', 0, NOW());

  RETURN TRUE;
END;
$function$;

-- ============================================================================
-- ② مراجعة الطلب — الإدارة تقبل أو ترفض (كانت غائبة كلياً)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_review_broker_request_internal(
  p_admin_uid  uuid,
  p_target_uid uuid,
  p_approve    boolean,
  p_reason     text DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role   INT;
  v_brk    INT;
  v_nm     TEXT;
  v_brk_nm TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  -- مراجعة طلبات الوساطة: موظف مكتب فأعلى (role >= 4)
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT COALESCE(brk, 0), nm, brk_nm
    INTO v_brk, v_nm, v_brk_nm
    FROM users WHERE id = p_target_uid AND i_del = 0;
  IF v_brk IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_NOT_FOUND');
  END IF;

  -- §13: لا نجاح كاذب — لا بتّ إلا في طلب قائم فعلاً
  IF v_brk <> 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_PENDING_BROKER_REQUEST');
  END IF;

  IF p_approve THEN
    UPDATE users
       SET brk = 1, role = 1, brk_rsn = NULL, ts_upd = NOW()
     WHERE id = p_target_uid;

    INSERT INTO notifications (uid, tp, ttl, bdy, act, i_rd, i_del, ts_crt)
    VALUES (p_target_uid, 4,
            '🎉 تم قبولك كوسيط',
            'تهانينا! اعتُمد حسابك كوسيط عقاري باسم «' || COALESCE(v_brk_nm, '') ||
              '». افتح لوحة الوسيط من حسابك.',
            'broker_request_approved', 0, 0, NOW());
  ELSE
    IF COALESCE(TRIM(p_reason), '') = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'REJECTION_REASON_REQUIRED');
    END IF;

    UPDATE users
       SET brk = 3, brk_rsn = TRIM(p_reason), ts_upd = NOW()
     WHERE id = p_target_uid;

    INSERT INTO notifications (uid, tp, ttl, bdy, act, i_rd, i_del, ts_crt)
    VALUES (p_target_uid, 4,
            '❌ لم يُقبل طلب الوساطة',
            'السبب: ' || TRIM(p_reason) || E'\n' ||
              'يمكنك تعديل بياناتك وإعادة التقديم.',
            'broker_request_rejected', 0, 0, NOW());
  END IF;

  PERFORM public.log_admin_action(
    p_admin_uid, 120,
    CASE WHEN p_approve THEN 'قبول طلب وساطة' ELSE 'رفض طلب وساطة' END ||
      ' — ' || COALESCE(v_nm, ''),
    p_target_uid::TEXT, 'users');

  RETURN jsonb_build_object('success', true, 'approved', p_approve);
END;
$function$;

-- ============================================================================
-- ③ قائمة الطلبات المعلّقة للإدارة
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_pending_broker_requests_internal(p_admin_uid uuid)
RETURNS JSONB
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
  v_rows JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'uid', u.id, 'nm', u.nm, 'ph', u.ph, 'sid', u.sid,
           'brk_nm', u.brk_nm, 'brk_cls', u.brk_cls,
           'vrf', u.vrf, 'ts_upd', u.ts_upd
         ) ORDER BY u.ts_upd DESC), '[]'::jsonb)
    INTO v_rows
    FROM users u
   WHERE u.brk = 2 AND u.i_del = 0;

  RETURN jsonb_build_object('success', true, 'requests', v_rows);
END;
$function$;

-- ============================================================================
-- §7 رباعي التحصين
-- ============================================================================
REVOKE ALL ON FUNCTION public.submit_broker_request_internal(uuid, text, integer, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_broker_request_internal(uuid, text, integer, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_broker_request_internal(uuid, text, integer, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.admin_review_broker_request_internal(uuid, uuid, boolean, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_review_broker_request_internal(uuid, uuid, boolean, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_broker_request_internal(uuid, uuid, boolean, text) TO service_role;

REVOKE ALL ON FUNCTION public.get_pending_broker_requests_internal(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_pending_broker_requests_internal(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_broker_requests_internal(uuid) TO service_role;

-- ============================================================================
-- ④ إعادة هناء لحالتها الأصلية (بطلب المالك لإعادة التجربة)
-- ============================================================================
UPDATE users
   SET role = 0, brk = 0, brk_nm = NULL, brk_cls = 0, brk_rsn = NULL, ts_upd = NOW()
 WHERE id = '99703882-2ff5-46ba-ad2f-1a3262c02eb2';
