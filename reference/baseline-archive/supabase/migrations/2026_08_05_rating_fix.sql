-- ============================================================================
-- 🔧 إصلاح تقييم التجربة - تحسين trigger check_rating_valid (Bug #28)
-- ============================================================================
--
-- المشكلة: تقييم التجربة من المستخدم يفشل بالإرسال
-- السبب: trigger check_rating_valid معقد جداً وقد يفشل في بعض الحالات
--
-- الحل: تبسيط الـ trigger وتحسين معالجة الأخطاء
-- ============================================================================

DROP TRIGGER IF EXISTS trg_rating_valid ON ratings;
DROP FUNCTION IF EXISTS check_rating_valid();

CREATE OR REPLACE FUNCTION check_rating_valid()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_has_interaction BOOLEAN;
  v_error_msg TEXT;
BEGIN
  -- ✅ Bug #28: تبسيط التحقق من التفاعل بين المُقيِّم والمستهدف
  
  -- التحقق 1: هل المُقيِّم هو نفسه المستهدف؟ (لا يمكن تقييم النفس)
  IF NEW.reviewer_uid = NEW.target_uid THEN
    RAISE EXCEPTION 'CANNOT_RATE_SELF';
  END IF;
  
  -- التحقق 2: هل النجوم بين 1 و 5؟
  IF NEW.stars < 1 OR NEW.stars > 5 THEN
    RAISE EXCEPTION 'INVALID_STARS';
  END IF;
  
  -- التحقق 3: هل هناك تفاعل فعلي بين الطرفين؟
  -- (أ) موعد منتهٍ على عرض يملكه المستهدف
  SELECT EXISTS (
    SELECT 1 FROM appointments a
    JOIN offers o ON o.id = a.off_id
    WHERE o.usr_id = NEW.target_uid
      AND a.sts = 2  -- منتهٍ
      AND (a.req_uid = NEW.reviewer_uid OR a.bkr_id = NEW.reviewer_uid)
  ) INTO v_has_interaction;
  
  -- (ب) أو صفقة بين الطرفين
  IF NOT v_has_interaction THEN
    SELECT EXISTS (
      SELECT 1 FROM deals d
      WHERE d.sts = 1  -- مكتملة
        AND ((d.sell_uid = NEW.target_uid AND d.buy_uid = NEW.reviewer_uid)
          OR (d.buy_uid = NEW.target_uid AND d.sell_uid = NEW.reviewer_uid)
          OR (d.bkr_uid = NEW.reviewer_uid 
              AND (d.sell_uid = NEW.target_uid OR d.buy_uid = NEW.target_uid)))
    ) INTO v_has_interaction;
  END IF;
  
  -- (ج) أو المُقيِّم هو الوسيط في عرض للمستهدف
  IF NOT v_has_interaction THEN
    SELECT EXISTS (
      SELECT 1 FROM offers o
      JOIN appointments a ON a.off_id = o.id
      WHERE o.usr_id = NEW.target_uid
        AND a.bkr_id = NEW.reviewer_uid
        AND a.sts IN (1, 2)  -- مؤكد أو منتهٍ
    ) INTO v_has_interaction;
  END IF;
  
  -- إذا لم يكن هناك تفاعل، نرفض التقييم
  IF NOT v_has_interaction THEN
    v_error_msg := 'NO_INTERACTION: لا يمكن التقييم قبل إتمام موعد أو صفقة مع هذا الطرف.';
    RAISE EXCEPTION '%', v_error_msg;
  END IF;
  
  RETURN NEW;
END;
$$;

-- إعادة إنشاء الـ trigger
CREATE TRIGGER trg_rating_valid
BEFORE INSERT ON ratings
FOR EACH ROW
EXECUTE FUNCTION check_rating_valid();

-- تحصين الـ function
REVOKE ALL ON FUNCTION check_rating_valid() FROM PUBLIC;
REVOKE ALL ON FUNCTION check_rating_valid() FROM anon;
REVOKE ALL ON FUNCTION check_rating_valid() FROM authenticated;
GRANT EXECUTE ON FUNCTION check_rating_valid() TO service_role;
