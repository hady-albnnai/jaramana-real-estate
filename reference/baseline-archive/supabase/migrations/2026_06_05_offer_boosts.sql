-- ════════════════════════════════════════════════════════════════════════════
-- Migration: نظام ترقيات العروض (spd: pin/boost/featured/renew/discount)
-- Date: 2026-06-05
-- ════════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) إضافة أعمدة الترقيات لجدول offers
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE offers ADD COLUMN IF NOT EXISTS i_pin INTEGER DEFAULT 0 CHECK (i_pin IN (0,1));
ALTER TABLE offers ADD COLUMN IF NOT EXISTS i_bst INTEGER DEFAULT 0 CHECK (i_bst IN (0,1));
ALTER TABLE offers ADD COLUMN IF NOT EXISTS i_fms INTEGER DEFAULT 0 CHECK (i_fms IN (0,1));
ALTER TABLE offers ADD COLUMN IF NOT EXISTS pin_end TIMESTAMPTZ;
ALTER TABLE offers ADD COLUMN IF NOT EXISTS bst_end TIMESTAMPTZ;
ALTER TABLE offers ADD COLUMN IF NOT EXISTS fms_end TIMESTAMPTZ;
ALTER TABLE offers ADD COLUMN IF NOT EXISTS dsc_pct INTEGER DEFAULT 0; -- خصم على العمولة %
ALTER TABLE offers ADD COLUMN IF NOT EXISTS dsc_end TIMESTAMPTZ;

-- Index لتسريع الترتيب حسب الترقيات
CREATE INDEX IF NOT EXISTS idx_offers_boosts
  ON offers(i_pin DESC, i_fms DESC, i_bst DESC, ts_pub DESC)
  WHERE i_del = 0 AND i_pub = 1;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) RPC: purchase_offer_boost
-- ─────────────────────────────────────────────────────────────────────────────
-- يخصم النقاط من المستخدم ويفعّل الميزة على العرض
-- الأنواع المدعومة:
--   'ren'  → تجديد العرض لمدة 30 يوم إضافية (ينقل ts_end)
--   'pin'  → تثبيت في الأعلى لمدة 7 أيام
--   'bst'  → Boost لمدة 14 يوم
--   'dsc5' → خصم 5% على عمولة المكتب
--   'fms'  → عرض مميّز (Featured) لمدة 30 يوم
CREATE OR REPLACE FUNCTION purchase_offer_boost(
  p_uid UUID,
  p_offer_id UUID,
  p_boost_type TEXT,
  p_cost INTEGER
)
RETURNS JSONB AS $$
DECLARE
  v_user_pts INTEGER;
  v_owner_id UUID;
  v_now TIMESTAMPTZ := NOW();
  v_result JSONB;
BEGIN
  -- 1) التحقق من ملكية العرض
  SELECT usr_id INTO v_owner_id FROM offers WHERE id = p_offer_id AND i_del = 0;
  IF v_owner_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'OFFER_NOT_FOUND');
  END IF;
  IF v_owner_id != p_uid THEN
    RETURN jsonb_build_object('success', false, 'error', 'NOT_OWNER');
  END IF;

  -- 2) التحقق من رصيد النقاط
  SELECT pt INTO v_user_pts FROM users WHERE id = p_uid;
  IF v_user_pts IS NULL OR v_user_pts < p_cost THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INSUFFICIENT_POINTS',
      'current_points', COALESCE(v_user_pts, 0),
      'required', p_cost
    );
  END IF;

  -- 3) تطبيق الترقية حسب النوع
  CASE p_boost_type
    WHEN 'ren' THEN
      UPDATE offers SET
        ts_end = GREATEST(COALESCE(ts_end, v_now), v_now) + INTERVAL '30 days',
        ts_ren = v_now,
        sts = CASE WHEN sts = 4 THEN 2 ELSE sts END, -- تنشيط لو منتهي
        i_pub = 1,
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'ren', 'duration_days', 30);

    WHEN 'pin' THEN
      UPDATE offers SET
        i_pin = 1,
        pin_end = v_now + INTERVAL '7 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'pin', 'duration_days', 7);

    WHEN 'bst' THEN
      UPDATE offers SET
        i_bst = 1,
        bst_end = v_now + INTERVAL '14 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'bst', 'duration_days', 14);

    WHEN 'dsc5' THEN
      UPDATE offers SET
        dsc_pct = 5,
        dsc_end = v_now + INTERVAL '60 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'dsc5', 'discount_pct', 5);

    WHEN 'fms' THEN
      UPDATE offers SET
        i_fms = 1,
        fms_end = v_now + INTERVAL '30 days',
        ts_upd = v_now
      WHERE id = p_offer_id;
      v_result := jsonb_build_object('boost_type', 'fms', 'duration_days', 30);

    ELSE
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_BOOST_TYPE');
  END CASE;

  -- 4) خصم النقاط
  UPDATE users SET
    pt = pt - p_cost,
    ts_upd = v_now
  WHERE id = p_uid;

  -- 5) تسجيل في activity_log
  INSERT INTO activity_log (uid, action, details, ts_crt)
  VALUES (
    p_uid,
    'offer_boost',
    jsonb_build_object(
      'offer_id', p_offer_id,
      'boost_type', p_boost_type,
      'cost', p_cost
    ),
    v_now
  );

  RETURN jsonb_build_object('success', true, 'result', v_result, 'new_balance', v_user_pts - p_cost);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION purchase_offer_boost TO anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) RPC: expire_offer_boosts (يُستدعى يومياً مع cron)
-- ─────────────────────────────────────────────────────────────────────────────
-- يلغي تلقائياً الترقيات المنتهية
CREATE OR REPLACE FUNCTION expire_offer_boosts()
RETURNS INTEGER AS $$
DECLARE v_count INTEGER := 0;
BEGIN
  -- إلغاء pin المنتهي
  UPDATE offers SET i_pin = 0, pin_end = NULL
    WHERE i_pin = 1 AND pin_end < NOW();
  GET DIAGNOSTICS v_count = ROW_COUNT;

  -- إلغاء boost المنتهي
  UPDATE offers SET i_bst = 0, bst_end = NULL
    WHERE i_bst = 1 AND bst_end < NOW();

  -- إلغاء featured المنتهي
  UPDATE offers SET i_fms = 0, fms_end = NULL
    WHERE i_fms = 1 AND fms_end < NOW();

  -- إلغاء الخصم المنتهي
  UPDATE offers SET dsc_pct = 0, dsc_end = NULL
    WHERE dsc_pct > 0 AND dsc_end < NOW();

  RETURN v_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION expire_offer_boosts TO anon, authenticated;
