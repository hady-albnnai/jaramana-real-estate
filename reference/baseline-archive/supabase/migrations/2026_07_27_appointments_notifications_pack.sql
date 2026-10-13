-- ============================================================
-- رزمة إشعارات المواعيد الثلاثية (موافقة المالك «أوافق على الثلاثة» — 2026-07-27)
-- (أ) تغنيَة إشعار قبول الموعد بنص المالك حرفياً: العنوان التفصيلي + التاريخ/الساعة
--     + المشرف ورقم هاتفه + «تواصل قبل ساعة كاملة» — دون لمس owner_respond_appointment
--     الحيّة (تريغر AFTER INSERT على notifications يعيد كتابة النص ذرّياً)
-- (ب) التذكيرات الفعلية: 24س + 2س + 15د لكلا الطرفين (الطالب + المشرف) — بدل الأعلام
--     الصامتة. دالة send_appointment_reminders تعاد كتابتها (تقلب العلم + تبني الإشعار
--     بذات الاستعلام، فالعَلِم يضمن عدم التكرار) + cron يُرفع دقته إلى */15 دقيقة.
-- (ج) إشعار المشرف المُسنَد لحظة الحجز (سدّ فجوة «المشرف الأعمى» المُثبتة حيّاً)
-- idempotent بالكامل + رباعي التحصين (الدستور §7) + تحقق SELECTs مدمجة بالأسفل
-- ============================================================

-- ── (أ) 1/4: دالة تغنيَة إشعار القبول ──────────────────────────
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
  -- صف إشعار قبول الموعد فقط (المصدر: owner_respond_appointment الحيّة)
  IF NEW.act IS DISTINCT FROM 'appointment' THEN RETURN NEW; END IF;
  IF NEW.ttl IS NULL OR NEW.ttl NOT LIKE '✅ تم تأكيد موعدك%' THEN RETURN NEW; END IF;
  -- idempotent: إن كان النص قد غُنّي سلفاً لا نعيد
  IF NEW.bdy IS NOT NULL AND NEW.bdy LIKE '%يرجى الحضور إلى موقع العرض%' THEN RETURN NEW; END IF;

  SELECT a.off_id, a.dt, a.supervisor_uid INTO v_appt
  FROM public.appointments a WHERE a.id::TEXT = NEW.ref_id;
  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT o.ttl, o.loc, o.exact_loc INTO v_offer
  FROM public.offers o WHERE o.id = v_appt.off_id;

  -- العنوان التفصيلي: exact_loc المكتوب بحر اليد أولاً (يحوي التفاصيل عادةً)،
  -- وإلا بناء من الحقول المهيكلة (المدينة + الحي)، وإلا «يُحدَّد بالاتصال»
  v_addr := NULLIF(TRIM(COALESCE(v_offer.exact_loc, '')), '');
  IF v_addr IS NULL THEN
    v_addr := NULLIF(BTRIM(CONCAT_WS(' — ',
      NULLIF(TRIM(COALESCE(v_offer.loc->>'city', '')), ''),
      NULLIF(TRIM(COALESCE(v_offer.loc->>'d', '')), ''))), '');
  END IF;
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

DROP TRIGGER IF EXISTS trg_appt_accept_enrich ON public.notifications;
CREATE TRIGGER trg_appt_accept_enrich
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_appt_accept_enrich();

REVOKE ALL ON FUNCTION public.trg_appt_accept_enrich() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_appt_accept_enrich() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_appt_accept_enrich() TO service_role;

-- ── (ج) دالة إشعار المشرف المُسنَد لحظة الحجز ─────────────────
CREATE OR REPLACE FUNCTION public.trg_appt_notify_supervisor()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_offer RECORD;
  v_addr TEXT;
  v_date TEXT;
  v_time TEXT;
BEGIN
  -- حجز جديد بمشرف مُسنَد فقط (إلغاء/تعديلات لاحقة لا تشغّل INSERT trigger)
  IF NEW.supervisor_uid IS NULL THEN RETURN NEW; END IF;

  SELECT o.ttl, o.loc, o.exact_loc INTO v_offer
  FROM public.offers o WHERE o.id = NEW.off_id;

  v_addr := NULLIF(TRIM(COALESCE(v_offer.exact_loc, '')), '');
  IF v_addr IS NULL THEN
    v_addr := NULLIF(BTRIM(CONCAT_WS(' — ',
      NULLIF(TRIM(COALESCE(v_offer.loc->>'city', '')), ''),
      NULLIF(TRIM(COALESCE(v_offer.loc->>'d', '')), ''))), '');
  END IF;

  v_date := to_char(NEW.dt AT TIME ZONE 'Asia/Damascus', 'YYYY/MM/DD');
  v_time := to_char(NEW.dt AT TIME ZONE 'Asia/Damascus', 'HH24:MI');

  INSERT INTO public.notifications (uid, tp, ttl, bdy, act, ref_id, i_rd, ts_crt)
  VALUES (
    NEW.supervisor_uid, 2,
    '📋 أُسند إليك موعد معاينة',
    'موعد معاينة لعرض «' || COALESCE(v_offer.ttl, '—') || '» بتاريخ ' || v_date ||
    ' الساعة ' || v_time ||
    CASE WHEN v_addr IS NOT NULL THEN ' — الموقع: ' || v_addr ELSE '' END || '.',
    'appointment', NEW.id::TEXT, 0, NOW()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_appt_notify_supervisor ON public.appointments;
CREATE TRIGGER trg_appt_notify_supervisor
  AFTER INSERT ON public.appointments
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_appt_notify_supervisor();

REVOKE ALL ON FUNCTION public.trg_appt_notify_supervisor() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_appt_notify_supervisor() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_appt_notify_supervisor() TO service_role;

-- ── (ب) إعادة بناء send_appointment_reminders: أعلام حيّة تنبض إشعارات ──
CREATE OR REPLACE FUNCTION public.send_appointment_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v INT;
BEGIN
  -- لكل عتبة: نفس النمط — UPDATE يقلب العلم ويُرجع الصفوف المتأثرة،
  -- فتُبنى إشعارات لها فقط (العَلَم نفسه يضمن الإرسال مرة واحدة بالعمر).
  -- المواعيد المقبولة فقط (sts=1): التذكير عن موعد غير مؤكد عبث تنسيقي.
  FOR v IN
    WITH due AS (
      UPDATE public.appointments SET rmnd_24 = 1
      WHERE sts = 1 AND i_force = 0
        AND dt > NOW() AND dt <= NOW() + INTERVAL '24 hours' AND rmnd_24 = 0
      RETURNING id, req_uid, supervisor_uid, off_id, dt
    )
    SELECT public._appt_reminder_fanout(id, req_uid, supervisor_uid, off_id, dt, 'غداً (قبل ٢٤ ساعة)') FROM due
  LOOP END LOOP;

  FOR v IN
    WITH due AS (
      UPDATE public.appointments SET rmnd_2 = 1
      WHERE sts = 1 AND i_force = 0
        AND dt > NOW() AND dt <= NOW() + INTERVAL '2 hours' AND rmnd_2 = 0
      RETURNING id, req_uid, supervisor_uid, off_id, dt
    )
    SELECT public._appt_reminder_fanout(id, req_uid, supervisor_uid, off_id, dt, 'بعد ساعتين') FROM due
  LOOP END LOOP;

  FOR v IN
    WITH due AS (
      UPDATE public.appointments SET rmnd_qtr = 1
      WHERE sts = 1 AND i_force = 0
        AND dt > NOW() AND dt <= NOW() + INTERVAL '15 minutes' AND rmnd_qtr = 0
      RETURNING id, req_uid, supervisor_uid, off_id, dt
    )
    SELECT public._appt_reminder_fanout(id, req_uid, supervisor_uid, off_id, dt, 'بعد ربع ساعة — انطلق الآن') FROM due
  LOOP END LOOP;
END;
$$;

-- المروحة المشتركة: إشعار للطالب + إشعار للمشرف (كلٌّ بنصّه وأرقام الطرف الآخر)
CREATE OR REPLACE FUNCTION public._appt_reminder_fanout(
  p_appt_id uuid, p_req_uid uuid, p_sup_uid uuid, p_off_id uuid,
  p_dt timestamptz, p_when text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $$
DECLARE
  v_offer RECORD;
  v_req RECORD;
  v_sup RECORD;
  v_addr TEXT;
  v_time TEXT;
  v_n INT := 0;
BEGIN
  SELECT o.ttl, o.loc, o.exact_loc INTO v_offer FROM public.offers o WHERE o.id = p_off_id;
  SELECT u.nm, u.ph INTO v_req FROM public.users u WHERE u.id = p_req_uid;
  SELECT u.nm, u.ph INTO v_sup FROM public.users u WHERE u.id = p_sup_uid;

  v_addr := NULLIF(TRIM(COALESCE(v_offer.exact_loc, '')), '');
  IF v_addr IS NULL THEN
    v_addr := NULLIF(BTRIM(CONCAT_WS(' — ',
      NULLIF(TRIM(COALESCE(v_offer.loc->>'city', '')), ''),
      NULLIF(TRIM(COALESCE(v_offer.loc->>'d', '')), ''))), '');
  END IF;

  v_time := to_char(p_dt AT TIME ZONE 'Asia/Damascus', 'HH24:MI');

  IF p_req_uid IS NOT NULL THEN
    INSERT INTO public.notifications (uid, tp, ttl, bdy, act, ref_id, i_rd, ts_crt)
    VALUES (p_req_uid, 2, '⏰ تذكير بموعدك',
      'تذكير: ' || p_when || ' موعد معاينة «' || COALESCE(v_offer.ttl, '—') ||
      '» الساعة ' || v_time ||
      CASE WHEN v_addr IS NOT NULL THEN ' — الموقع: ' || v_addr ELSE '' END ||
      CASE WHEN v_sup.nm IS NOT NULL
           THEN ' — المشرف: ' || v_sup.nm || ' ' || COALESCE(v_sup.ph, '')
           ELSE '' END || '.',
      'appointment', p_appt_id::TEXT, 0, NOW());
    v_n := v_n + 1;
  END IF;

  IF p_sup_uid IS NOT NULL THEN
    INSERT INTO public.notifications (uid, tp, ttl, bdy, act, ref_id, i_rd, ts_crt)
    VALUES (p_sup_uid, 2, '⏰ تذكير بمهمة معاينة',
      'تذكير: ' || p_when || ' معاينة «' || COALESCE(v_offer.ttl, '—') ||
      '» الساعة ' || v_time ||
      CASE WHEN v_addr IS NOT NULL THEN ' — الموقع: ' || v_addr ELSE '' END ||
      ' — الطالب: ' || COALESCE(v_req.nm, '—') || ' ' || COALESCE(v_req.ph, '') || '.',
      'appointment', p_appt_id::TEXT, 0, NOW());
    v_n := v_n + 1;
  END IF;

  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.send_appointment_reminders() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.send_appointment_reminders() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.send_appointment_reminders() TO service_role;
REVOKE ALL ON FUNCTION public._appt_reminder_fanout(uuid, uuid, uuid, uuid, timestamptz, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._appt_reminder_fanout(uuid, uuid, uuid, uuid, timestamptz, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._appt_reminder_fanout(uuid, uuid, uuid, uuid, timestamptz, text) TO service_role;

-- رفع دقة الكرون من «بداية كل ساعة» إلى «كل 15 دقيقة» (لدقة عتبة الربع ساعة)
DO $$
BEGIN
  PERFORM cron.unschedule(jobid) FROM cron.job
  WHERE jobname IN ('hourly-appointment-reminders', 'appointment-reminders-15min');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'appointment-reminders-15min',
  '*/15 * * * *',
  $$ SELECT public.send_appointment_reminders(); $$
);

-- ══ تحققات مدمجة (نتائج متوقعة بعد اللصق) ══
-- ① ثلاثة تريغرات بحرف O:
SELECT tgname, tgrelid::regclass AS tbl, tgenabled FROM pg_trigger
WHERE tgname IN ('trg_appt_accept_enrich', 'trg_appt_notify_supervisor')
ORDER BY tgname;
-- ② أربع دوال محصّنة (prosecdef=t ومعها search_path مثبت):
SELECT p.proname, p.prosecdef,
  EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) c WHERE c LIKE 'search_path=%') AS pinned
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('trg_appt_accept_enrich', 'trg_appt_notify_supervisor',
                    'send_appointment_reminders', '_appt_reminder_fanout')
ORDER BY p.proname;
-- ③ الجدولة الجديدة 15 دقيقة (والساعية القديمة غائبة):
SELECT jobname, schedule, active FROM cron.job WHERE jobname LIKE '%reminder%';
-- ④ فحص وظيفي يدوي بعد اللصق (لا يكتب شيئاً — المواعيد الافتراضية بعيدة):
--   SELECT public.send_appointment_reminders();
