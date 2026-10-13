-- ══════════════════════════════════════════════════════════════════════
-- Migration: Admin Dashboard Stats RPC
-- Date: 2026-06-15
-- Purpose:
--   Replace client-side list loading for admin dashboard counters with one
--   aggregate SECURITY DEFINER RPC.
-- ══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_admin_dashboard_stats(p_admin_uid UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_role INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role
  FROM users
  WHERE id = p_admin_uid
    AND i_del = 0
    AND sts = 0;

  IF v_role IS NULL OR v_role < 4 THEN
    RAISE EXCEPTION 'UNAUTHORIZED';
  END IF;

  RETURN jsonb_build_object(
    'totalOffers', (SELECT COUNT(*) FROM offers WHERE i_del = 0),
    'pendingOffers', (SELECT COUNT(*) FROM offers WHERE sts = 1 AND i_del = 0),
    'publishedOffers', (SELECT COUNT(*) FROM offers WHERE sts = 2 AND i_del = 0),

    'totalUsers', (SELECT COUNT(*) FROM users WHERE i_del = 0),
    'activeUsers', (SELECT COUNT(*) FROM users WHERE sts = 0 AND i_del = 0),
    'bannedUsers', (SELECT COUNT(*) FROM users WHERE sts = 2 AND i_del = 0),
    'brokers', (SELECT COUNT(*) FROM users WHERE role = 1 AND i_del = 0),

    'totalDeals', (SELECT COUNT(*) FROM deals WHERE i_del = 0),
    'completedDeals', (SELECT COUNT(*) FROM deals WHERE sts IN (1, 2) AND i_del = 0),
    'totalCommission', COALESCE((SELECT SUM(com_val) FROM deals WHERE sts IN (1, 2) AND i_del = 0), 0),

    'totalAppointments', (SELECT COUNT(*) FROM appointments),
    'completedAppointments', (SELECT COUNT(*) FROM appointments WHERE sts = 2),

    'pendingPayments', (SELECT COUNT(*) FROM payments WHERE sts = 0),
    'approvedPayments', (SELECT COUNT(*) FROM payments WHERE sts IN (1, 2)),
    'openReports', (SELECT COUNT(*) FROM reports WHERE sts = 0),
    'pendingVerifications', (SELECT COUNT(*) FROM users WHERE vrf = 1 AND i_del = 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_admin_dashboard_stats(UUID) TO anon, authenticated, service_role;
