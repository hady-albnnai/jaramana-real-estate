-- ════════════════════════════════════════════════════════════════════════════
-- إصلاحات نهائية — دورة حياة العرض — 2026-06-12
-- ════════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────
-- 1. expire_offers — فقط المنشور ينتهي (sts=2)، قيد المراجعة (sts=1) لا ينتهي
-- ──────────────────────────────────────
CREATE OR REPLACE FUNCTION expire_offers()
RETURNS VOID AS $$
BEGIN
  UPDATE offers
  SET sts = 4, ts_end = NOW()
  WHERE sts = 2
    AND i_del = 0
    AND ts_crt < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;

-- ──────────────────────────────────────
-- 2. mark_social_published_internal — حذف ts_upd (العمود غير موجود بـ offers)
-- ──────────────────────────────────────
DROP FUNCTION IF EXISTS mark_social_published_internal(UUID, UUID, TEXT);

CREATE OR REPLACE FUNCTION mark_social_published_internal(
  p_user_uid UUID,
  p_offer_id UUID,
  p_text TEXT
) RETURNS BOOLEAN AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  UPDATE offers
  SET soc_pub = 1,
      soc_txt = COALESCE(p_text, '')
  WHERE id = p_offer_id
    AND usr_id = p_user_uid
    AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION mark_social_published_internal(UUID, UUID, TEXT) TO anon, authenticated;

-- ──────────────────────────────────────
-- 3. process_completion_request — عند الرفض: إرجاع العرض من sts=5 إلى sts=2
--    (لأن الموافقة المبدئية حوّلته لمحجوز عبر request_completion_by_appointment)
-- ──────────────────────────────────────
-- ملاحظة: الدالة أُعيد كتابتها بالكامل بالملف السابق (booking_overhaul)
-- هنا نعيد كتابتها مع إضافة إرجاع العرض عند الرفض

DROP FUNCTION IF EXISTS process_completion_request(UUID, UUID, TEXT, TEXT);

CREATE OR REPLACE FUNCTION process_completion_request(
  p_admin_uid    UUID,
  p_request_id   UUID,
  p_decision     TEXT,
  p_office_notes TEXT DEFAULT ''
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_role    INT;
  v_req     RECORD;
  v_off_id  UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT * INTO v_req FROM completion_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF v_req.decision <> 'pending' THEN RAISE EXCEPTION 'REQUEST_ALREADY_PROCESSED'; END IF;

  -- تحديث طلب الإتمام
  UPDATE completion_requests
  SET decision = p_decision,
      decided_by = p_admin_uid,
      office_notes = COALESCE(p_office_notes, ''),
      ts_decided = NOW()
  WHERE id = p_request_id;

  -- جلب offer_id من الموعد
  SELECT off_id INTO v_off_id FROM appointments WHERE id = v_req.app_id;

  IF p_decision = 'approved' THEN
    -- تحديث الموعد المعتمد
    UPDATE appointments SET sts = 2 WHERE id = v_req.app_id AND sts <> 2;

    -- تحويل العرض إلى محجوز + إخفاء من القوائم
    UPDATE offers SET sts = 5, i_pub = 0 WHERE id = v_off_id AND sts IN (2, 5);

    -- إلغاء كل المواعيد الأخرى على نفس العرض
    UPDATE appointments
    SET sts = 3,
        cnl_rsn = 'تم إتمام معاملة على هذا العرض',
        dt_end = NOW()
    WHERE off_id = v_off_id
      AND id <> v_req.app_id
      AND sts IN (0, 1);

    -- إشعار أصحاب المواعيد الملغاة
    INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
    SELECT a.req_uid, 0, 'تم إلغاء موعدك',
           'تم إلغاء موعدك لأن العرض اكتمل بمعاملة أخرى.',
           a.id, NOW()
    FROM appointments a
    WHERE a.off_id = v_off_id
      AND a.id <> v_req.app_id
      AND a.sts = 3
      AND a.cnl_rsn = 'تم إتمام معاملة على هذا العرض';

  ELSIF p_decision = 'rejected' THEN
    -- تحديث الموعد
    UPDATE appointments
    SET sts = 4, outcome = 'reject'
    WHERE id = v_req.app_id;

    -- إرجاع العرض من محجوز إلى منشور (لو كان تحوّل بالخطأ أو مبدئياً)
    UPDATE offers SET sts = 2, i_pub = 1 WHERE id = v_off_id AND sts = 5;
  END IF;

  -- إشعار المنفذ بالنتيجة
  INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
  VALUES (
    v_req.req_by, 20,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب الإتمام'
         ELSE 'تم رفض طلب الإتمام' END,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب إتمام المعاملة ✓'
         ELSE 'تم رفض طلب الإتمام: ' || COALESCE(p_office_notes, '') END,
    v_req.app_id, NOW()
  );

  RETURN TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION process_completion_request(UUID, UUID, TEXT, TEXT) TO anon, authenticated;
