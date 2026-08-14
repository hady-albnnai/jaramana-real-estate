-- ═══════════════════════════════════════════════════════════════════
-- 2026_08_14_expediter_assignment.sql
-- الفجوة المكتشفة بتقمّص دور المحامي: get_available_expediters تُرجع
-- (id, nm, ph) فقط ⇒ **المحامي يختار معقّباً أعمى** فقد يكدّس 10 مهام على
-- واحد وزميله فارغ. لا مؤشر انشغال ولا ترتيب ولا اقتراح.
-- القرار: نفس أسس إسناد المحامين — الأقل انشغالاً ← الدور (الأقدم).
-- ═══════════════════════════════════════════════════════════════════

-- ① قائمة المعقّبين مع عدد المهام النشطة، مرتّبة بالأقل انشغالاً
CREATE OR REPLACE FUNCTION public.get_available_expediters()
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', u.id,
    'nm', u.nm,
    'ph', u.ph,
    -- المهام غير المنتهية (0 بانتظار · 1 قيد الاستخراج · 2 بانتظار المراجعة)
    'active_tasks', COALESCE(t.cnt, 0),
    'is_least_busy', COALESCE(t.cnt, 0) = (
        SELECT MIN(COALESCE(t2.cnt, 0))
        FROM public.users u2
        LEFT JOIN (
          SELECT expediter_uid, COUNT(*) cnt FROM public.expediting_tasks
           WHERE status IN (0, 1, 2) GROUP BY expediter_uid
        ) t2 ON t2.expediter_uid = u2.id
        WHERE u2.role = 8 AND u2.sts = 0 AND u2.i_del = 0
      )
  )
  FROM public.users u
  LEFT JOIN (
    SELECT expediter_uid, COUNT(*) cnt FROM public.expediting_tasks
     WHERE status IN (0, 1, 2) GROUP BY expediter_uid
  ) t ON t.expediter_uid = u.id
  WHERE u.role = 8 AND u.sts = 0 AND u.i_del = 0
  ORDER BY COALESCE(t.cnt, 0) ASC, u.ts_crt ASC NULLS LAST, u.nm ASC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_available_expediters() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_available_expediters() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_available_expediters() TO service_role;

-- ② المعقّب التالي بالدور (نفس مبدأ pick_next_lawyer)
CREATE OR REPLACE FUNCTION public.pick_next_expediter(p_exclude uuid[] DEFAULT '{}')
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  SELECT u.id
  FROM public.users u
  LEFT JOIN (
    SELECT expediter_uid, COUNT(*) cnt FROM public.expediting_tasks
     WHERE status IN (0, 1, 2) GROUP BY expediter_uid
  ) t ON t.expediter_uid = u.id
  WHERE u.role = 8 AND u.sts = 0 AND u.i_del = 0
    AND NOT (u.id = ANY(COALESCE(p_exclude, '{}')))
  ORDER BY COALESCE(t.cnt, 0) ASC, u.ts_crt ASC NULLS LAST
  LIMIT 1;
$function$;

REVOKE ALL ON FUNCTION public.pick_next_expediter(uuid[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.pick_next_expediter(uuid[]) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pick_next_expediter(uuid[]) TO service_role;
