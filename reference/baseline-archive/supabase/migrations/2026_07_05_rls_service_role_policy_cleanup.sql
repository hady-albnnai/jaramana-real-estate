-- =====================================================================
-- Migration: 2026_07_05_rls_service_role_policy_cleanup.sql
-- الغرض:
--   إزالة تحذير RLS Enabled No Policy من الجداول الداخلية المقفلة، بدون فتح
--   أي صلاحية للعميل. السياسات موجهة إلى service_role فقط.
-- =====================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'staff_sessions'
      AND policyname = 'staff_sessions_service_role_all'
  ) THEN
    CREATE POLICY staff_sessions_service_role_all
    ON public.staff_sessions
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'stats'
      AND policyname = 'stats_service_role_all'
  ) THEN
    CREATE POLICY stats_service_role_all
    ON public.stats
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'user_daily_limits'
      AND policyname = 'user_daily_limits_service_role_all'
  ) THEN
    CREATE POLICY user_daily_limits_service_role_all
    ON public.user_daily_limits
    FOR ALL TO service_role
    USING (true)
    WITH CHECK (true);
  END IF;
END $$;
