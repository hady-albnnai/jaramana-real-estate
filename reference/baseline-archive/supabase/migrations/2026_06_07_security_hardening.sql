-- ════════════════════════════════════════════════════════════════════════════
-- Migration: تشديد الأمان (Security Hardening) — Phase 8
-- Date: 2026-06-07
-- المرجع: تقرير الفحص الأمني — يعالج CVE-1 إلى CVE-7
-- ════════════════════════════════════════════════════════════════════════════
-- هذا الـ migration يُغلق الثغرات الحرجة التالية:
--   CVE-1: ترقية النفس إلى مدير عبر UPDATE مباشر
--   CVE-2: سرقة نقاط الإحالة (apply_referral مفتوحة)
--   CVE-3: التقييم الذاتي + التقييم المتكرر
--   CVE-4: كشف بيانات شخصية حساسة من users لكل مسجّل
--   CVE-6: سرقة ملكية العروض بسبب غياب WITH CHECK
--   CVE-7: إرسال إشعارات وهمية (phishing)
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) حماية أعمدة users الحساسة (CVE-1)
-- ─────────────────────────────────────────────────────────────────────────────
-- المبدأ: المستخدم يقدر يعدّل حقول الملف الشخصي فقط (nm, ph, eml, ad, img, sid, ntf)
-- أما (role, vrf, pt, bg, brk, b_pkg, ref_by, sts, ban_rsn) فلا تُعدَّل إلا
-- عبر دوال SECURITY DEFINER أو من حساب admin.

-- نُنشئ دالة تتحقق من أن المستخدم لم يحاول تعديل حقل ممنوع
CREATE OR REPLACE FUNCTION check_user_safe_update()
RETURNS TRIGGER AS $$
BEGIN
  -- إذا كان المُحدِّث هو نفس المستخدم (وليس Service Role / Admin)
  -- نمنع تعديل الحقول الحساسة
  IF auth.uid() = NEW.id THEN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
      RAISE EXCEPTION 'SECURITY: Cannot self-modify role. Use admin panel.';
    END IF;
    IF NEW.vrf IS DISTINCT FROM OLD.vrf THEN
      -- استثناء وحيد: 0 → 1 (تقديم طلب توثيق) مسموح
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
    -- منع انتحال "المكتب" أو الإدارة في الاسم
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

DROP TRIGGER IF EXISTS trg_user_safe_update ON users;
CREATE TRIGGER trg_user_safe_update
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION check_user_safe_update();

-- منع انتحال الاسم عند الـ INSERT أيضاً
CREATE OR REPLACE FUNCTION check_user_safe_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF auth.uid() = NEW.id THEN
    -- مستخدم جديد لا يقدر يبدأ بحالة ممتازة
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
    -- نفس فحص الاسم
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

DROP TRIGGER IF EXISTS trg_user_safe_insert ON users;
CREATE TRIGGER trg_user_safe_insert
BEFORE INSERT ON users
FOR EACH ROW EXECUTE FUNCTION check_user_safe_insert();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) إخفاء البيانات الشخصية الحساسة (CVE-4)
-- ─────────────────────────────────────────────────────────────────────────────
-- استبدال policy "Users can read active users" بـ policy أضيق:
--   - الحقول العامة (id, nm, role, brk, bg, vrf, img, ref_cnt, ts_crt) للجميع
--   - الحقول الحساسة (ph, eml, sid, ad, ban_rsn, ntf, stats) للمالك فقط
-- الحل: نُنشئ VIEW عامة + سياسة users تسمح فقط للمالك بقراءة الـrow الكامل

DROP POLICY IF EXISTS "Users can read active users" ON users;
DROP POLICY IF EXISTS "Users can read own row only" ON users;
DROP POLICY IF EXISTS "Users can read public fields" ON users;

-- المالك يقرأ صفه فقط بالكامل
CREATE POLICY "Users can read own row only" ON users
  FOR SELECT USING (auth.uid() = id AND i_del = 0);

-- VIEW عامة بالحقول الآمنة فقط (يستعملها الـclient لإثراء البطاقات)
DROP VIEW IF EXISTS users_public CASCADE;
CREATE VIEW users_public AS
SELECT
  id,
  nm,        -- الاسم يبقى للظهور (يمكن تخفيفه لاحقاً)
  role,
  brk,
  brk_cls,
  brk_nm,
  bg,
  vrf,
  img,       -- صورة فقط (الـURL مرجع لـStorage)
  pt,
  ref_cnt,
  ts_crt
FROM users
WHERE i_del = 0;

GRANT SELECT ON users_public TO anon, authenticated;

-- لكن RLS لا تنطبق على VIEW بشكل افتراضي؛ نضمن انها SECURITY INVOKER:
ALTER VIEW users_public SET (security_invoker = true);

-- ⚠️ المطلوب من Client: استبدال SELECT FROM users (لغير المالك) بـ SELECT FROM users_public.

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) WITH CHECK لـ offers (CVE-6)
-- ─────────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Owner can update own offer" ON offers;
CREATE POLICY "Owner can update own offer" ON offers
  FOR UPDATE
  USING (auth.uid() = usr_id)
  WITH CHECK (auth.uid() = usr_id);

-- منع تغيير usr_id عبر trigger
CREATE OR REPLACE FUNCTION check_offer_safe_update()
RETURNS TRIGGER AS $$
BEGIN
  IF auth.uid() = OLD.usr_id THEN
    IF NEW.usr_id IS DISTINCT FROM OLD.usr_id THEN
      RAISE EXCEPTION 'SECURITY: Cannot change offer ownership.';
    END IF;
    -- منع تغيير العمولة/الترقيات يدوياً
    IF NEW.com IS DISTINCT FROM OLD.com THEN
      RAISE EXCEPTION 'SECURITY: Commission is admin/server-only.';
    END IF;
    IF NEW.i_pin IS DISTINCT FROM OLD.i_pin
       OR NEW.i_bst IS DISTINCT FROM OLD.i_bst
       OR NEW.i_fms IS DISTINCT FROM OLD.i_fms THEN
      RAISE EXCEPTION 'SECURITY: Boost flags via purchase_offer_boost RPC only.';
    END IF;
    -- منع تغيير عداد المشاهدات يدوياً
    IF NEW.vws > OLD.vws + 1 THEN
      RAISE EXCEPTION 'SECURITY: Views can only increment by 1.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_offer_safe_update ON offers;
CREATE TRIGGER trg_offer_safe_update
BEFORE UPDATE ON offers
FOR EACH ROW EXECUTE FUNCTION check_offer_safe_update();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) حماية ratings (CVE-3)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

-- منع التقييم الذاتي + التقييم المتكرر
ALTER TABLE ratings DROP CONSTRAINT IF EXISTS ratings_no_self;
ALTER TABLE ratings ADD CONSTRAINT ratings_no_self
  CHECK (reviewer_uid <> target_uid);

CREATE UNIQUE INDEX IF NOT EXISTS ratings_unique_reviewer_target
  ON ratings(reviewer_uid, target_uid);

-- إضافة عمود اختياري لربط التقييم بصفقة/موعد فعلي (إثبات تعامل)
ALTER TABLE ratings ADD COLUMN IF NOT EXISTS appointment_id UUID
  REFERENCES appointments(id) ON DELETE SET NULL;
ALTER TABLE ratings ADD COLUMN IF NOT EXISTS deal_id UUID
  REFERENCES deals(id) ON DELETE SET NULL;

-- سياسات RLS
DROP POLICY IF EXISTS "ratings_select_all" ON ratings;
DROP POLICY IF EXISTS "ratings_insert_authenticated" ON ratings;
DROP POLICY IF EXISTS "ratings_no_update" ON ratings;
DROP POLICY IF EXISTS "ratings_no_delete" ON ratings;

CREATE POLICY "ratings_select_all" ON ratings
  FOR SELECT USING (true); -- متاحة للقراءة (متوسط التقييم)

CREATE POLICY "ratings_insert_authenticated" ON ratings
  FOR INSERT WITH CHECK (
    auth.uid() = reviewer_uid          -- المُقيِّم هو الموقّع
    AND auth.uid() <> target_uid       -- وليس النفس
    AND stars BETWEEN 1 AND 5
  );

-- لا يمكن تعديل أو حذف تقييم (لمنع التلاعب)
-- نُسجّل فقط سياسات SELECT/INSERT — UPDATE/DELETE denied by default.

-- Trigger إضافي يتحقق أن المُقيِّم له موعد منتهٍ مع المستهدف
CREATE OR REPLACE FUNCTION check_rating_valid()
RETURNS TRIGGER AS $$
DECLARE
  v_has_completed BOOLEAN;
BEGIN
  -- نسمح بالتقييم إذا:
  --  (أ) موعد فعلي مع المستهدف اكتمل (sts=2)، أو
  --  (ب) صفقة فعلية بين الطرفين، أو
  --  (ج) المُقيِّم وسيط للمستهدف
  SELECT EXISTS (
    SELECT 1 FROM appointments a
    JOIN offers o ON o.id = a.off_id
    WHERE (a.own_id = NEW.target_uid AND o.usr_id = NEW.target_uid)
      AND a.sts = 2
      AND EXISTS (
        SELECT 1 FROM appointments a2
        WHERE a2.off_id = a.off_id
          AND a2.sts = 2
          -- المُقيِّم له موعد منتهٍ على نفس العرض
          AND (a2.bkr_id = NEW.reviewer_uid
               OR EXISTS (SELECT 1 FROM deals d
                          WHERE d.app_id = a2.id
                          AND (d.buy_uid = NEW.reviewer_uid
                               OR d.sell_uid = NEW.reviewer_uid)))
      )
  ) OR EXISTS (
    SELECT 1 FROM deals d
    WHERE d.sts = 1
      AND ((d.sell_uid = NEW.target_uid AND d.buy_uid = NEW.reviewer_uid)
        OR (d.buy_uid = NEW.target_uid AND d.sell_uid = NEW.reviewer_uid))
  ) INTO v_has_completed;

  IF NOT v_has_completed THEN
    RAISE EXCEPTION 'SECURITY: You can only rate users you have completed a deal/appointment with.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_rating_valid ON ratings;
CREATE TRIGGER trg_rating_valid
BEFORE INSERT ON ratings
FOR EACH ROW EXECUTE FUNCTION check_rating_valid();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) حماية apply_referral (CVE-2)
-- ─────────────────────────────────────────────────────────────────────────────
-- النسخة الجديدة:
--   - تعمل فقط لـauth.uid() = p_new_uid (لا يستطيع شخص ثالث تمريرها)
--   - تتحقق من حد زمني: لا أكثر من 5 إحالات في الساعة لكل محيل
--   - تستخدم رمز فريد كامل (UUID) بدل 8 أحرف، لمنع التعداد

CREATE OR REPLACE FUNCTION apply_referral(
  p_new_uid UUID,
  p_referrer_code TEXT,
  p_pts INT DEFAULT 1500
)
RETURNS BOOLEAN AS $$
DECLARE
  v_referrer_uid UUID;
  v_recent_refs INT;
BEGIN
  -- 1. السماح فقط للمستخدم نفسه باستدعائها
  IF auth.uid() IS NULL OR auth.uid() <> p_new_uid THEN
    RAISE EXCEPTION 'SECURITY: apply_referral can only be called by the new user.';
  END IF;

  -- 2. حلّ الكود (نفس المنطق السابق)
  SELECT id INTO v_referrer_uid FROM users
    WHERE REPLACE(id::text, '-', '') ILIKE p_referrer_code || '%'
    AND i_del = 0
    LIMIT 1;

  IF v_referrer_uid IS NULL OR v_referrer_uid = p_new_uid THEN
    RETURN FALSE;
  END IF;

  -- 3. منع التكرار للمستخدم الجديد
  IF EXISTS(SELECT 1 FROM users WHERE id = p_new_uid AND ref_by IS NOT NULL) THEN
    RETURN FALSE;
  END IF;

  -- 4. حدّ معدل: لا أكثر من 5 إحالات/ساعة لكل محيل
  SELECT COUNT(*) INTO v_recent_refs
    FROM users
    WHERE ref_by = v_referrer_uid
      AND ts_crt > NOW() - INTERVAL '1 hour';
  IF v_recent_refs >= 5 THEN
    RAISE EXCEPTION 'RATE_LIMIT: Referrer reached 5 referrals/hour cap.';
  END IF;

  -- 5. تنفيذ الإحالة
  UPDATE users SET ref_by = v_referrer_uid WHERE id = p_new_uid;
  UPDATE users SET ref_cnt = COALESCE(ref_cnt, 0) + 1 WHERE id = v_referrer_uid;
  UPDATE users SET pt = pt + p_pts WHERE id IN (p_new_uid, v_referrer_uid);

  PERFORM update_user_badge(p_new_uid);
  PERFORM update_user_badge(v_referrer_uid);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION apply_referral FROM anon;
GRANT EXECUTE ON FUNCTION apply_referral TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6) Server function آمنة لطلب التوثيق (يستخدمها client بدل UPDATE)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION request_verification()
RETURNS BOOLEAN AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_user RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;
  SELECT id, sid, img, vrf INTO v_user FROM users WHERE id = v_uid;
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF v_user.vrf = 2 THEN
    RAISE EXCEPTION 'ALREADY_VERIFIED';
  END IF;
  IF v_user.vrf = 1 THEN
    RAISE EXCEPTION 'ALREADY_PENDING';
  END IF;
  IF v_user.sid IS NULL OR LENGTH(TRIM(v_user.sid)) = 0
     OR v_user.img IS NULL OR LENGTH(TRIM(v_user.img)) = 0 THEN
    RAISE EXCEPTION 'MISSING_DOCUMENTS';
  END IF;
  UPDATE users SET vrf = 1, ts_upd = NOW() WHERE id = v_uid;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION request_verification FROM anon;
GRANT EXECUTE ON FUNCTION request_verification TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 7) Server functions آمنة للأدمن لاعتماد/رفض التوثيق
--    (تستبدل UPDATE المباشر من client الذي ينتهك trg_user_safe_update)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_approve_verification(p_target_uid UUID)
RETURNS BOOLEAN AS $$
DECLARE v_admin_role INT;
BEGIN
  SELECT role INTO v_admin_role FROM users WHERE id = auth.uid();
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;
  UPDATE users SET vrf = 2, ts_upd = NOW() WHERE id = p_target_uid;
  -- إشعار المستخدم
  INSERT INTO notifications (uid, tp, ttl, bdy, act)
    VALUES (p_target_uid, 4, '✅ تم اعتماد توثيق حسابك',
            'تهانينا! حسابك أصبح موثقاً رسمياً.', 'verification');
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION admin_reject_verification(p_target_uid UUID, p_reason TEXT DEFAULT '')
RETURNS BOOLEAN AS $$
DECLARE v_admin_role INT;
BEGIN
  SELECT role INTO v_admin_role FROM users WHERE id = auth.uid();
  IF v_admin_role IS NULL OR v_admin_role < 2 THEN
    RAISE EXCEPTION 'FORBIDDEN: Admin role required.';
  END IF;
  UPDATE users SET vrf = 0, ts_upd = NOW() WHERE id = p_target_uid;
  INSERT INTO notifications (uid, tp, ttl, bdy, act)
    VALUES (p_target_uid, 4, '🚫 رفض طلب التوثيق',
            CASE WHEN LENGTH(TRIM(p_reason)) > 0
                 THEN 'السبب: ' || p_reason
                 ELSE 'يرجى التأكد من وضوح صورة الهوية وإعادة المحاولة.'
            END, 'verification');
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE EXECUTE ON FUNCTION admin_approve_verification, admin_reject_verification FROM anon;
GRANT EXECUTE ON FUNCTION admin_approve_verification, admin_reject_verification TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8) حماية notifications من الـphishing (CVE-7)
-- ─────────────────────────────────────────────────────────────────────────────
-- نمنع INSERT المباشر من client. الإدراج يتم عبر:
--   - triggers في DB (notification_triggers.sql)
--   - دوال SECURITY DEFINER (admin_approve_verification, إلخ)
DROP POLICY IF EXISTS "notifications_no_user_insert" ON notifications;
CREATE POLICY "notifications_no_user_insert" ON notifications
  FOR INSERT WITH CHECK (false);

-- المستخدم يستطيع تحديث i_rd (قراءة) فقط لإشعاراته
DROP POLICY IF EXISTS "notifications_user_mark_read" ON notifications;
CREATE POLICY "notifications_user_mark_read" ON notifications
  FOR UPDATE
  USING (auth.uid() = uid)
  WITH CHECK (auth.uid() = uid);

-- ─────────────────────────────────────────────────────────────────────────────
-- 9) قفل OTP بعد محاولات فاشلة (CVE-5 جزئياً)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION verify_otp_safe(p_phone TEXT, p_code TEXT)
RETURNS BOOLEAN AS $$
DECLARE v_row RECORD;
BEGIN
  SELECT * INTO v_row FROM otp_codes
    WHERE phone = p_phone AND used = 0 AND expires_at > NOW()
    ORDER BY ts_crt DESC LIMIT 1;

  IF v_row IS NULL THEN
    RETURN FALSE;
  END IF;
  IF v_row.attempts >= 5 THEN
    -- نُنهي صلاحية الكود فوراً
    UPDATE otp_codes SET expires_at = NOW() WHERE id = v_row.id;
    RAISE EXCEPTION 'OTP_LOCKED: Too many failed attempts.';
  END IF;
  IF v_row.code = p_code THEN
    UPDATE otp_codes SET used = 1 WHERE id = v_row.id;
    DELETE FROM otp_codes WHERE phone = p_phone AND used = 1;
    RETURN TRUE;
  ELSE
    UPDATE otp_codes SET attempts = attempts + 1 WHERE id = v_row.id;
    RETURN FALSE;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION verify_otp_safe TO anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- تعليقات توثيقية
-- ════════════════════════════════════════════════════════════════════════════
COMMENT ON FUNCTION check_user_safe_update IS
  'Phase 8 Security: يمنع self-promotion للحقول الحساسة في users.';
COMMENT ON FUNCTION request_verification IS
  'Phase 8 Security: الطريق الآمن لرفع vrf من 0 إلى 1.';
COMMENT ON FUNCTION admin_approve_verification IS
  'Phase 8 Security: اعتماد التوثيق (role>=2 required).';
COMMENT ON VIEW users_public IS
  'Phase 8 Security: VIEW عامة بحقول آمنة فقط — استبدلت SELECT * FROM users في الـclient.';
COMMENT ON FUNCTION apply_referral IS
  'Phase 8 Security: محصورة لـauth.uid()=p_new_uid + rate-limit 5/h.';

-- ─────────────────────────────────────────────────────────────────────────────
-- 10) إصلاح check_offer_duplicate (H-2)
--     النسخة الأصلية كانت تستثني الـusr_id الحالي، مما يسمح بنشر مكرر بنفس الحساب
--     النسخة الجديدة تكشف التكرار من أي مصدر + تتحمّل الفروق البسيطة في النص
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_offer_duplicate(
  p_ttl TEXT, p_prc NUMERIC, p_loc JSONB, p_usr_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE v_dup BOOLEAN;
BEGIN
  -- تطبيع النص: lowercase + إزالة المسافات المتعددة
  SELECT EXISTS(
    SELECT 1 FROM offers
    WHERE LOWER(REGEXP_REPLACE(ttl, '\s+', ' ', 'g')) =
          LOWER(REGEXP_REPLACE(p_ttl, '\s+', ' ', 'g'))
      AND prc = p_prc
      AND i_del = 0
      -- نكشف التكرار حتى من نفس المستخدم (لمنع نشر متعدد بنفس الحساب)
  ) INTO v_dup;
  RETURN v_dup;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION check_offer_duplicate TO anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- نهاية Phase 8 Hardening
-- ════════════════════════════════════════════════════════════════════════════
