-- =====================================================================
-- Migration: 2026_07_05_expediting_documents_review_flow.sql
-- الغرض:
--   رفع صور سندات/وثائق التعقيب إلى bucket خاص، وتمكين المحامي من طلب
--   إعادة إنجاز بند محدد إذا كان غير صحيح، مع إشعار المعقب.
-- =====================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('expediting_docs', 'expediting_docs', false)
ON CONFLICT (id) DO UPDATE SET public = false;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname = 'expediting_docs_service_role_all'
  ) THEN
    CREATE POLICY expediting_docs_service_role_all
    ON storage.objects
    FOR ALL TO service_role
    USING (bucket_id = 'expediting_docs')
    WITH CHECK (bucket_id = 'expediting_docs');
  END IF;
END $$;

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
      IF COALESCE(p_input_value, '') <> '' THEN
        v_item := jsonb_set(v_item, '{input_value}', to_jsonb(p_input_value));
      END IF;
      IF COALESCE(p_attachment_url, '') <> '' THEN
        v_item := jsonb_set(v_item, '{attachment_url}', to_jsonb(p_attachment_url));
      END IF;
      IF COALESCE(p_notes, '') <> '' THEN
        v_item := jsonb_set(v_item, '{notes}', to_jsonb(p_notes));
      END IF;
    END IF;
    v_new_checklist := v_new_checklist || v_item;
  END LOOP;

  IF NOT v_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  UPDATE public.expediting_tasks
  SET checklist = v_new_checklist,
      status = CASE
        WHEN p_status IN (0, 1, 3) THEN 1
        WHEN status < 2 AND p_status = 2 THEN 1
        ELSE status
      END,
      completed_at = CASE WHEN p_status IN (0, 1, 3) THEN NULL ELSE completed_at END
  WHERE id = p_task_id;

  RETURN jsonb_build_object('success', true, 'checklist', v_new_checklist);
END;
$$;

CREATE OR REPLACE FUNCTION public.request_expediting_item_revision_internal(
  p_lawyer_uid uuid,
  p_task_id uuid,
  p_item_key text,
  p_revision_notes text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_task record;
  v_role int;
  v_new_checklist jsonb := '[]'::jsonb;
  v_item jsonb;
  v_found boolean := false;
  v_item_title text := '';
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;

  IF v_role <> 7 THEN
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
    RETURN jsonb_build_object('success', false, 'error', 'TASK_ALREADY_APPROVED');
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(v_task.checklist)
  LOOP
    IF v_item->>'key' = p_item_key THEN
      v_found := true;
      v_item_title := COALESCE(v_item->>'title', 'وثيقة');
      v_item := jsonb_set(v_item, '{status}', to_jsonb(1));
      v_item := jsonb_set(v_item, '{revision_notes}', to_jsonb(COALESCE(p_revision_notes, '')));
    END IF;
    v_new_checklist := v_new_checklist || v_item;
  END LOOP;

  IF NOT v_found THEN
    RETURN jsonb_build_object('success', false, 'error', 'ITEM_NOT_FOUND');
  END IF;

  UPDATE public.expediting_tasks
  SET checklist = v_new_checklist,
      status = 1,
      completed_at = NULL
  WHERE id = p_task_id;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (
    v_task.expediter_uid,
    2,
    'إعادة تدقيق وثيقة تعقيب',
    'طلب المحامي إعادة إنجاز/تصحيح: ' || v_item_title,
    p_task_id::text,
    'expediting_item_revision_requested',
    NOW()
  );

  RETURN jsonb_build_object('success', true, 'status', 1, 'item_key', p_item_key);
END;
$$;

REVOKE ALL ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_expediting_checklist_item(uuid, uuid, text, integer, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.request_expediting_item_revision_internal(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.request_expediting_item_revision_internal(uuid, uuid, text, text) TO service_role;
