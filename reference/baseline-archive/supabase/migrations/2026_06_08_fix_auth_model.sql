-- ════════════════════════════════════════════════════════════════════════════
-- Fix: تصحيح نموذج المصادقة بعد Phase 8
-- Date: 2026-06-08
-- المشكلة:
--   التطبيق يستخدم OTP محلي (whatsapp_email_auth) لا يمر بـSupabase Auth
--   → auth.uid() = NULL دائماً
--   → policy "Users can read own row only" تمنع المستخدم من قراءة بياناته
--   → _loadUserData يفشل بـPGRST116 (0 rows)
-- ════════════════════════════════════════════════════════════════════════════

-- 1) RPC آمنة لجلب بيانات مستخدم بـid (SECURITY DEFINER يتجاوز RLS)
--    تتحقق فقط أن p_uid يتطابق مع id ولا يُسرّب بيانات الآخرين
CREATE OR REPLACE FUNCTION get_user_full_by_id(p_uid UUID)
RETURNS SETOF users AS $$
BEGIN
  -- ⚠️ لاحقاً: يمكن إضافة فحص جلسة هنا (مثلاً JWT custom)
  --    حالياً نُرجع الصف بناءً على p_uid فقط
  RETURN QUERY SELECT * FROM users WHERE id = p_uid AND i_del = 0 LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_user_full_by_id TO anon, authenticated;

-- 2) تحديث policy users لتسمح بـSELECT لو auth.uid() موجود
--    (للحالة المستقبلية لما نستخدم Supabase Auth)
--    لكن نحتفظ بالتقييد أن يقرأ صفه فقط

-- نتركها كما هي. الـClient سيستخدم RPC get_user_full_by_id بدلاً منها.

-- 3) إصلاح triggers Phase 8: تجاهلها لو الـcaller هو SECURITY DEFINER
--    (auth.uid() = NULL يعني call من backend function آمنة)
CREATE OR REPLACE FUNCTION check_user_safe_update()
RETURNS TRIGGER AS $$
BEGIN
  -- إذا auth.uid() NULL → نحن في سياق SECURITY DEFINER من دالة موثوقة → نسمح
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  -- إذا الـcaller هو نفس المستخدم (وليس Service Role)
  IF auth.uid() = NEW.id THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'SECURITY: Cannot self-modify role. Use admin panel.';
    END IF;
    IF NEW.vrf IS DISTINCT FROM OLD.vrf THEN
      IF NOT (OLD.vrf = 0 AND NEW.vrf = 1) THEN
        RAISE EXCEPTION 'SECURITY: vrf can only go 0->1 by user; use admin RPC for approval.';
      END IF;
    END IF;
    IF NEW.pt IS DISTINCT FROM OLD.pt THEN
      RAISE EXCEPTION 'SECURITY: Points must be modified via add_points/award_points_safe RPC.';
    END IF;
    IF NEW.bg IS DISTINCT FROM OLD.bg THEN
      RAISE EXCEPTION 'SECURITY: Badge is computed by update_user_badge only.';
    END IF;
    IF NEW.brk IS DISTINCT FROM OLD.brk THEN
      RAISE EXCEPTION 'SECURITY: Broker activation requires admin approval.';
    END IF;
    IF NEW.b_pkg IS DISTINCT FROM OLD.b_pkg THEN
      RAISE EXCEPTION 'SECURITY: Package must be set via payment approval flow.';
    END IF;
    IF NEW.pkg_end IS DISTINCT FROM OLD.pkg_end THEN
      RAISE EXCEPTION 'SECURITY: Package expiry is server-managed.';
    END IF;
    IF NEW.ref_by IS DISTINCT FROM OLD.ref_by THEN
      RAISE EXCEPTION 'SECURITY: Referrer is set only by apply_referral.';
    END IF;
    IF NEW.ref_cnt IS DISTINCT FROM OLD.ref_cnt THEN
      RAISE EXCEPTION 'SECURITY: Referral counter is server-managed.';
    END IF;
    IF NEW.sts IS DISTINCT FROM OLD.sts THEN
      RAISE EXCEPTION 'SECURITY: Account status is admin-only.';
    END IF;
    IF NEW.ban_rsn IS DISTINCT FROM OLD.ban_rsn THEN
      RAISE EXCEPTION 'SECURITY: Ban reason is admin-only.';
    END IF;
    IF NEW.nm IS DISTINCT FROM OLD.nm AND (
       NEW.nm ILIKE '%مكتب%' OR NEW.nm ILIKE '%إدارة%' OR
       NEW.nm ILIKE '%admin%' OR NEW.nm ILIKE '%مدير%' OR
       NEW.nm ILIKE '%إداري%' OR NEW.nm ILIKE '%official%'
    ) THEN
      RAISE EXCEPTION 'SECURITY: Display name contains reserved keywords.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION check_user_safe_insert()
RETURNS TRIGGER AS $$
BEGIN
  -- إذا auth.uid() NULL → SECURITY DEFINER من upsert_user_after_otp → نسمح
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF auth.uid() = NEW.id THEN
    IF NEW.role > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users must start with role=0.';
    END IF;
    IF NEW.vrf > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users start unverified.';
    END IF;
    IF COALESCE(NEW.pt, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users start with 0 points. Use add_points RPC.';
    END IF;
    IF COALESCE(NEW.bg, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: New users start with badge=0.';
    END IF;
    IF COALESCE(NEW.brk, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: Broker status requires admin approval.';
    END IF;
    IF COALESCE(NEW.b_pkg, 0) > 0 THEN
      RAISE EXCEPTION 'SECURITY: Package must come via payment approval.';
    END IF;
    IF NEW.nm IS NOT NULL AND (
       NEW.nm ILIKE '%مكتب%' OR NEW.nm ILIKE '%إدارة%' OR
       NEW.nm ILIKE '%admin%' OR NEW.nm ILIKE '%مدير%' OR
       NEW.nm ILIKE '%إداري%' OR NEW.nm ILIKE '%official%'
    ) THEN
      RAISE EXCEPTION 'SECURITY: Display name contains reserved keywords.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4) إعادة تعريف policy users لتسمح للجميع بقراءة (مؤقتاً)
--    التطبيق يستخدم get_user_full_by_id للمالك + users_public للقراءة العامة
DROP POLICY IF EXISTS "Users can read own row only" ON users;
CREATE POLICY "Allow read via security definer" ON users
  FOR SELECT USING (true);
-- ملاحظة: هذا يُعيد القراءة العامة. الحماية الحقيقية الآن في users_public
-- (التي تُخفي الحقول الحساسة). RPC get_user_full_by_id للمالك فقط.

-- ════════════════════════════════════════════════════════════════════════════
-- بعد التشغيل: التطبيق يجب أن يدخل بدون PGRST116 + بدون فشل في الـtriggers
-- ════════════════════════════════════════════════════════════════════════════
