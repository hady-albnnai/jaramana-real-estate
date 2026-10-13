-- ════════════════════════════════════════════════════════════════════════════
-- Migration: تحديث users.stats تلقائياً + دالة wk_lgn (تسجيل دخول أسبوعي)
-- Date: 2026-06-05
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) Trigger لتحديث users.stats.off عند إضافة/حذف عرض
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_user_stats_on_offer()
RETURNS TRIGGER AS $$
DECLARE
  v_count INT;
  v_uid UUID;
BEGIN
  v_uid := COALESCE(NEW.usr_id, OLD.usr_id);
  IF v_uid IS NULL THEN RETURN NEW; END IF;
  SELECT COUNT(*) INTO v_count FROM offers
    WHERE usr_id = v_uid AND i_del = 0;
  UPDATE users SET stats = jsonb_set(
    COALESCE(stats, '{}'::jsonb), '{off}', to_jsonb(v_count)
  ), ts_upd = NOW() WHERE id = v_uid;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_offers_stats ON offers;
CREATE TRIGGER trg_offers_stats
AFTER INSERT OR UPDATE OR DELETE ON offers
FOR EACH ROW EXECUTE FUNCTION update_user_stats_on_offer();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) Trigger لتحديث users.stats.req
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_user_stats_on_request()
RETURNS TRIGGER AS $$
DECLARE
  v_count INT;
  v_uid UUID;
BEGIN
  v_uid := COALESCE(NEW.usr_id, OLD.usr_id);
  IF v_uid IS NULL THEN RETURN NEW; END IF;
  SELECT COUNT(*) INTO v_count FROM requests
    WHERE usr_id = v_uid AND i_del = 0;
  UPDATE users SET stats = jsonb_set(
    COALESCE(stats, '{}'::jsonb), '{req}', to_jsonb(v_count)
  ), ts_upd = NOW() WHERE id = v_uid;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_requests_stats ON requests;
CREATE TRIGGER trg_requests_stats
AFTER INSERT OR UPDATE OR DELETE ON requests
FOR EACH ROW EXECUTE FUNCTION update_user_stats_on_request();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Trigger لتحديث users.stats.app (المواعيد لصاحب العرض)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_user_stats_on_appointment()
RETURNS TRIGGER AS $$
DECLARE
  v_count INT;
  v_uid UUID;
BEGIN
  v_uid := COALESCE(NEW.own_id, OLD.own_id);
  IF v_uid IS NULL THEN RETURN NEW; END IF;
  SELECT COUNT(*) INTO v_count FROM appointments
    WHERE own_id = v_uid;
  UPDATE users SET stats = jsonb_set(
    COALESCE(stats, '{}'::jsonb), '{app}', to_jsonb(v_count)
  ), ts_upd = NOW() WHERE id = v_uid;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_appointments_stats ON appointments;
CREATE TRIGGER trg_appointments_stats
AFTER INSERT OR UPDATE OR DELETE ON appointments
FOR EACH ROW EXECUTE FUNCTION update_user_stats_on_appointment();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4) Trigger لتحديث users.stats.dl (الصفقات للبائع والمشتري)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_user_stats_on_deal()
RETURNS TRIGGER AS $$
DECLARE
  v_seller UUID;
  v_buyer UUID;
  v_seller_count INT;
  v_buyer_count INT;
BEGIN
  v_seller := COALESCE(NEW.sell_uid, OLD.sell_uid);
  v_buyer := COALESCE(NEW.buy_uid, OLD.buy_uid);

  IF v_seller IS NOT NULL THEN
    SELECT COUNT(*) INTO v_seller_count FROM deals WHERE sell_uid = v_seller;
    UPDATE users SET stats = jsonb_set(
      COALESCE(stats, '{}'::jsonb), '{dl}', to_jsonb(v_seller_count)
    ), ts_upd = NOW() WHERE id = v_seller;
  END IF;

  IF v_buyer IS NOT NULL AND v_buyer <> v_seller THEN
    SELECT COUNT(*) INTO v_buyer_count FROM deals WHERE buy_uid = v_buyer;
    UPDATE users SET stats = jsonb_set(
      COALESCE(stats, '{}'::jsonb), '{dl}', to_jsonb(v_buyer_count)
    ), ts_upd = NOW() WHERE id = v_buyer;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_deals_stats ON deals;
CREATE TRIGGER trg_deals_stats
AFTER INSERT OR UPDATE OR DELETE ON deals
FOR EACH ROW EXECUTE FUNCTION update_user_stats_on_deal();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5) RPC: register_weekly_login — يفحص ويمنح pts.wkL لو مر أسبوع (القيمة الافتراضية 100 الآن)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION register_weekly_login(p_uid UUID, p_pts INT DEFAULT 100)
RETURNS BOOLEAN AS $$
DECLARE
  v_last TIMESTAMPTZ;
  v_now TIMESTAMPTZ := NOW();
  v_logins JSONB;
BEGIN
  SELECT wk_lgn INTO v_logins FROM users WHERE id = p_uid;
  v_logins := COALESCE(v_logins, '[]'::jsonb);

  -- آخر تسجيل دخول (آخر عنصر بالـ array)
  IF jsonb_array_length(v_logins) > 0 THEN
    v_last := (v_logins->-1)::text::timestamptz;
    -- لو آخر تسجيل أقل من 7 أيام، لا نمنح
    IF v_now - v_last < INTERVAL '7 days' THEN
      RETURN FALSE;
    END IF;
  END IF;

  -- نضيف التاريخ الحالي للقائمة (نحتفظ بآخر 10 فقط)
  v_logins := v_logins || to_jsonb(v_now::text);
  IF jsonb_array_length(v_logins) > 10 THEN
    v_logins := jsonb_path_query_array(v_logins, '$[last - 9 to last]');
  END IF;

  UPDATE users SET
    wk_lgn = v_logins,
    pt = pt + p_pts,
    ts_upd = NOW()
  WHERE id = p_uid;

  PERFORM update_user_badge(p_uid);
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION register_weekly_login TO anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- 6) Backfill: حدّث stats لكل المستخدمين الحاليين مرة واحدة
-- ════════════════════════════════════════════════════════════════════════════
UPDATE users u SET stats = jsonb_build_object(
  'off', COALESCE((SELECT COUNT(*) FROM offers WHERE usr_id = u.id AND i_del = 0), 0),
  'req', COALESCE((SELECT COUNT(*) FROM requests WHERE usr_id = u.id AND i_del = 0), 0),
  'app', COALESCE((SELECT COUNT(*) FROM appointments WHERE own_id = u.id), 0),
  'dl', COALESCE((SELECT COUNT(*) FROM deals WHERE sell_uid = u.id OR buy_uid = u.id), 0)
), ts_upd = NOW()
WHERE i_del = 0;

-- ════════════════════════════════════════════════════════════════════════════
-- 7) نظام الإحالة (Referral)
-- ════════════════════════════════════════════════════════════════════════════
ALTER TABLE users ADD COLUMN IF NOT EXISTS ref_by UUID REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS ref_cnt INT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_users_ref_by ON users(ref_by) WHERE ref_by IS NOT NULL;

-- RPC: apply_referral — يستدعى عند إنشاء حساب جديد بكود إحالة
CREATE OR REPLACE FUNCTION apply_referral(
  p_new_uid UUID,
  p_referrer_code TEXT,
  p_pts INT DEFAULT 1500
)
RETURNS BOOLEAN AS $$
DECLARE
  v_referrer_uid UUID;
BEGIN
  -- كود الإحالة = أول 8 أحرف من uid (بدون شرطات)
  SELECT id INTO v_referrer_uid FROM users
    WHERE REPLACE(id::text, '-', '') ILIKE p_referrer_code || '%'
    AND i_del = 0
    LIMIT 1;

  IF v_referrer_uid IS NULL OR v_referrer_uid = p_new_uid THEN
    RETURN FALSE;
  END IF;

  -- منع التكرار
  IF EXISTS(SELECT 1 FROM users WHERE id = p_new_uid AND ref_by IS NOT NULL) THEN
    RETURN FALSE;
  END IF;

  -- ربط المُحال بالمحيل
  UPDATE users SET ref_by = v_referrer_uid WHERE id = p_new_uid;
  -- زيادة عدّاد المحيل
  UPDATE users SET ref_cnt = COALESCE(ref_cnt, 0) + 1 WHERE id = v_referrer_uid;
  -- منح النقاط لكلا الطرفين
  UPDATE users SET pt = pt + p_pts WHERE id IN (p_new_uid, v_referrer_uid);

  PERFORM update_user_badge(p_new_uid);
  PERFORM update_user_badge(v_referrer_uid);

  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION apply_referral TO anon, authenticated;
