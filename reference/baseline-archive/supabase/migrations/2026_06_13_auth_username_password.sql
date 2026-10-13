-- ══════════════════════════════════════════════════════════════════════
-- Migration: اسم مستخدم + كلمة مرور + إحصائيات الموظفين
-- التاريخ: 2026-06-13
-- الغرض:
--   1) إضافة usr (اسم مستخدم فريد) + pwd (كلمة مرور مشفرة) لجدول users
--   2) RPCs: register_password, login_with_password, reset_password_with_otp,
--             change_password_internal, check_username_available
--   3) RPC: get_staff_stats_internal (إحصائيات كل موظف حسب دوره)
--   4) تحديث users_public (إضافة usr) + get_user_full_by_id (إضافة usr، إخفاء pwd)
-- ══════════════════════════════════════════════════════════════════════

-- ─── 1) تأكد من وجود pgcrypto ───
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─── 2) أعمدة جديدة ───
ALTER TABLE users ADD COLUMN IF NOT EXISTS usr TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS pwd TEXT;

-- Unique index على اسم المستخدم (فقط للمستخدمين غير المحذوفين)
CREATE UNIQUE INDEX IF NOT EXISTS ux_users_username_active
  ON users (LOWER(usr))
  WHERE usr IS NOT NULL AND i_del = 0;

-- ─── 3) تسجيل كلمة مرور بعد OTP الأول ───
-- يُستدعى من setup_profile بعد التسجيل الأول عبر واتساب
CREATE OR REPLACE FUNCTION register_password(
  p_user_uid UUID,
  p_username TEXT,
  p_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_usr TEXT;
  v_existing UUID;
BEGIN
  -- تطبيع اسم المستخدم
  v_usr := LOWER(TRIM(p_username));

  -- فحص الطول (3-30 حرف)
  IF LENGTH(v_usr) < 3 OR LENGTH(v_usr) > 30 THEN
    RAISE EXCEPTION 'USERNAME_LENGTH' USING HINT = 'اسم المستخدم يجب أن يكون بين 3 و 30 حرف';
  END IF;

  -- فحص الأحرف المسموحة (أحرف لاتينية + أرقام + _ + .)
  IF NOT v_usr ~ '^[a-z0-9_.]+$' THEN
    RAISE EXCEPTION 'USERNAME_INVALID_CHARS' USING HINT = 'اسم المستخدم يحتوي أحرف غير مسموحة';
  END IF;

  -- فحص قوة كلمة المرور (6+ أحرف)
  IF LENGTH(p_password) < 6 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT' USING HINT = 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
  END IF;

  -- فحص عدم تكرار اسم المستخدم
  SELECT id INTO v_existing FROM users
    WHERE LOWER(usr) = v_usr AND i_del = 0 AND id != p_user_uid;
  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'USERNAME_TAKEN' USING HINT = 'اسم المستخدم محجوز';
  END IF;

  -- فحص وجود المستخدم
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_uid AND i_del = 0) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  -- تحديث
  UPDATE users SET
    usr = v_usr,
    pwd = crypt(p_password, gen_salt('bf', 8)),
    ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN jsonb_build_object('success', true, 'username', v_usr);
END;
$$;
GRANT EXECUTE ON FUNCTION register_password(UUID, TEXT, TEXT) TO anon, authenticated;

-- ─── 4) تسجيل الدخول باسم مستخدم + كلمة مرور ───
CREATE OR REPLACE FUNCTION login_with_password(
  p_identifier TEXT,  -- اسم مستخدم أو رقم هاتف
  p_password TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user RECORD;
  v_identifier TEXT;
BEGIN
  v_identifier := LOWER(TRIM(p_identifier));

  -- محاولة البحث باسم المستخدم أولاً، ثم بالهاتف
  SELECT id, nm, role, pwd, sts, i_del INTO v_user
    FROM users
    WHERE (LOWER(usr) = v_identifier
           OR normalize_sy_phone(ph) = normalize_sy_phone(v_identifier))
      AND i_del = 0
    LIMIT 1;

  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING HINT = 'لم يتم العثور على حساب بهذا الاسم أو الرقم';
  END IF;

  -- فحص أن المستخدم أعدّ كلمة مرور
  IF v_user.pwd IS NULL THEN
    RAISE EXCEPTION 'NO_PASSWORD_SET' USING HINT = 'لم يتم تعيين كلمة مرور لهذا الحساب، سجّل دخولك عبر واتساب أولاً';
  END IF;

  -- فحص الحظر/التجميد
  IF v_user.sts = 2 THEN
    RAISE EXCEPTION 'USER_BANNED';
  END IF;
  IF v_user.sts = 1 THEN
    RAISE EXCEPTION 'USER_FROZEN';
  END IF;

  -- فحص كلمة المرور
  IF v_user.pwd != crypt(p_password, v_user.pwd) THEN
    RAISE EXCEPTION 'WRONG_PASSWORD' USING HINT = 'كلمة المرور غير صحيحة';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user.id,
    'role', v_user.role,
    'nm', v_user.nm
  );
END;
$$;
GRANT EXECUTE ON FUNCTION login_with_password(TEXT, TEXT) TO anon, authenticated;

-- ─── 5) إعادة تعيين كلمة المرور بعد OTP واتساب ───
CREATE OR REPLACE FUNCTION reset_password_with_otp(
  p_user_uid UUID,
  p_new_password TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF LENGTH(p_new_password) < 6 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_uid AND i_del = 0) THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  UPDATE users SET
    pwd = crypt(p_new_password, gen_salt('bf', 8)),
    ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION reset_password_with_otp(UUID, TEXT) TO anon, authenticated;

-- ─── 6) تغيير كلمة المرور (من الإعدادات) ───
CREATE OR REPLACE FUNCTION change_password_internal(
  p_user_uid UUID,
  p_old_password TEXT,
  p_new_password TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_pwd TEXT;
BEGIN
  SELECT pwd INTO v_pwd FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v_pwd IS NULL THEN
    RAISE EXCEPTION 'NO_PASSWORD_SET';
  END IF;

  IF v_pwd != crypt(p_old_password, v_pwd) THEN
    RAISE EXCEPTION 'WRONG_OLD_PASSWORD';
  END IF;

  IF LENGTH(p_new_password) < 6 THEN
    RAISE EXCEPTION 'PASSWORD_TOO_SHORT';
  END IF;

  UPDATE users SET
    pwd = crypt(p_new_password, gen_salt('bf', 8)),
    ts_upd = NOW()
  WHERE id = p_user_uid;

  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION change_password_internal(UUID, TEXT, TEXT) TO anon, authenticated;

-- ─── 7) فحص توفر اسم مستخدم ───
CREATE OR REPLACE FUNCTION check_username_available(
  p_username TEXT
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_usr TEXT;
BEGIN
  v_usr := LOWER(TRIM(p_username));
  IF LENGTH(v_usr) < 3 THEN RETURN FALSE; END IF;
  RETURN NOT EXISTS (
    SELECT 1 FROM users WHERE LOWER(usr) = v_usr AND i_del = 0
  );
END;
$$;
GRANT EXECUTE ON FUNCTION check_username_available(TEXT) TO anon, authenticated;

-- ─── 8) إحصائيات الموظف حسب الدور ───
-- تُرجع إحصائيات مخصصة لكل موظف بناءً على دوره
CREATE OR REPLACE FUNCTION get_staff_stats_internal(
  p_user_uid UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role INT;
  v_result JSONB := '{}';
  v_count INT;
BEGIN
  SELECT role INTO v_role FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;

  -- مصور (role=2): مهام مكتملة + معلّقة + مرسلة للمكتب
  IF v_role = 2 THEN
    SELECT COUNT(*) INTO v_count FROM photography_tasks
      WHERE photographer_id = p_user_uid AND sts = 3;
    v_result := v_result || jsonb_build_object('completed_tasks', v_count);

    SELECT COUNT(*) INTO v_count FROM photography_tasks
      WHERE photographer_id = p_user_uid AND sts IN (0, 1);
    v_result := v_result || jsonb_build_object('pending_tasks', v_count);

    SELECT COUNT(*) INTO v_count FROM photography_tasks
      WHERE photographer_id = p_user_uid AND sts = 2;
    v_result := v_result || jsonb_build_object('submitted_tasks', v_count);

  -- مشرف ميداني (role=3): زيارات منفذة + طلبات إتمام + مهام قيد التنفيذ
  ELSIF v_role = 3 THEN
    SELECT COUNT(*) INTO v_count FROM appointments
      WHERE supervisor_uid = p_user_uid AND sts = 2;
    v_result := v_result || jsonb_build_object('completed_visits', v_count);

    SELECT COUNT(*) INTO v_count FROM completion_requests
      WHERE executor_uid = p_user_uid;
    v_result := v_result || jsonb_build_object('completion_requests', v_count);

    SELECT COUNT(*) INTO v_count FROM appointments
      WHERE supervisor_uid = p_user_uid AND sts IN (0, 1);
    v_result := v_result || jsonb_build_object('active_tasks', v_count);

  -- موظف مكتب (role=4): عروض راجعها + مواعيد أدارها + طلبات إتمام
  ELSIF v_role = 4 THEN
    SELECT COUNT(*) INTO v_count FROM offers WHERE sts IN (2, 3);
    v_result := v_result || jsonb_build_object('reviewed_offers', v_count);

    SELECT COUNT(*) INTO v_count FROM appointments WHERE sts = 2;
    v_result := v_result || jsonb_build_object('managed_appointments', v_count);

    SELECT COUNT(*) INTO v_count FROM completion_requests WHERE sts IN (1, 2);
    v_result := v_result || jsonb_build_object('processed_completions', v_count);

  -- نائب مدير + مدير (role>=5): صفقات + مدفوعات + توثيقات
  ELSIF v_role >= 5 THEN
    SELECT COUNT(*) INTO v_count FROM deals WHERE i_del = 0;
    v_result := v_result || jsonb_build_object('total_deals', v_count);

    SELECT COUNT(*) INTO v_count FROM payments WHERE sts = 1;
    v_result := v_result || jsonb_build_object('approved_payments', v_count);

    SELECT COUNT(*) INTO v_count FROM payments WHERE sts = 0;
    v_result := v_result || jsonb_build_object('pending_payments', v_count);

    SELECT COUNT(*) INTO v_count FROM users WHERE vrf = 2 AND i_del = 0;
    v_result := v_result || jsonb_build_object('verified_users', v_count);

    SELECT COUNT(*) INTO v_count FROM users WHERE vrf = 1 AND i_del = 0;
    v_result := v_result || jsonb_build_object('pending_verifications', v_count);

    SELECT COUNT(*) INTO v_count FROM users WHERE i_del = 0;
    v_result := v_result || jsonb_build_object('total_users', v_count);

    SELECT COUNT(*) INTO v_count FROM offers WHERE sts = 2 AND i_del = 0;
    v_result := v_result || jsonb_build_object('active_offers', v_count);
  END IF;

  v_result := v_result || jsonb_build_object('role', v_role);
  RETURN v_result;
END;
$$;
GRANT EXECUTE ON FUNCTION get_staff_stats_internal(UUID) TO anon, authenticated;

-- ─── 9) إضافة usr لـ users_public view ───
-- إعادة إنشاء VIEW بدون كشف pwd
DROP VIEW IF EXISTS users_public;
CREATE VIEW users_public AS
  SELECT id, nm, usr, role, brk, brk_cls, brk_nm, bg, vrf, pt, ref_cnt, ts_crt
  FROM users
  WHERE i_del = 0;

-- ─── 10) تحديث get_user_full_by_id لإضافة usr وإخفاء pwd ───
-- ⚠️ نستخدم RETURNS SETOF JSONB لتفادي أي خطأ تطابق أنواع (مثل SMALLINT vs INT
--    في عمود vrf) — كل القيم تُسلسَل لـ JSON بشكل صحيح تلقائياً.
--    شكل الرد يبقى مصفوفة [{...}] — لا يحتاج تعديل كود Flutter.
-- pwd_flag: يُرجع فقط هل يوجد كلمة مرور أم لا (بدون القيمة الفعلية)
DROP FUNCTION IF EXISTS get_user_full_by_id(UUID);

CREATE FUNCTION get_user_full_by_id(p_uid UUID)
RETURNS SETOF JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  RETURN QUERY
    SELECT jsonb_build_object(
      'id', u.id, 'nm', u.nm, 'ph', u.ph, 'eml', u.eml, 'ad', u.ad, 'role', u.role,
      'sid', u.sid, 'img', u.img, 'pt', u.pt, 'bg', u.bg, 'bg_ts', u.bg_ts,
      'b_pkg', u.b_pkg, 'pkg_end', u.pkg_end, 'pkg_grace', u.pkg_grace,
      'brk', u.brk, 'brk_cls', u.brk_cls, 'brk_nm', u.brk_nm, 'sts', u.sts, 'ban_rsn', u.ban_rsn,
      'ntf', u.ntf, 'stats', u.stats, 'wk_lgn', u.wk_lgn, 'strk', u.strk, 'strk_dt', u.strk_dt,
      'i_del', u.i_del, 'perm', u.perm, 'ts_crt', u.ts_crt, 'ts_upd', u.ts_upd,
      'vrf', u.vrf, 'ref_by', u.ref_by, 'ref_cnt', u.ref_cnt,
      'usr', u.usr,
      -- pwd: فقط flag (لا نُرجع الهاش الفعلي)
      'pwd', CASE WHEN u.pwd IS NOT NULL THEN 'set' ELSE NULL END,
      'rl', u.rl, 'device_id', u.device_id, 'last_ip', u.last_ip, 'signup_ip', u.signup_ip,
      'device_history', u.device_history
    )
    FROM users u
    WHERE u.id = p_uid AND u.i_del = 0;
END;
$$;
GRANT EXECUTE ON FUNCTION get_user_full_by_id(UUID) TO anon, authenticated;

-- ─── 11) حماية pwd ───
-- • pwd لا يظهر في users_public (العرض العام).
-- • pwd لا يُرجع كهاش في get_user_full_by_id (فقط flag 'set' أو NULL).
-- • الحماية الفعلية لـ pwd هي RLS على users (لا تعديل مباشر من العميل) +
--   أن الكتابة تتم فقط عبر دوال SECURITY DEFINER الموثوقة.
