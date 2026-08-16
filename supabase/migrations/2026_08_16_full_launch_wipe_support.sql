-- One-time launch wipe support: list physical user-uploaded objects for protected Edge deletion.
CREATE OR REPLACE FUNCTION public.list_all_user_upload_files_for_wipe()
RETURNS TABLE(bucket_id text,name text)
LANGUAGE sql SECURITY DEFINER
SET search_path TO 'public','storage','extensions','pg_temp'
AS $function$
 SELECT o.bucket_id,o.name
 FROM storage.objects o
 WHERE o.bucket_id IN ('consultation_files','expediting_docs','ids_private','offer_images','payment_proofs')
 ORDER BY o.bucket_id,o.name;
$function$;
REVOKE ALL ON FUNCTION public.list_all_user_upload_files_for_wipe() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.list_all_user_upload_files_for_wipe() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.list_all_user_upload_files_for_wipe() TO service_role;
