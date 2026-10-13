-- ============================================================================
-- 🔧 إصلاح طلب التصوير - عدم ظهوره كعرض جديد (Bug #24)
-- ============================================================================
--
-- المشكلة:
-- 1. عند إضافة طلب تصوير جديد، يتم إرسال إشعار بعرض جديد (خطأ)
-- 2. طلب التصوير يظهر كعرض مضاف في مراجعة العروض (خطأ)
--
-- السبب:
-- - RPC get_admin_offers_internal يجلب جميع العروض بدون تمييز
-- - لا يوجد فلتر لاستبعاد العروض المرتبطة بطلبات التصوير
--
-- الحل:
-- - تحديث RPC لاستبعاد العروض المرتبطة بطلبات التصوير (sts = 1)
-- - العروض المرتبطة بطلبات التصوير يجب أن تظهر فقط في شاشة إدارة التصوير
-- ============================================================================

DROP FUNCTION IF EXISTS get_admin_offers_internal(UUID, INT);

CREATE OR REPLACE FUNCTION get_admin_offers_internal(
  p_admin_uid UUID, 
  p_limit INT DEFAULT 100
)
RETURNS SETOF offers 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE 
  v_role INT;
BEGIN
  -- التحقق من الصلاحيات
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN 
    RAISE EXCEPTION 'AUTH_MISMATCH'; 
  END IF;
  
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 3 THEN 
    RAISE EXCEPTION 'NOT_AUTHORIZED'; 
  END IF;
  
  -- ✅ استبعاد العروض المرتبطة بطلبات التصوير (sts = 1)
  -- هذه العروض تظهر فقط في شاشة إدارة التصوير، وليس في مراجعة العروض
  RETURN QUERY 
  SELECT * FROM offers 
  WHERE i_del = 0 
    AND NOT EXISTS (
      SELECT 1 FROM photography_tasks pt
      WHERE pt.off_id = offers.id
        AND pt.sts = 1  -- قيد التنفيذ
    )
  ORDER BY ts_crt DESC 
  LIMIT p_limit;
END;
$$;

-- تحصين الـ RPC
REVOKE ALL ON FUNCTION get_admin_offers_internal(UUID, INT) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_admin_offers_internal(UUID, INT) FROM anon;
REVOKE ALL ON FUNCTION get_admin_offers_internal(UUID, INT) FROM authenticated;
GRANT EXECUTE ON FUNCTION get_admin_offers_internal(UUID, INT) TO service_role;

-- ============================================================================
-- 🔔 إصلاح إشعارات العروض المرتبطة بطلبات التصوير
-- ============================================================================
--
-- المشكلة: عند إنشاء عرض مرتبط بطلب تصوير، يتم إرسال إشعار بعرض جديد
-- الحل: تحديث trigger trg_offer_status_changed لاستبعاد العروض المرتبطة بطلبات التصوير

DROP TRIGGER IF EXISTS trg_offer_status_changed ON offers;
DROP FUNCTION IF EXISTS trg_offer_status_changed();

CREATE OR REPLACE FUNCTION trg_offer_status_changed()
RETURNS TRIGGER 
LANGUAGE plpgsql 
SECURITY DEFINER 
SET search_path TO public, extensions, pg_temp
AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_has_photography_task BOOLEAN;
BEGIN
  -- التحقق من تغيير الحالة
  IF NEW.sts = OLD.sts THEN 
    RETURN NEW; 
  END IF;
  
  -- ✅ التحقق من وجود طلب تصوير مرتبط
  SELECT EXISTS (
    SELECT 1 FROM photography_tasks pt
    WHERE pt.off_id = NEW.id
  ) INTO v_has_photography_task;
  
  -- ✅ إذا كان العرض مرتبطاً بطلب تصوير، لا نرسل إشعار بعرض جديد
  -- لأن الإشعارات الخاصة بالتصوير تُرسل من triggers التصوير
  IF v_has_photography_task AND NEW.sts = 1 THEN
    RETURN NEW;
  END IF;
  
  -- إرسال الإشعارات العادية
  CASE NEW.sts
    WHEN 1 THEN -- قيد المراجعة
      v_title := '📝 عرض جديد بانتظار المراجعة';
      v_body := 'تم إضافة عرض جديد وهو بانتظار المراجعة والموافقة.';
      
      -- إشعار للإدارة
      PERFORM notify_user(
        (SELECT id FROM users WHERE role >= 2 AND sts = 0 AND i_del = 0 ORDER BY ts_crt ASC LIMIT 1),
        1,
        v_title,
        v_body,
        NEW.id::text,
        'offer_pending'
      );
      
    WHEN 2 THEN -- منشور
      v_title := '✅ تم نشر العرض الخاص بك';
      v_body := 'تمت الموافقة على العرض الخاص بك ونشره بنجاح. يمكنك الآن تلقي طلبات المعاينة.';
      
      -- إشعار لصاحب العرض
      PERFORM notify_user(
        NEW.usr_id,
        1,
        v_title,
        v_body,
        NEW.id::text,
        'offer_approved'
      );
      
    WHEN 3 THEN -- مرفوض
      v_title := '❌ تم رفض العرض الخاص بك';
      v_body := 'لم تتم الموافقة على العرض الخاص بك. السبب: ' || COALESCE(NEW.rsn, 'غير محدد');
      
      -- إشعار لصاحب العرض
      PERFORM notify_user(
        NEW.usr_id,
        1,
        v_title,
        v_body,
        NEW.id::text,
        'offer_rejected'
      );
      
    WHEN 5 THEN -- منتهي
      v_title := '⏰ انتهى العرض الخاص بك';
      v_body := 'انتهت صلاحية العرض الخاص بك. يمكنك تجديده من صفحة عروضي.';
      
      -- إشعار لصاحب العرض
      PERFORM notify_user(
        NEW.usr_id,
        1,
        v_title,
        v_body,
        NEW.id::text,
        'offer_expired'
      );
  END CASE;
  
  RETURN NEW;
END;
$$;

-- إعادة إنشاء الـ trigger
CREATE TRIGGER trg_offer_status_changed
AFTER UPDATE OF sts ON offers
FOR EACH ROW
EXECUTE FUNCTION trg_offer_status_changed();

-- تحصين الـ trigger
REVOKE ALL ON FUNCTION trg_offer_status_changed() FROM PUBLIC;
