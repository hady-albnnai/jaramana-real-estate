-- ============================================
-- Migration: Points System Refinement (Anti-Cheat & Quality)
-- Date: 2026-06-06
-- ============================================

-- 1️⃣ جدول تتبع الحدود اليومية
CREATE TABLE IF NOT EXISTS user_daily_limits (
    uid UUID REFERENCES users(id) ON DELETE CASCADE,
    event_type TEXT, -- 'add_offer', 'like', 'comment', 'share', etc.
    event_date DATE DEFAULT CURRENT_DATE,
    count INT DEFAULT 0,
    PRIMARY KEY (uid, event_type, event_date)
);

-- 2️⃣ تحديث مدة التثبيت (Pin) في دالة purchase_offer_boost
-- سنقوم بإعادة إنشاء الدالة مع تعديل مدة الـ pin من 7 أيام إلى يومين
CREATE OR REPLACE FUNCTION purchase_offer_boost(
  p_uid UUID, 
  p_offer_id UUID, 
  p_boost_type TEXT, 
  p_cost INT
) RETURNS JSONB AS $$
DECLARE
  v_offer_owner UUID;
  v_user_points INT;
  v_duration INT;
  v_success BOOLEAN := FALSE;
BEGIN
  -- التحقق من ملكية العرض
  SELECT usr_id INTO v_offer_owner FROM offers WHERE id = p_offer_id;
  IF v_offer_owner IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND'); END IF;
  IF v_offer_owner != p_uid THEN RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER'); END IF;

  -- التحقق من النقاط
  SELECT pt INTO v_user_points FROM users WHERE id = p_uid;
  IF v_user_points < p_cost THEN 
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_POINTS', 'current', v_user_points, 'required', p_cost); 
  END IF;

  -- تحديد المدة بناءً على النوع (التعديل هنا: pin = 2 days)
  v_duration := CASE p_boost_type
    WHEN 'ren' THEN 30
    WHEN 'pin' THEN 2  -- 👈 تعديل من 7 إلى 2
    WHEN 'bst' THEN 14
    WHEN 'dsc5' THEN 60
    WHEN 'fms' THEN 30
    ELSE 0
  END;

  IF v_duration = 0 THEN RETURN jsonb_build_object('success', false, 'error', 'INVALID_BOOST_TYPE'); END IF;

  -- خصم النقاط
  UPDATE users SET pt = pt - p_cost WHERE id = p_uid;

  -- تطبيق الترقية
  IF p_boost_type = 'ren' THEN
    UPDATE offers SET ts_end = ts_end + (v_duration || ' days')::interval, sts = 2 WHERE id = p_offer_id;
  ELSIF p_boost_type = 'pin' THEN
    UPDATE offers SET i_pin = 1, pin_end = NOW() + (v_duration || ' days')::interval WHERE id = p_offer_id;
  ELSIF p_boost_type = 'bst' THEN
    UPDATE offers SET i_bst = 1, bst_end = NOW() + (v_duration || ' days')::interval WHERE id = p_offer_id;
  ELSIF p_boost_type = 'dsc5' THEN
    UPDATE offers SET dsc_pct = 5, dsc_end = NOW() + (v_duration || ' days')::interval WHERE id = p_offer_id;
  ELSIF p_boost_type = 'fms' THEN
    UPDATE offers SET i_fms = 1, fms_end = NOW() + (v_duration || ' days')::interval WHERE id = p_offer_id;
  END IF;

  -- تسجيل في activity_log
  INSERT INTO activity_log (uid, action, details) 
  VALUES (p_uid, 'purchase_boost', jsonb_build_object('offer_id', p_offer_id, 'type', p_boost_type, 'cost', p_cost));

  RETURN jsonb_build_object('success', true, 'duration_days', v_duration, 'new_balance', v_user_points - p_cost);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 3️⃣ دالة منح النقاط "الآمنة" (Safe Award) مع فحص الحدود اليومية
CREATE OR REPLACE FUNCTION award_points_safe(
  p_uid UUID,
  p_event_type TEXT,
  p_points INT
) RETURNS JSONB AS $$
DECLARE
  v_max_daily INT;
  v_current_count INT;
BEGIN
  -- 1. تحديد الحد اليومي بناءً على نوع الحدث
  v_max_daily := CASE p_event_type
    WHEN 'add_offer' THEN 3   -- بحد أقصى 3 عروض يومياً
    WHEN 'like'      THEN 10  -- بحد أقصى 10 لايكات
    WHEN 'comment'   THEN 5   -- بحد أقصى 5 تعليقات
    WHEN 'share'     THEN 5   -- بحد أقصى 5 مشاركات
    ELSE 999                  -- أحداث أخرى بدون حد (إحالات، صفقات، إلخ)
  END;

  -- 2. فحص العدد الحالي للمستخدم اليوم
  SELECT count INTO v_current_count 
  FROM user_daily_limits 
  WHERE uid = p_uid AND event_type = p_event_type AND event_date = CURRENT_DATE;

  IF v_current_count >= v_max_daily THEN
    RETURN jsonb_build_object('success', false, 'error', 'DAILY_LIMIT_REACHED', 'limit', v_max_daily);
  END IF;

  -- 3. إضافة النقاط
  PERFORM add_points(p_uid, p_points);

  -- 4. تحديث عداد اليوم
  INSERT INTO user_daily_limits (uid, event_type, event_date, count)
  VALUES (p_uid, p_event_type, CURRENT_DATE, 1)
  ON CONFLICT (uid, event_type, event_date) 
  DO UPDATE SET count = user_daily_limits.count + 1;

  RETURN jsonb_build_object('success', true, 'points_added', p_points);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4️⃣ مكافأة التقييم 5 نجوم
CREATE TABLE IF NOT EXISTS ratings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reviewer_uid UUID REFERENCES users(id),
    target_uid UUID REFERENCES users(id),
    stars INT CHECK (stars BETWEEN 1 AND 5),
    comment TEXT,
    ts_crt TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION trg_rating_bonus()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.stars = 5 THEN
    PERFORM award_points_safe(NEW.target_uid, 'top_rating', 200);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_rating_bonus_notify ON ratings;
CREATE TRIGGER trg_rating_bonus_notify
AFTER INSERT ON ratings
FOR EACH ROW EXECUTE FUNCTION trg_rating_bonus();
