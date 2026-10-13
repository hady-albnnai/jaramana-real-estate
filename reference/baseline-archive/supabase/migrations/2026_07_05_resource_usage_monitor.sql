-- =====================================================================
-- Migration: 2026_07_05_resource_usage_monitor.sql
-- الغرض:
--   توفير RPC محصنة لإعطاء الإدارة قياسات دقيقة لحجم قاعدة البيانات
--   وحجم Storage حسب كل bucket. قياس Bandwidth/egress الحقيقي يتطلب
--   Supabase Dashboard/Management API، لذلك نعيد ملاحظة صريحة بهذا الخصوص.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_resource_usage_internal(p_admin_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage, extensions, pg_catalog, pg_temp
AS $$
DECLARE
  v_role int;
  v_db_bytes bigint := 0;
  v_public_schema_bytes bigint := 0;
  v_storage_schema_bytes bigint := 0;
  v_table_stats jsonb := '[]'::jsonb;
  v_bucket_stats jsonb := '[]'::jsonb;
  v_storage_total_bytes bigint := 0;
  v_storage_total_files bigint := 0;
  v_storage_month_bytes bigint := 0;
  v_storage_month_files bigint := 0;
  v_object_type_stats jsonb := '[]'::jsonb;
BEGIN
  SELECT role INTO v_role
  FROM public.users
  WHERE id = p_admin_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role NOT IN (4, 5, 6) THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT pg_database_size(current_database()) INTO v_db_bytes;

  SELECT COALESCE(SUM(pg_total_relation_size(c.oid)), 0)::bigint
  INTO v_public_schema_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relkind IN ('r', 'p', 'm');

  SELECT COALESCE(SUM(pg_total_relation_size(c.oid)), 0)::bigint
  INTO v_storage_schema_bytes
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'storage'
    AND c.relkind IN ('r', 'p', 'm');

  SELECT COALESCE(jsonb_agg(row_data ORDER BY (row_data->>'total_bytes')::bigint DESC), '[]'::jsonb)
  INTO v_table_stats
  FROM (
    SELECT jsonb_build_object(
      'schema', n.nspname,
      'table', c.relname,
      'total_bytes', pg_total_relation_size(c.oid),
      'table_bytes', pg_relation_size(c.oid),
      'index_bytes', pg_indexes_size(c.oid),
      'row_estimate', GREATEST(c.reltuples::bigint, 0)
    ) AS row_data
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'storage')
      AND c.relkind IN ('r', 'p', 'm')
    ORDER BY pg_total_relation_size(c.oid) DESC
    LIMIT 25
  ) s;

  WITH object_sizes AS (
    SELECT
      b.id AS bucket_id,
      b.public AS is_public,
      o.id AS object_id,
      o.created_at,
      COALESCE(o.metadata->>'mimetype', 'unknown') AS mimetype,
      CASE
        WHEN o.metadata ? 'size' AND (o.metadata->>'size') ~ '^[0-9]+$' THEN (o.metadata->>'size')::bigint
        WHEN o.metadata ? 'contentLength' AND (o.metadata->>'contentLength') ~ '^[0-9]+$' THEN (o.metadata->>'contentLength')::bigint
        ELSE 0
      END AS bytes
    FROM storage.buckets b
    LEFT JOIN storage.objects o ON o.bucket_id = b.id
  ), bucket_rows AS (
    SELECT
      bucket_id,
      is_public,
      COUNT(object_id)::bigint AS file_count,
      COALESCE(SUM(bytes), 0)::bigint AS total_bytes,
      COALESCE(AVG(bytes), 0)::bigint AS avg_bytes,
      COALESCE(MAX(bytes), 0)::bigint AS largest_bytes,
      COALESCE(SUM(bytes) FILTER (WHERE created_at >= date_trunc('month', now())), 0)::bigint AS current_month_uploaded_bytes,
      COUNT(object_id) FILTER (WHERE created_at >= date_trunc('month', now()))::bigint AS current_month_uploaded_files,
      MAX(created_at) AS last_upload_at
    FROM object_sizes
    GROUP BY bucket_id, is_public
  )
  SELECT
    COALESCE(SUM(total_bytes), 0)::bigint,
    COALESCE(SUM(file_count), 0)::bigint,
    COALESCE(SUM(current_month_uploaded_bytes), 0)::bigint,
    COALESCE(SUM(current_month_uploaded_files), 0)::bigint,
    COALESCE(jsonb_agg(jsonb_build_object(
      'bucket_id', bucket_id,
      'public', is_public,
      'file_count', file_count,
      'total_bytes', total_bytes,
      'avg_bytes', avg_bytes,
      'largest_bytes', largest_bytes,
      'current_month_uploaded_bytes', current_month_uploaded_bytes,
      'current_month_uploaded_files', current_month_uploaded_files,
      'last_upload_at', last_upload_at
    ) ORDER BY total_bytes DESC), '[]'::jsonb)
  INTO v_storage_total_bytes, v_storage_total_files, v_storage_month_bytes, v_storage_month_files, v_bucket_stats
  FROM bucket_rows;

  WITH object_sizes AS (
    SELECT
      COALESCE(metadata->>'mimetype', 'unknown') AS mimetype,
      CASE
        WHEN metadata ? 'size' AND (metadata->>'size') ~ '^[0-9]+$' THEN (metadata->>'size')::bigint
        WHEN metadata ? 'contentLength' AND (metadata->>'contentLength') ~ '^[0-9]+$' THEN (metadata->>'contentLength')::bigint
        ELSE 0
      END AS bytes
    FROM storage.objects
  ), type_rows AS (
    SELECT
      mimetype,
      COUNT(*)::bigint AS file_count,
      COALESCE(SUM(bytes), 0)::bigint AS total_bytes
    FROM object_sizes
    GROUP BY mimetype
    ORDER BY SUM(bytes) DESC
    LIMIT 20
  )
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'mimetype', mimetype,
    'file_count', file_count,
    'total_bytes', total_bytes
  ) ORDER BY total_bytes DESC), '[]'::jsonb)
  INTO v_object_type_stats
  FROM type_rows;

  RETURN jsonb_build_object(
    'success', true,
    'generated_at', now(),
    'database', jsonb_build_object(
      'database_name', current_database(),
      'total_bytes', v_db_bytes,
      'public_schema_bytes', v_public_schema_bytes,
      'storage_schema_bytes', v_storage_schema_bytes
    ),
    'storage', jsonb_build_object(
      'total_bytes', v_storage_total_bytes,
      'total_files', v_storage_total_files,
      'current_month_uploaded_bytes', v_storage_month_bytes,
      'current_month_uploaded_files', v_storage_month_files,
      'buckets', v_bucket_stats,
      'by_mimetype', v_object_type_stats
    ),
    'tables', v_table_stats,
    'network', jsonb_build_object(
      'exact_bandwidth_available_from_db', false,
      'note', 'قاعدة البيانات تعطي حجم التخزين وقاعدة البيانات بدقة. أما egress/API bandwidth الحقيقي فيلزم Supabase Dashboard أو Management API/Log Drain.'
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_resource_usage_internal(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_resource_usage_internal(uuid) TO service_role;
