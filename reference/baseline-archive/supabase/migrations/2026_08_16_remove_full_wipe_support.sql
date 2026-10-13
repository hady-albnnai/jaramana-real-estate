-- Remove one-time destructive wipe capability after successful launch reset.
DROP FUNCTION IF EXISTS public.list_all_user_upload_files_for_wipe();
