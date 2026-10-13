-- ════════════════════════════════════════════════════════════════════════════
-- Photography tasks workflow
-- Date: 2026-06-10
-- Purpose:
--   Adds a lightweight internal workflow for assigning photographers to offers,
--   uploading media, submitting to office, and approving/rejecting the media.
-- ════════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS photography_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  off_id UUID REFERENCES offers(id) ON DELETE CASCADE,
  photographer_id UUID REFERENCES users(id) ON DELETE SET NULL,
  requested_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ttl TEXT NOT NULL DEFAULT '',
  notes TEXT NOT NULL DEFAULT '',
  loc JSONB DEFAULT '{}'::jsonb,
  media JSONB NOT NULL DEFAULT '[]'::jsonb,
  photographer_note TEXT NOT NULL DEFAULT '',
  office_note TEXT NOT NULL DEFAULT '',
  sts INTEGER NOT NULL DEFAULT 0 CHECK (sts BETWEEN 0 AND 5),
  ts_scheduled TIMESTAMPTZ,
  ts_submit TIMESTAMPTZ,
  ts_done TIMESTAMPTZ,
  ts_crt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ts_upd TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_photo_tasks_offer ON photography_tasks(off_id);
CREATE INDEX IF NOT EXISTS idx_photo_tasks_photographer ON photography_tasks(photographer_id, sts);
CREATE INDEX IF NOT EXISTS idx_photo_tasks_status ON photography_tasks(sts, ts_crt DESC);

ALTER TABLE photography_tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Photography tasks read" ON photography_tasks;
CREATE POLICY "Photography tasks read" ON photography_tasks
FOR SELECT USING (
  auth.uid() = photographer_id
  OR auth.uid() = requested_by
  OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2 AND i_del = 0)
);

DROP POLICY IF EXISTS "Admin can insert photography tasks" ON photography_tasks;
CREATE POLICY "Admin can insert photography tasks" ON photography_tasks
FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2 AND i_del = 0)
);

DROP POLICY IF EXISTS "Admin or photographer can update photography tasks" ON photography_tasks;
CREATE POLICY "Admin or photographer can update photography tasks" ON photography_tasks
FOR UPDATE USING (
  auth.uid() = photographer_id
  OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 2 AND i_del = 0)
);

-- Update internal permissions allowed list to include photography workflow keys.
CREATE OR REPLACE FUNCTION admin_update_user_permissions(
  p_target_uid UUID,
  p_perm JSONB DEFAULT '[]'::jsonb
)
RETURNS BOOLEAN AS $$
DECLARE
  v_admin_role INT;
  v_item TEXT;
  v_allowed TEXT[] := ARRAY[
    'admin_dashboard',
    'office_operations',
    'manage_users',
    'manage_permissions',
    'review_offers',
    'review_verifications',
    'media_review',
    'photography_management',
    'photographer_tasks',
    'fraud_suspects',
    'manage_appointments',
    'manage_deals',
    'manage_payments',
    'manage_reports',
    'manage_config',
    'view_analytics',
    'broker_dashboard',
    'broker_offers',
    'broker_appointments',
    'broker_deals',
    'broker_stats',
    'user_home',
    'user_offers',
    'user_requests',
    'user_appointments',
    'user_profile'
  ];
BEGIN
  SELECT role INTO v_admin_role FROM users WHERE id = auth.uid();

  IF v_admin_role IS NULL OR v_admin_role < 3 THEN
    RAISE EXCEPTION 'FORBIDDEN: Deputy/admin role required.';
  END IF;

  IF p_perm IS NULL THEN
    p_perm := '[]'::jsonb;
  END IF;

  IF jsonb_typeof(p_perm) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_PERMISSIONS: Expected JSON array.';
  END IF;

  FOR v_item IN SELECT jsonb_array_elements_text(p_perm)
  LOOP
    IF NOT (v_item = ANY(v_allowed)) THEN
      RAISE EXCEPTION 'INVALID_PERMISSION: %', v_item;
    END IF;
  END LOOP;

  UPDATE users
  SET perm = p_perm,
      ts_upd = NOW()
  WHERE id = p_target_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION admin_update_user_permissions FROM anon;
GRANT EXECUTE ON FUNCTION admin_update_user_permissions TO authenticated;
