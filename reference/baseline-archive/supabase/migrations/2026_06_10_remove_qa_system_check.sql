-- Remove temporary/in-app QA server function from production-clean schema.
DROP FUNCTION IF EXISTS public.qa_system_check(UUID);
