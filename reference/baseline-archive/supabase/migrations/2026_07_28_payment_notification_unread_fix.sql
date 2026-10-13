-- ============================================================
-- إصلاح تظهير «غير مقروء» بالدفع (2026-07-28)
-- القبول (sts=1): i_rd=0 ← ينوّر ✅
-- الرفض  (sts=2): i_rd=1 ← لا ينوّر (يظهر بالسجل فقط)
-- ============================================================

CREATE OR REPLACE FUNCTION public.trg_payment_approved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_pkg_name TEXT;
  v_reason TEXT;
  v_unread INT;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;

  v_pkg_name := CASE NEW.pkg
    WHEN 1 THEN 'الفضية'
    WHEN 2 THEN 'الذهبية'
    ELSE 'المجانية'
  END;

  IF NEW.sts = 1 THEN
    -- ✅ قبول: ينوّر (غير مقروء)
    v_title := '✅ تم تفعيل اشتراكك';
    v_body := 'تم تفعيل الباقة ' || v_pkg_name || ' بنجاح. استمتع بالمزايا الجديدة!';
    v_unread := 0;
  ELSIF NEW.sts = 2 THEN
    -- ❌ رفض: لا ينوّر (مقروء)
    v_title := '❌ تم رفض الدفعة';
    v_reason := COALESCE(NULLIF(BTRIM(COALESCE(NEW.meta->>'reject_reason', '')), ''), '');
    IF v_reason <> '' THEN
      v_body := 'لم تُقبل الدفعة — السبب: ' || LEFT(v_reason, 140) ||
                ' · صحّح البيانات وأعد الطلب من «سجل دفعاتي».';
    ELSE
      v_body := 'لم تُقبل الدفعة. يرجى مراجعة بيانات الدفع والمحاولة مرة أخرى.';
    END IF;
    v_unread := 1;  -- ❌ مقروء: لا ينوّر
  ELSE
    RETURN NEW;
  END IF;

  -- إدراج مباشر (بدل notify_user) للتحكم بـ i_rd
  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
  VALUES (NEW.uid, 3, v_title, v_body, NEW.id::text, 'payment', v_unread, 0, NOW());

  PERFORM public.send_push_notification(
    NEW.uid, v_title, v_body,
    jsonb_build_object('type', 'payment', 'id', NEW.id::text)
  );

  RETURN NEW;
END;
$$;

-- رباعي التحصين (موجود سلفاً، لكن تأكيد)
REVOKE ALL ON FUNCTION public.trg_payment_approved() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_payment_approved() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_payment_approved() TO service_role;

-- ══ تحقق مدمج ══
-- فحص أن التريغر لا يزال مربوطاً والبحث_path مثبت:
SELECT tgname, tgrelid::regclass AS tbl, tgenabled
FROM pg_trigger WHERE tgname = 'trg_payment_approved';

SELECT p.proname, p.prosecdef,
  EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%') AS pinned
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'trg_payment_approved';
