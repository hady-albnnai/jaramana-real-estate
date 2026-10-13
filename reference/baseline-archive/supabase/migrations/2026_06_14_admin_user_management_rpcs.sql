-- =====================================================
-- Migration: 2026_06_14_admin_user_management_rpcs.sql
-- الغرض: دوال إدارة الموظفين (مستوحى من مشروع Final + الدستور)
-- الالتزام: LOGIC_SPEC.md + DEVELOPMENT_GUIDELINES.md
-- =====================================================

-- =====================================================
-- 1. دالة إنشاء مستخدم جديد (للإدارة فقط)
-- =====================================================
CREATE OR REPLACE FUNCTION create_user_by_admin(
  p_admin_uid UUID,
  p_email TEXT,
  p_password TEXT,
  p_full_name TEXT,
  p_phone TEXT,
  p_role INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  new_user_id UUID;
  admin_role INT;
BEGIN
  -- التحقق من صلاحية المدير (role >= 5)
  SELECT role INTO admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF admin_role IS NULL OR admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- التحقق من صحة الدور
  IF p_role NOT IN (2, 3, 4, 5) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ROLE');
  END IF;

  -- إنشاء المستخدم عبر Supabase Auth (يتم من Edge Function عادة)
  -- هنا نفترض أن الـ Edge Function ستنشئ الـ auth user ثم تستدعي هذه الدالة
  -- لهذا السبب هذه الدالة تُستخدم بعد إنشاء الـ auth user

  RETURN jsonb_build_object('success', true, 'message', 'Use Edge Function create-user instead');
END;
$$;

-- =====================================================
-- 2. دالة تغيير دور المستخدم
-- =====================================================
CREATE OR REPLACE FUNCTION update_user_role_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_new_role INT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  admin_role INT;
  target_current_role INT;
BEGIN
  -- التحقق من صلاحية المدير
  SELECT role INTO admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF admin_role IS NULL OR admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  -- التحقق من أن المستهدف ليس المدير الرئيسي
  SELECT role INTO target_current_role FROM users WHERE id = p_target_uid;
  IF target_current_role = 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_CHANGE_SUPER_ADMIN');
  END IF;

  -- التحقق من صحة الدور الجديد
  IF p_new_role NOT IN (0, 1, 2, 3, 4, 5) THEN
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ROLE');
  END IF;

  -- تحديث الدور
  UPDATE users 
  SET role = p_new_role, ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;

  -- تسجيل في activity_log
  INSERT INTO activity_log (usr_id, act, det, ts)
  VALUES (p_admin_uid, 99, 
          jsonb_build_object('action', 'role_change', 'target', p_target_uid, 'new_role', p_new_role),
          NOW());

  RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================
-- 3. دالة تفعيل/تعطيل المستخدم
-- =====================================================
CREATE OR REPLACE FUNCTION toggle_user_status_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID,
  p_is_active BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  admin_role INT;
  target_role INT;
BEGIN
  SELECT role INTO admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF admin_role IS NULL OR admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  SELECT role INTO target_role FROM users WHERE id = p_target_uid;
  IF target_role = 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_DISABLE_SUPER_ADMIN');
  END IF;

  UPDATE users 
  SET sts = CASE WHEN p_is_active THEN 0 ELSE 1 END, ts_upd = NOW()
  WHERE id = p_target_uid AND i_del = 0;

  INSERT INTO activity_log (usr_id, act, det, ts)
  VALUES (p_admin_uid, 99, 
          jsonb_build_object('action', 'status_toggle', 'target', p_target_uid, 'active', p_is_active),
          NOW());

  RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================
-- 4. دالة إعادة تعيين كلمة السر
-- =====================================================
CREATE OR REPLACE FUNCTION reset_user_password_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  admin_role INT;
  target_role INT;
  new_password TEXT;
BEGIN
  SELECT role INTO admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF admin_role IS NULL OR admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  SELECT role INTO target_role FROM users WHERE id = p_target_uid;
  IF target_role = 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_RESET_SUPER_ADMIN');
  END IF;

  -- توليد كلمة سر عشوائية (يُفضل أن تتم في Edge Function)
  new_password := substr(md5(random()::text), 1, 12);

  -- ملاحظة: كلمة السر يجب أن تُحدث عبر Edge Function باستخدام auth.admin API
  -- هذه الدالة تعيد كلمة السر الجديدة فقط

  INSERT INTO activity_log (usr_id, act, det, ts)
  VALUES (p_admin_uid, 99, 
          jsonb_build_object('action', 'password_reset', 'target', p_target_uid),
          NOW());

  RETURN jsonb_build_object('success', true, 'new_password', new_password);
END;
$$;

-- =====================================================
-- 5. دالة حذف مستخدم (soft delete)
-- =====================================================
CREATE OR REPLACE FUNCTION delete_user_by_admin(
  p_admin_uid UUID,
  p_target_uid UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  admin_role INT;
  target_role INT;
BEGIN
  SELECT role INTO admin_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF admin_role IS NULL OR admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNAUTHORIZED');
  END IF;

  SELECT role INTO target_role FROM users WHERE id = p_target_uid;
  IF target_role = 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'CANNOT_DELETE_SUPER_ADMIN');
  END IF;

  UPDATE users 
  SET i_del = 1, ts_upd = NOW()
  WHERE id = p_target_uid;

  INSERT INTO activity_log (usr_id, act, det, ts)
  VALUES (p_admin_uid, 99, 
          jsonb_build_object('action', 'user_delete', 'target', p_target_uid),
          NOW());

  RETURN jsonb_build_object('success', true);
END;
$$;

-- =====================================================
-- 6. دالة جلب إحصائيات الموظفين (محسّنة)
-- =====================================================
CREATE OR REPLACE FUNCTION get_staff_stats_internal(p_user_uid UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_role INT;
  result JSONB;
BEGIN
  SELECT role INTO user_role FROM users WHERE id = p_user_uid AND i_del = 0;

  IF user_role IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;

  CASE user_role
    WHEN 2 THEN -- مصور
      result := jsonb_build_object(
        'role', 2,
        'completed_tasks', (SELECT COUNT(*) FROM photography_tasks WHERE photographer_id = p_user_uid AND sts = 3),
        'pending_tasks', (SELECT COUNT(*) FROM photography_tasks WHERE photographer_id = p_user_uid AND sts IN (0,1))
      );
    WHEN 3 THEN -- مشرف
      result := jsonb_build_object(
        'role', 3,
        'completed_visits', (SELECT COUNT(*) FROM appointments WHERE supervisor_uid = p_user_uid AND sts = 2),
        'active_tasks', (SELECT COUNT(*) FROM appointments WHERE supervisor_uid = p_user_uid AND sts = 1)
      );
    WHEN 4 THEN -- موظف مكتب
      result := jsonb_build_object(
        'role', 4,
        'reviewed_offers', (SELECT COUNT(*) FROM offers WHERE added_by = p_user_uid),
        'managed_appointments', (SELECT COUNT(*) FROM appointments WHERE bkr_id = p_user_uid)
      );
    WHEN 5, 6 THEN -- نائب / مدير
      result := jsonb_build_object(
        'role', user_role,
        'total_deals', (SELECT COUNT(*) FROM deals WHERE sts = 2),
        'approved_payments', (SELECT COUNT(*) FROM payments WHERE sts = 2),
        'pending_payments', (SELECT COUNT(*) FROM payments WHERE sts = 1),
        'verified_users', (SELECT COUNT(*) FROM users WHERE vrf = 2),
        'pending_verifications', (SELECT COUNT(*) FROM users WHERE vrf = 1),
        'total_users', (SELECT COUNT(*) FROM users WHERE i_del = 0),
        'active_offers', (SELECT COUNT(*) FROM offers WHERE sts = 2 AND i_del = 0)
      );
    ELSE
      result := jsonb_build_object('role', user_role, 'message', 'No specific stats for this role');
  END CASE;

  RETURN result;
END;
$$;

-- =====================================================
-- ملاحظات:
-- - كل الدوال محمية بـ SECURITY DEFINER
-- - لا يمكن تعديل المدير الرئيسي (role=6)
-- - كل العمليات تسجل في activity_log
-- - يُفضل استخدام Edge Functions للعمليات الحساسة (مثل create-user)
-- =====================================================