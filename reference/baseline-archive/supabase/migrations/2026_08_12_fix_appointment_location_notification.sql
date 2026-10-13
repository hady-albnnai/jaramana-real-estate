-- إصلاح إشعار قبول الموعد: استخدام اسم المنطقة بدلاً من الإحداثيات
CREATE OR REPLACE FUNCTION public.trg_appt_accept_enrich()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_appt RECORD;
  v_offer RECORD;
  v_sup RECORD;
  v_addr TEXT;
  v_date TEXT;
  v_time TEXT;
BEGIN
  IF NEW.act IS DISTINCT FROM 'appointment' THEN RETURN NEW; END IF;
  IF NEW.ttl IS NULL OR NEW.ttl NOT LIKE '✅ تم تأكيد موعدك%' THEN RETURN NEW; END IF;
  IF NEW.bdy IS NOT NULL AND NEW.bdy LIKE '%يرجى الحضور إلى موقع العرض%' THEN RETURN NEW; END IF;

  SELECT a.off_id, a.dt, a.supervisor_uid INTO v_appt
  FROM public.appointments a WHERE a.id::TEXT = NEW.ref_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT o.ttl, o.loc, o.exact_loc INTO v_offer
  FROM public.offers o WHERE o.id = v_appt.off_id;

  -- ✅ الأولوية: اسم المنطقة + وصف الموقع (loc) وليس الإحداثيات
  v_addr := NULLIF(BTRIM(CONCAT_WS(' — ',
    NULLIF(TRIM(COALESCE(v_offer.loc->>'city', '')), ''),
    NULLIF(TRIM(COALESCE(v_offer.loc->>'d', '')), ''))), '');
  v_addr := COALESCE(v_addr, 'يُحدَّد بالاتصال مع المشرف');

  v_date := to_char(v_appt.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD');
  v_time := to_char(v_appt.dt AT TIME ZONE 'Asia/Damascus', 'HH24:MI');

  SELECT u.nm, u.ph INTO v_sup FROM public.users u WHERE u.id = v_appt.supervisor_uid;

  UPDATE public.notifications SET bdy =
    'يرجى الحضور إلى موقع العرض المطلوب والمحدد بـ: ' || v_addr ||
    ' وذلك بتاريخ ' || v_date || ' الساعة ' || v_time || '.' ||
    CASE WHEN v_sup.nm IS NOT NULL THEN
      ' يرجى التواصل على رقم المشرف ' || v_sup.nm || ' — ' || COALESCE(NULLIF(v_sup.ph, ''), 'يُوافى به قريباً') ||
      ' قبل ساعة كاملة من الموعد لتلافي أي سوء تنسيق.'
    ELSE
      ' سيوافيك المكتب ببيانات المشرف المخصص قبل الموعد.'
    END
  WHERE id = NEW.id;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.trg_appt_accept_enrich() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_appt_accept_enrich() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_appt_accept_enrich() TO service_role;
