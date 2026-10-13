-- ════════════════════════════════════════════════════════════════════════════
-- إصلاحات التدقيق العميق — 2026-06-12
-- ════════════════════════════════════════════════════════════════════════════
-- المشاكل:
--   1. approve_payment_final: role >= 2 → role >= 5
--   2. create_offer_internal: إعفاء الحصة role >= 2 → role >= 4
--   3. RLS policies: role >= 2 → role >= 4 على 8 جداول
--   4. photography_tasks RLS: role >= 2 → role >= 4
-- ════════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────
-- 1. approve_payment_final — نائب/مدير فقط (role >= 5)
-- ──────────────────────────────────────
DROP FUNCTION IF EXISTS approve_payment_final(uuid, uuid);

CREATE OR REPLACE FUNCTION approve_payment_final(
  p_payment_id UUID,
  p_admin_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_user_id UUID;
  v_pkg_id INT;
  v_pkg_duration INT;
  v_grace_days INT;
  v_config JSONB;
  v_admin_role INT;
  v_payment_status INT;
  v_payment_type INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;

  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_id AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;

  SELECT uid, pkg, sts, tp INTO v_user_id, v_pkg_id, v_payment_status, v_payment_type
  FROM payments WHERE id = p_payment_id;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND');
  END IF;
  IF COALESCE(v_payment_status, -1) <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_PENDING');
  END IF;
  IF COALESCE(v_payment_type, -1) <> 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_PAYMENT_TYPE');
  END IF;

  SELECT value INTO v_config FROM app_config WHERE key = 'main';
  v_pkg_duration := (v_config->'pkg'->(v_pkg_id::text)->>'d')::INT;
  v_grace_days := COALESCE((v_config->'pkg'->>'grace_days')::INT, 3);

  IF v_pkg_duration IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'PKG_DURATION_NOT_FOUND');
  END IF;

  UPDATE payments
  SET sts = 1, appr_by = p_admin_id
  WHERE id = p_payment_id AND sts = 0;

  UPDATE users
  SET b_pkg = v_pkg_id,
      pkg_end = GREATEST(COALESCE(pkg_end, NOW()), NOW()) + (v_pkg_duration || ' days')::interval,
      pkg_grace = GREATEST(COALESCE(pkg_end, NOW()), NOW()) + ((v_pkg_duration + v_grace_days) || ' days')::interval,
      ts_upd = NOW()
  WHERE id = v_user_id;

  RETURN jsonb_build_object('success', true, 'message', 'Package activated', 'duration', v_pkg_duration);
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION approve_payment_final(UUID, UUID) TO authenticated;

-- ──────────────────────────────────────
-- 2. create_offer_internal — إعفاء الحصة role >= 4
-- ──────────────────────────────────────
-- لا نعيد كتابة الدالة كاملة — نحدّث الشرط فقط عبر إعادة الإنشاء
-- الفرق الوحيد: سطر role < 2 → role < 4

DROP FUNCTION IF EXISTS create_offer_internal(uuid, jsonb);

CREATE OR REPLACE FUNCTION create_offer_internal(
  p_user_uid UUID,
  p_offer JSONB
) RETURNS SETOF offers AS $$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_recent_deleted INT;
  v_duplicate BOOLEAN;
  v_effective_pkg INT;
BEGIN
  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND'; END IF;

  IF COALESCE(trim(p_offer->>'ttl'), '') = '' THEN RAISE EXCEPTION 'TITLE_REQUIRED'; END IF;
  IF COALESCE(trim(p_offer->>'contact_ph'), '') = '' THEN RAISE EXCEPTION 'CONTACT_PHONE_REQUIRED'; END IF;
  IF COALESCE((p_offer->>'prc')::NUMERIC, 0) <= 0 THEN RAISE EXCEPTION 'INVALID_PRICE'; END IF;

  -- الإدارة الداخلية (موظف مكتب فما فوق) غير مقيّدة بحصة
  IF COALESCE(v_user.role, 0) < 4 THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';

    -- فحص انتهاء الباقة
    v_effective_pkg := CASE
      WHEN COALESCE(v_user.b_pkg, 0) = 0 THEN 0
      WHEN v_user.pkg_grace IS NOT NULL AND v_user.pkg_grace > NOW() THEN v_user.b_pkg
      WHEN v_user.pkg_end IS NOT NULL AND v_user.pkg_end > NOW() THEN v_user.b_pkg
      ELSE 0
    END;

    v_limit := COALESCE((v_config->'pkg'->(v_effective_pkg::TEXT)->>'o')::INT,
      CASE WHEN COALESCE(v_user.role, 0) = 1 THEN 5 ELSE 1 END);

    SELECT COUNT(*) INTO v_used FROM offers
    WHERE usr_id = p_user_uid AND i_del = 0 AND sts IN (0, 1, 2, 5);

    SELECT COUNT(*) INTO v_recent_deleted FROM offers
    WHERE usr_id = p_user_uid AND i_del = 1 AND ts_crt >= NOW() - INTERVAL '24 hours';

    v_used := COALESCE(v_used, 0) + COALESCE(v_recent_deleted, 0);
    IF v_used >= v_limit THEN RAISE EXCEPTION 'QUOTA_EXCEEDED'; END IF;
  END IF;

  SELECT check_offer_duplicate(
    COALESCE(p_offer->>'ttl', ''),
    COALESCE((p_offer->>'prc')::NUMERIC, 0),
    COALESCE(p_offer->'loc', '{"r":0,"d":""}'::jsonb),
    p_user_uid
  ) INTO v_duplicate;
  IF v_duplicate THEN RAISE EXCEPTION 'DUPLICATE_OFFER'; END IF;

  RETURN QUERY
  INSERT INTO offers (
    usr_id, brk_id, brk_pct, typ, trx, cat, sub, contact_ph,
    ttl, prc, cur, loc, descript, imgs, vdo, doc_tp, doc_img,
    exact_loc, specs, com, sts, rsn, vws, fvs, i_pub, i_soc,
    soc_pub, soc_txt, i_dup, dup_of, avl, i_del, ts_crt, ts_pub, ts_end, ts_ren, added_by
  ) VALUES (
    p_user_uid,
    NULLIF(p_offer->>'brk_id', '')::UUID,
    COALESCE((p_offer->>'brk_pct')::NUMERIC, 0),
    COALESCE((p_offer->>'typ')::INT, 0),
    COALESCE((p_offer->>'trx')::INT, 0),
    COALESCE((p_offer->>'cat')::INT, 0),
    COALESCE((p_offer->>'sub')::INT, 0),
    COALESCE(p_offer->>'contact_ph', ''),
    COALESCE(p_offer->>'ttl', ''),
    COALESCE((p_offer->>'prc')::NUMERIC, 0),
    COALESCE((p_offer->>'cur')::INT, 0),
    COALESCE(p_offer->'loc', '{}'::jsonb),
    COALESCE(p_offer->>'descript', ''),
    COALESCE(p_offer->'imgs', '[]'::jsonb),
    COALESCE(p_offer->>'vdo', ''),
    COALESCE((p_offer->>'doc_tp')::INT, 0),
    COALESCE(p_offer->>'doc_img', ''),
    COALESCE(p_offer->>'exact_loc', ''),
    COALESCE(p_offer->'specs', '{}'::jsonb),
    COALESCE((p_offer->>'com')::NUMERIC, 0),
    1,  -- sts = قيد المراجعة
    '',
    0, 0, 0, 0, 0, '', 0, NULL,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    0,
    NOW(), NULL, NULL, NULL,
    CASE WHEN COALESCE(v_user.role, 0) >= 4 THEN p_user_uid ELSE NULL END
  )
  RETURNING *;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION create_offer_internal(UUID, JSONB) TO anon, authenticated;

-- ──────────────────────────────────────
-- 3. RLS policies — role >= 2 → role >= 4
-- ──────────────────────────────────────

-- app_config: الكتابة للموظف فما فوق
DROP POLICY IF EXISTS "Admin can write config" ON app_config;
CREATE POLICY "Admin can write config" ON app_config FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 6));

-- offers: القراءة الإدارية
DROP POLICY IF EXISTS "Anyone can read published offers" ON offers;
CREATE POLICY "Anyone can read published offers" ON offers FOR SELECT
  USING (i_del = 0 AND (i_pub = 1 OR auth.uid() = usr_id
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4)));

-- offers: التعديل
DROP POLICY IF EXISTS "Admin can update offers" ON offers;
CREATE POLICY "Admin can update offers" ON offers FOR UPDATE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4) OR auth.uid() = usr_id);

-- activity_log
DROP POLICY IF EXISTS "Admin can read activity log" ON activity_log;
CREATE POLICY "Admin can read activity log" ON activity_log FOR SELECT
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4));

-- payments
DROP POLICY IF EXISTS "Admin can update payments" ON payments;
CREATE POLICY "Admin can update payments" ON payments FOR UPDATE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 5));

-- reports
DROP POLICY IF EXISTS "Admin can update reports" ON reports;
CREATE POLICY "Admin can update reports" ON reports FOR UPDATE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4));

-- deals
DROP POLICY IF EXISTS "Admin can update deals" ON deals;
CREATE POLICY "Admin can update deals" ON deals FOR UPDATE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 5));

-- appointments
DROP POLICY IF EXISTS "Admin can update appointments" ON appointments;
CREATE POLICY "Admin can update appointments" ON appointments FOR UPDATE
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4));

-- ──────────────────────────────────────
-- 4. photography_tasks RLS — role >= 4
-- ──────────────────────────────────────
DROP POLICY IF EXISTS "Photography tasks read" ON photography_tasks;
CREATE POLICY "Photography tasks read" ON photography_tasks FOR SELECT
  USING (
    photographer_id = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4 AND i_del = 0)
  );

DROP POLICY IF EXISTS "Admin can insert photography tasks" ON photography_tasks;
CREATE POLICY "Admin can insert photography tasks" ON photography_tasks FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4 AND i_del = 0)
  );

DROP POLICY IF EXISTS "Admin or photographer can update photography tasks" ON photography_tasks;
CREATE POLICY "Admin or photographer can update photography tasks" ON photography_tasks FOR UPDATE
  USING (
    photographer_id = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role >= 4 AND i_del = 0)
  );

-- ════════════════════════════════════════════════════════════════════════════
-- ✅ ملخص الحدود النهائية:
--   role >= 4 (موظف مكتب): عمليات إدارية عامة + RLS
--   role >= 5 (نائب مدير): مدفوعات + صفقات + تحليلات + صلاحيات
--   role >= 6 (مدير): إعدادات التطبيق (app_config)
-- ════════════════════════════════════════════════════════════════════════════
