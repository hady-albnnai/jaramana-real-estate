-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — مزامنة الريبو مع الحقيقة الحية (إقفال الدَّين 5)
--
-- الفحص الحي (لقطة الانحراف + drift_markers) أثبت أن هاتين الدالتين
-- حيتان ومستخدَمتان في كل مسارات الاستشارة بينما تعريفهما غير موجود
-- بأي ملف بالريبو (انحراف سيرفر) — نُسختا هنا حرفياً من التعريف الحي
-- لتطابق الريبو مع السيرفر. CREATE OR REPLACE = idempotent.
-- ══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.lawyer_alias_for(p_lawyer_uid uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_rank INT;
  v_ord  TEXT[] := ARRAY['','الأول','الثاني','الثالث','الرابع','الخامس','السادس','السابع','الثامن','التاسع','العاشر'];
BEGIN
  IF p_lawyer_uid IS NULL THEN RETURN NULL; END IF;
  SELECT r INTO v_rank FROM (
    SELECT uid, ROW_NUMBER() OVER (ORDER BY created_at ASC) AS r
    FROM lawyer_profiles
  ) t WHERE t.uid = p_lawyer_uid;
  IF v_rank IS NULL THEN RETURN 'محامي المكتب'; END IF;
  RETURN 'محامي المكتب ' || COALESCE(v_ord[v_rank + 1], v_rank::text);
END;
$function$;

REVOKE ALL ON FUNCTION public.lawyer_alias_for(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.lawyer_alias_for(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lawyer_alias_for(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.update_lawyer_active_tasks(p_lawyer_uid uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM legal_consultations
  WHERE lawyer_uid = p_lawyer_uid
    AND status IN (0, 1)
    AND i_del = 0;

  UPDATE lawyer_profiles
  SET active_tasks_count = v_count, updated_at = NOW()
  WHERE uid = p_lawyer_uid;
END;
$function$;

REVOKE ALL ON FUNCTION public.update_lawyer_active_tasks(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_lawyer_active_tasks(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_lawyer_active_tasks(uuid) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج: repo_sync_patched = true ⇒ الدالتان موجودتان بالريبو
-- ──────────────────────────────────────────────────────────────────────
SELECT
  (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='lawyer_alias_for')) AS lawyer_alias_for_exists,
  (SELECT EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='update_lawyer_active_tasks')) AS update_lawyer_active_tasks_exists;
