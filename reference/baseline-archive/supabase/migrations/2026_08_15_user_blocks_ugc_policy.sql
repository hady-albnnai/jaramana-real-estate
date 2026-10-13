-- ============================================================================
-- 2026_08_15 — GP-004: حظر المستخدمين (متطلب سياسة UGC في Google Play)
-- ============================================================================
-- سياسة Google Play «User Generated Content» تشترط صراحةً ثلاثة أمور معاً:
--   1) قبول شروط الاستخدام قبل رفع أي محتوى   ✅ موجود (إقرار add_offer)
--   2) نظام تبليغ داخل التطبيق                  ✅ موجود (create_report)
--   3) **وظيفة حظر المستخدمين**                 ❌ كانت غائبة كلياً
-- البند 3 يشتدّ في تطبيقنا لأن فيه تفاعلاً فردياً مباشراً (شات الاستشارات
-- القانونية)، وهو ما تستهدفه السياسة تحديداً.
--
-- التصميم:
--   • الحظر **أحادي الاتجاه ومتماثل الأثر**: إن حظر (أ) الشخص (ب)، يختفي
--     محتوى كلٍّ منهما عن الآخر. هذا يمنع «الالتفاف بالحظر المضاد».
--   • المستخدم لا يعرف `usr_id` لصاحب العرض إطلاقاً (قاعدة المالك +
--     SEC-004: contact_ph/usr_id غير مكشوفين عبر REST)، لذا الحظر يتم
--     **بمعرّف العرض** والسيرفر يستنتج المالك بمفتاح الخدمة.
--   • ممنوع حظر النفس، وممنوع حظر الطاقم (role>=2) — لأن حظر موظف المكتب
--     يعطّل الخدمة على المستخدم نفسه (مواعيد، استشارات، دعم).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.user_blocks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_uid UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_uid UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reason      TEXT NOT NULL DEFAULT '',
  ts_crt      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_blocks_no_self CHECK (blocker_uid <> blocked_uid),
  CONSTRAINT user_blocks_unique  UNIQUE (blocker_uid, blocked_uid)
);

COMMENT ON TABLE public.user_blocks IS
  'GP-004: حظر مستخدم لمستخدم — متطلب سياسة UGC في Google Play. الأثر متماثل.';

-- فهارس الاتجاهين: كل استعلام إخفاء يفحص الطرفين.
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocker ON public.user_blocks (blocker_uid);
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON public.user_blocks (blocked_uid);

-- RLS: الجدول يُقرأ ويُكتب حصراً عبر الدوال الداخلية بمفتاح الخدمة.
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_blocks FROM PUBLIC;
REVOKE ALL ON TABLE public.user_blocks FROM anon, authenticated;
GRANT ALL ON TABLE public.user_blocks TO service_role;

-- ============================================================================
-- block_user_internal — الحظر بمعرّف المستخدم مباشرةً (من الشات)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.block_user_internal(
  p_actor_uid   UUID,
  p_blocked_uid UUID,
  p_reason      TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_actor_ok   BOOLEAN;
  v_tgt_role   INT;
  v_tgt_name   TEXT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  IF p_actor_uid IS NULL OR p_blocked_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'MISSING_REQUIRED_FIELDS');
  END IF;

  IF p_actor_uid = p_blocked_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_BLOCK_SELF');
  END IF;

  SELECT TRUE INTO v_actor_ok FROM users
   WHERE id = p_actor_uid AND i_del = 0 AND sts = 0;
  IF NOT COALESCE(v_actor_ok, FALSE) THEN
    RETURN jsonb_build_object('success', false, 'error', 'ACTOR_NOT_ACTIVE');
  END IF;

  SELECT role, nm INTO v_tgt_role, v_tgt_name FROM users
   WHERE id = p_blocked_uid AND i_del = 0;
  IF v_tgt_role IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TARGET_NOT_FOUND');
  END IF;

  -- حظر الطاقم يعطّل الخدمة على الحاجب نفسه (مواعيد/استشارات/دعم) ⇒ يُمنع
  -- صراحةً بدل أن يكسر تجربته بصمت. التبليغ هو المسار الصحيح ضد موظف.
  IF v_tgt_role >= 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_BLOCK_STAFF');
  END IF;

  INSERT INTO user_blocks (blocker_uid, blocked_uid, reason)
  VALUES (p_actor_uid, p_blocked_uid, COALESCE(LEFT(TRIM(p_reason), 500), ''))
  ON CONFLICT (blocker_uid, blocked_uid) DO NOTHING;

  -- مسار تدقيق: `log_admin_action` مخصّصة للطاقم وتفترض دوراً إدارياً، وهذا
  -- فعل مستخدم عادي ⇒ نكتب في activity_log مباشرةً.
  -- act=130 (حظر) — أعلى كود مستخدَم حالياً 122، فلا تضارب.
  INSERT INTO activity_log (uid, act, det, ref_id, ref_col, i_del, ts_crt)
  VALUES (p_actor_uid, 130,
          'حظر المستخدم: ' || COALESCE(v_tgt_name, ''),
          p_blocked_uid::TEXT, 'users', 0, NOW());

  RETURN jsonb_build_object('success', true, 'blocked_uid', p_blocked_uid);
END;
$function$;

-- ============================================================================
-- block_offer_owner_internal — الحظر بمعرّف العرض
-- ============================================================================
-- الواجهة لا تعرف مالك العرض (SEC-004 يمنع كشف usr_id)، فالسيرفر يستنتجه.
CREATE OR REPLACE FUNCTION public.block_offer_owner_internal(
  p_actor_uid UUID,
  p_offer_id  UUID,
  p_reason    TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_owner UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT usr_id INTO v_owner FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND');
  END IF;

  RETURN public.block_user_internal(p_actor_uid, v_owner, p_reason);
END;
$function$;

-- ============================================================================
-- unblock_user_internal — رفع الحظر
-- ============================================================================
CREATE OR REPLACE FUNCTION public.unblock_user_internal(
  p_actor_uid   UUID,
  p_blocked_uid UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_deleted INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  DELETE FROM user_blocks
   WHERE blocker_uid = p_actor_uid AND blocked_uid = p_blocked_uid;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  IF v_deleted = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'BLOCK_NOT_FOUND');
  END IF;

  -- act=131 (رفع حظر)
  INSERT INTO activity_log (uid, act, det, ref_id, ref_col, i_del, ts_crt)
  VALUES (p_actor_uid, 131, 'رفع الحظر عن مستخدم',
          p_blocked_uid::TEXT, 'users', 0, NOW());

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- ============================================================================
-- list_my_blocks_internal — قائمة المحظورين (لإدارتها ورفع الحظر)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.list_my_blocks_internal(p_actor_uid UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_rows JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'uid',    b.blocked_uid,
           'nm',     COALESCE(NULLIF(u.nm, ''), 'مستخدم'),
           'reason', b.reason,
           'ts',     b.ts_crt
         ) ORDER BY b.ts_crt DESC), '[]'::jsonb)
    INTO v_rows
    FROM user_blocks b
    LEFT JOIN users u ON u.id = b.blocked_uid
   WHERE b.blocker_uid = p_actor_uid;

  RETURN jsonb_build_object('success', true, 'blocks', v_rows);
END;
$function$;

-- ============================================================================
-- get_blocked_offer_ids_internal — العروض التي يجب إخفاؤها عن المستخدم
-- ============================================================================
-- الأثر **متماثل**: تُخفى عروض من حظرتَهم ومن حظروك، وإلا صار الحظر بلا
-- معنى (يكفي أن يحظرك المُسيء ليبقى محتواه ظاهراً لك).
CREATE OR REPLACE FUNCTION public.get_blocked_offer_ids_internal(p_actor_uid UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_ids JSONB;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT COALESCE(jsonb_agg(o.id), '[]'::jsonb) INTO v_ids
    FROM offers o
   WHERE o.i_del = 0
     AND o.usr_id IN (
       SELECT blocked_uid FROM user_blocks WHERE blocker_uid = p_actor_uid
       UNION
       SELECT blocker_uid FROM user_blocks WHERE blocked_uid = p_actor_uid
     );

  RETURN jsonb_build_object('success', true, 'offer_ids', v_ids);
END;
$function$;

-- ============================================================================
-- §7 رباعي التحصين
-- ============================================================================
REVOKE ALL ON FUNCTION public.block_user_internal(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.block_user_internal(uuid, uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.block_user_internal(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.block_offer_owner_internal(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.block_offer_owner_internal(uuid, uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.block_offer_owner_internal(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.unblock_user_internal(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.unblock_user_internal(uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.unblock_user_internal(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.list_my_blocks_internal(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_my_blocks_internal(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.list_my_blocks_internal(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.get_blocked_offer_ids_internal(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_blocked_offer_ids_internal(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_blocked_offer_ids_internal(uuid) TO service_role;
