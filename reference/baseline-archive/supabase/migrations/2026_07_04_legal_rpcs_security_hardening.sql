-- =====================================================================
-- Migration: 2026_07_04_legal_rpcs_security_hardening.sql
-- الغرض:
--   تحصين دوال القسم القانوني والتعقيب التي أضيفت مؤخراً حتى لا تبقى
--   SECURITY DEFINER قابلة للتنفيذ مباشرة من anon/authenticated.
--   الوصول الرسمي يكون فقط عبر Edge Function: legal-actions.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.admin_upsert_lawyer_profile(
  p_admin_uid uuid,
  p_target_uid uuid,
  p_whatsapp text,
  p_address text DEFAULT '',
  p_spec text DEFAULT 'عقارات وسيارات',
  p_avl jsonb DEFAULT '{}'::jsonb
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_actor_role int;
  v_target_role int;
BEGIN
  IF p_admin_uid IS NULL OR p_target_uid IS NULL THEN
    RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS';
  END IF;

  IF COALESCE(TRIM(p_whatsapp), '') = '' THEN
    RAISE EXCEPTION 'WHATSAPP_REQUIRED';
  END IF;

  SELECT role INTO v_actor_role
  FROM public.users
  WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;

  IF v_actor_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND_OR_INACTIVE';
  END IF;

  SELECT role INTO v_target_role
  FROM public.users
  WHERE id = p_target_uid AND i_del = 0 AND sts = 0;

  IF v_target_role IS NULL THEN
    RAISE EXCEPTION 'TARGET_USER_NOT_FOUND_OR_INACTIVE';
  END IF;

  -- إدارة ملفات المحامين:
  -- 1) المحامي role=7 يعدّل ملفه فقط.
  -- 2) نائب المدير/المدير فقط role IN (5,6) يعدّلان ملف محامٍ موجود.
  -- 3) لا ترقية أدوار من هذه الدالة؛ تغيير الدور يتم حصراً من إدارة الموظفين.
  IF p_admin_uid = p_target_uid THEN
    IF v_actor_role <> 7 AND v_actor_role NOT IN (5, 6) THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  ELSE
    IF v_actor_role NOT IN (5, 6) THEN
      RAISE EXCEPTION 'NOT_AUTHORIZED';
    END IF;
  END IF;

  IF v_target_role <> 7 THEN
    RAISE EXCEPTION 'TARGET_NOT_LAWYER';
  END IF;

  INSERT INTO public.lawyer_profiles (uid, whatsapp_phone, office_address, specialization, avl, is_active, updated_at)
  VALUES (p_target_uid, TRIM(p_whatsapp), COALESCE(p_address, ''), COALESCE(p_spec, 'عقارات وسيارات'), COALESCE(p_avl, '{}'::jsonb), TRUE, NOW())
  ON CONFLICT (uid) DO UPDATE
  SET whatsapp_phone = EXCLUDED.whatsapp_phone,
      office_address = EXCLUDED.office_address,
      specialization = EXCLUDED.specialization,
      avl = EXCLUDED.avl,
      is_active = TRUE,
      updated_at = NOW();

  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_expediting_task_internal(
  p_lawyer_uid uuid,
  p_expediter_uid uuid,
  p_item_type integer,
  p_target_property_num text DEFAULT '',
  p_target_zone text DEFAULT '',
  p_lawyer_notes text DEFAULT '',
  p_checklist jsonb DEFAULT '[]'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task_id uuid;
  v_default_checklist jsonb;
  v_lawyer_role int;
  v_expediter_role int;
BEGIN
  IF p_lawyer_uid IS NULL OR p_expediter_uid IS NULL THEN
    RAISE EXCEPTION 'MISSING_REQUIRED_FIELDS';
  END IF;

  SELECT role INTO v_lawyer_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_lawyer_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  SELECT role INTO v_expediter_role
  FROM public.users
  WHERE id = p_expediter_uid AND i_del = 0 AND sts = 0;

  IF v_expediter_role <> 8 THEN
    RAISE EXCEPTION 'EXPEDITER_ROLE_REQUIRED';
  END IF;

  IF p_item_type NOT IN (0, 1) THEN
    RAISE EXCEPTION 'INVALID_ITEM_TYPE';
  END IF;

  IF p_checklist IS NULL OR p_checklist = '[]'::jsonb THEN
    IF p_item_type = 0 THEN
      v_default_checklist := '[
        {"key": "extract", "title": "إخراج قيد عقاري حديث", "status": 0},
        {"key": "area_stmt", "title": "بيان مساحة عقاري", "status": 0},
        {"key": "fin_clearance", "title": "براءة ذمة مالية وبلدية", "status": 0},
        {"key": "fin_record", "title": "قيد مالي للعقار", "status": 0},
        {"key": "sales_tax", "title": "ضريبة البيوع العقارية", "status": 0},
        {"key": "poa_chain", "title": "تسلسل وكالات كاتب بالعدل", "status": 0}
      ]'::jsonb;
    ELSE
      v_default_checklist := '[
        {"key": "traffic_info", "title": "كشف اطلاع مروري", "status": 0},
        {"key": "traffic_clearance", "title": "براءة ذمة مرورية ومخالفات", "status": 0},
        {"key": "tech_inspect", "title": "كشف فني ومطابقة الأرقام", "status": 0},
        {"key": "title_deed", "title": "سند الملكية / ميكانيك المركبة", "status": 0}
      ]'::jsonb;
    END IF;
  ELSE
    v_default_checklist := p_checklist;
  END IF;

  INSERT INTO public.expediting_tasks (
    lawyer_uid, expediter_uid, item_type,
    target_property_num, target_zone,
    checklist, status, lawyer_notes, created_at
  ) VALUES (
    p_lawyer_uid, p_expediter_uid, p_item_type,
    COALESCE(p_target_property_num, ''), COALESCE(p_target_zone, ''),
    v_default_checklist, 0, COALESCE(p_lawyer_notes, ''), NOW()
  ) RETURNING id INTO v_task_id;

  RETURN jsonb_build_object('success', true, 'task_id', v_task_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_lawyer_profile(p_lawyer_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_profile jsonb;
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  SELECT jsonb_build_object(
    'uid', lp.uid,
    'whatsapp_phone', lp.whatsapp_phone,
    'office_address', lp.office_address,
    'specialization', lp.specialization,
    'avl', lp.avl,
    'is_active', lp.is_active
  ) INTO v_profile
  FROM public.lawyer_profiles lp
  WHERE lp.uid = p_lawyer_uid;

  IF v_profile IS NULL THEN
    RETURN jsonb_build_object('found', false);
  END IF;
  RETURN v_profile || jsonb_build_object('found', true);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_lawyer_expediting_tasks(p_lawyer_uid uuid)
RETURNS SETOF public.expediting_tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.expediting_tasks
  WHERE lawyer_uid = p_lawyer_uid
  ORDER BY created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_lawyer_appointments(p_lawyer_uid uuid)
RETURNS TABLE(id uuid, client_name text, client_phone text, dt timestamptz, sts integer, notes text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    COALESCE(u.nm, '') AS client_name,
    COALESCE(u.ph, '') AS client_phone,
    a.dt,
    a.sts,
    COALESCE(a.note, '') AS notes
  FROM public.appointments a
  JOIN public.users u ON u.id = a.req_uid
  WHERE a.bkr_id = p_lawyer_uid
  ORDER BY a.dt DESC;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_expediting_tasks(p_expediter_uid uuid)
RETURNS SETOF public.expediting_tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_role int;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_expediter_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 8 THEN
    RAISE EXCEPTION 'EXPEDITER_ROLE_REQUIRED';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.expediting_tasks
  WHERE expediter_uid = p_expediter_uid
  ORDER BY created_at DESC;
END;
$$;

-- لا تحتاج إلى actor arg لأنها تُستدعى فقط من legal-actions بعد التحقق من role=7/5/6.
CREATE OR REPLACE FUNCTION public.get_available_expediters()
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT jsonb_build_object(
    'id', u.id,
    'nm', u.nm,
    'ph', u.ph
  )
  FROM public.users u
  WHERE u.role = 8 AND u.sts = 0 AND u.i_del = 0
  ORDER BY u.nm;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_upsert_lawyer_profile(uuid, uuid, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_lawyer_profile(uuid, uuid, text, text, text, jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.create_expediting_task_internal(uuid, uuid, integer, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_expediting_task_internal(uuid, uuid, integer, text, text, text, jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.get_available_expediters() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_available_expediters() TO service_role;

REVOKE ALL ON FUNCTION public.get_lawyer_appointments(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_lawyer_appointments(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.get_lawyer_expediting_tasks(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_lawyer_expediting_tasks(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.get_lawyer_profile(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_lawyer_profile(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.get_my_expediting_tasks(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_expediting_tasks(uuid) TO service_role;
