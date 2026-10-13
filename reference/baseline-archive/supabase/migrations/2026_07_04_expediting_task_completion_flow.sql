-- =====================================================================
-- Migration: 2026_07_04_expediting_task_completion_flow.sql
-- الغرض:
--   إكمال دورة مهمة التعقيب: إشعار المعقب عند إنشاء المهمة، تأكيد إنجاز
--   المعقب للمهمة، إشعار المحامي، ثم اعتماد المحامي للإنجاز وإشعار المعقب.
-- =====================================================================

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

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    p_expediter_uid,
    2,
    'مهمة تعقيب جديدة',
    CASE WHEN p_item_type = 0 THEN 'تم تكليفك بمهمة استخراج ثبوتيات عقار جديدة.' ELSE 'تم تكليفك بمهمة استخراج ثبوتيات مركبة جديدة.' END,
    v_task_id::text,
    'expediting_task_assigned',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'task_id', v_task_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.update_expediting_checklist_item(
  p_actor_uid uuid,
  p_task_id uuid,
  p_item_key text,
  p_status integer,
  p_input_value text DEFAULT '',
  p_attachment_url text DEFAULT '',
  p_notes text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_new_checklist jsonb := '[]'::jsonb;
  v_item jsonb;
  v_found boolean := false;
BEGIN
  IF p_actor_uid IS NULL THEN
    RAISE EXCEPTION 'USER_UID_REQUIRED';
  END IF;

  IF p_status NOT IN (0, 1, 2, 3) THEN
    RAISE EXCEPTION 'INVALID_STATUS';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.expediter_uid <> p_actor_uid AND v_task.lawyer_uid <> p_actor_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_ALREADY_APPROVED');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_task.checklist)
  LOOP
    IF v_item->>'key' = p_item_key THEN
      v_found := true;
      v_item := jsonb_set(v_item, '{status}', to_jsonb(p_status));
      IF COALESCE(p_input_value, '') <> '' THEN v_item := jsonb_set(v_item, '{input_value}', to_jsonb(p_input_value)); END IF;
      IF COALESCE(p_attachment_url, '') <> '' THEN v_item := jsonb_set(v_item, '{attachment_url}', to_jsonb(p_attachment_url)); END IF;
      IF COALESCE(p_notes, '') <> '' THEN v_item := jsonb_set(v_item, '{notes}', to_jsonb(p_notes)); END IF;
    END IF;
    v_new_checklist := v_new_checklist || v_item;
  END LOOP;

  IF NOT v_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  UPDATE public.expediting_tasks
  SET checklist = v_new_checklist,
      status = CASE WHEN status < 2 AND p_status IN (1, 2, 3) THEN 1 ELSE status END
  WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'checklist', v_new_checklist);
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_expediting_task_internal(
  p_expediter_uid uuid,
  p_task_id uuid,
  p_notes text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_expediter_role int;
  v_incomplete int;
BEGIN
  SELECT role INTO v_expediter_role
  FROM public.users
  WHERE id = p_expediter_uid AND i_del = 0 AND sts = 0;

  IF v_expediter_role <> 8 THEN
    RAISE EXCEPTION 'EXPEDITER_ROLE_REQUIRED';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.expediter_uid <> p_expediter_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_ALREADY_APPROVED');
  END IF;

  IF v_task.status = 2 THEN
    RETURN jsonb_build_object('success', true, 'already_completed', true);
  END IF;

  SELECT COUNT(*) INTO v_incomplete
  FROM jsonb_array_elements(v_task.checklist) item
  WHERE COALESCE((item->>'status')::int, 0) <> 2;

  IF v_incomplete > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CHECKLIST_NOT_COMPLETE', 'incomplete_count', v_incomplete);
  END IF;

  UPDATE public.expediting_tasks
  SET status = 2,
      completed_at = NOW(),
      expediter_notes = COALESCE(p_notes, expediter_notes)
  WHERE id = p_task_id;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    v_task.lawyer_uid,
    2,
    'مهمة تعقيب مكتملة',
    'أتم المعقب مهمة التعقيب بنجاح وهي بانتظار اعتمادك.',
    p_task_id::text,
    'expediting_task_completed',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'status', 2);
END;
$$;

CREATE OR REPLACE FUNCTION public.approve_expediting_task_internal(
  p_lawyer_uid uuid,
  p_task_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_lawyer_role int;
BEGIN
  SELECT role INTO v_lawyer_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_lawyer_role <> 7 THEN
    RAISE EXCEPTION 'LAWYER_ROLE_REQUIRED';
  END IF;

  SELECT * INTO v_task
  FROM public.expediting_tasks
  WHERE id = p_task_id
  FOR UPDATE;

  IF v_task IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_FOUND');
  END IF;

  IF v_task.lawyer_uid <> p_lawyer_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_AUTHORIZED');
  END IF;

  IF v_task.status = 3 THEN
    RETURN jsonb_build_object('success', true, 'already_approved', true);
  END IF;

  IF v_task.status <> 2 THEN
    RETURN jsonb_build_object('success', false, 'error', 'TASK_NOT_COMPLETED_BY_EXPEDITER');
  END IF;

  UPDATE public.expediting_tasks
  SET status = 3
  WHERE id = p_task_id;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    v_task.expediter_uid,
    2,
    'تم اعتماد مهمة التعقيب',
    'اعتمد المحامي مهمة التعقيب المكتملة. شكراً لجهودك.',
    p_task_id::text,
    'expediting_task_approved',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'status', 3);
END;
$$;

REVOKE ALL ON FUNCTION public.create_expediting_task_internal(uuid, uuid, integer, text, text, text, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_expediting_task_internal(uuid, uuid, integer, text, text, text, jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.complete_expediting_task_internal(uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.complete_expediting_task_internal(uuid, uuid, text) TO service_role;

REVOKE ALL ON FUNCTION public.approve_expediting_task_internal(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_expediting_task_internal(uuid, uuid) TO service_role;
