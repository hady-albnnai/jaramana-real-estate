-- ============================================================================
-- 📸 تذكير موعد التصوير قبل ساعة — للطرفين (طالب التصوير + المصوّر)
-- التاريخ: 2026-07-28 · بطلب المالك بعد جولة اختبار مسار التصوير
--
-- الخلفية: مهام التصوير بجدول `photography_tasks` منفصل عن `appointments`،
-- فدالة `send_appointment_reminders()` لا تراها إطلاقاً ⇒ صفر تذكير.
--
-- ما تفعله هذه اللصقة:
--   ① عمود `rmnd_1h` (علم dedup — مرة واحدة بالعمر لكل مهمة)
--   ② دالة `send_photography_reminders()` — تُذكّر الطرفين قبل ساعة (نافذة 0..60د)
--      مع الموعد بتوقيت دمشق + الموقع + اسم وهاتف الطرف الآخر + بوش خارجي
--   ③ إضافتها لكرون `*/15` القائم (يُعاد جدولته ليشغّل الدالتين معاً)
--   ④ رباعي التحصين كاملاً (§7 من DEVELOPMENT_GUIDELINES)
--
-- idempotent بالكامل: IF NOT EXISTS / CREATE OR REPLACE / dedup بالعلم.
-- ============================================================================

-- ① ─────────────────────────────────────────── علم التذكير (dedup)
ALTER TABLE public.photography_tasks
  ADD COLUMN IF NOT EXISTS rmnd_1h INTEGER NOT NULL DEFAULT 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'photography_tasks_rmnd_1h_check'
  ) THEN
    ALTER TABLE public.photography_tasks
      ADD CONSTRAINT photography_tasks_rmnd_1h_check CHECK (rmnd_1h IN (0, 1));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_photo_tasks_reminder
  ON public.photography_tasks (ts_scheduled)
  WHERE rmnd_1h = 0 AND sts IN (0, 1);

-- ② ─────────────────────────────────────────── دالة التذكير
CREATE OR REPLACE FUNCTION public.send_photography_reminders()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_task     RECORD;
  v_req      RECORD;
  v_photog   RECORD;
  v_when     TEXT;
  v_loc      TEXT;
  v_count    INTEGER := 0;
BEGIN
  -- المهام المجدولة خلال الساعة القادمة، النشطة فقط (بانتظار/قيد التنفيذ)،
  -- التي لم يُرسل لها تذكير بعد. النافذة 0..60 دقيقة تناسب كرون كل 15 دقيقة.
  FOR v_task IN
    SELECT t.id, t.ttl, t.notes, t.ts_scheduled, t.requested_by, t.photographer_id
    FROM public.photography_tasks t
    WHERE t.rmnd_1h = 0
      AND t.sts IN (0, 1)
      AND t.ts_scheduled IS NOT NULL
      AND t.ts_scheduled > NOW()
      AND t.ts_scheduled <= NOW() + INTERVAL '1 hour'
    FOR UPDATE SKIP LOCKED
  LOOP
    -- الموعد بتوقيت دمشق (السيرفر UTC — العرض دائماً محلي)
    v_when := to_char(v_task.ts_scheduled AT TIME ZONE 'Asia/Damascus',
                      'YYYY/MM/DD') || ' الساعة ' ||
              to_char(v_task.ts_scheduled AT TIME ZONE 'Asia/Damascus', 'HH24:MI');

    -- الموقع مخزّن داخل notes بصيغة «… | الموقع: X | …»
    v_loc := NULLIF(TRIM(SPLIT_PART(SPLIT_PART(COALESCE(v_task.notes, ''), 'الموقع:', 2), '|', 1)), '');

    SELECT u.nm, u.ph INTO v_req
      FROM public.users u WHERE u.id = v_task.requested_by;
    SELECT u.nm, u.ph INTO v_photog
      FROM public.users u WHERE u.id = v_task.photographer_id;

    -- ← تذكير صاحب الطلب (باسم ورقم المصوّر)
    IF v_task.requested_by IS NOT NULL THEN
      INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
      VALUES (
        v_task.requested_by, 1,
        '⏰ تذكير: موعد التصوير بعد ساعة',
        'موعد تصوير «' || COALESCE(v_task.ttl, '') || '» بعد ساعة — ' || v_when ||
        COALESCE(E'\n📍 ' || v_loc, '') ||
        E'\n👤 المصوّر: ' || COALESCE(v_photog.nm, '—') ||
        COALESCE(' — ' || v_photog.ph, '') ||
        E'\nيرجى التواجد بالموقع قبل الموعد بعشر دقائق.',
        v_task.id::TEXT, 'photography_reminder_1h', 0, 0, NOW()
      );
      PERFORM public.send_push_notification(
        v_task.requested_by,
        '⏰ موعد التصوير بعد ساعة',
        v_when || COALESCE(' — ' || v_loc, ''),
        jsonb_build_object('act', 'photography_reminder_1h', 'ref_id', v_task.id::TEXT)
      );
      v_count := v_count + 1;
    END IF;

    -- ← تذكير المصوّر (باسم ورقم وموقع طالب التصوير)
    IF v_task.photographer_id IS NOT NULL THEN
      INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
      VALUES (
        v_task.photographer_id, 2,
        '⏰ تذكير: مهمة تصوير بعد ساعة',
        'مهمة «' || COALESCE(v_task.ttl, '') || '» بعد ساعة — ' || v_when ||
        COALESCE(E'\n📍 ' || v_loc, '') ||
        E'\n📞 طالب التصوير: ' || COALESCE(v_req.nm, '—') ||
        COALESCE(' — ' || v_req.ph, ''),
        v_task.id::TEXT, 'photography_reminder_1h', 0, 0, NOW()
      );
      PERFORM public.send_push_notification(
        v_task.photographer_id,
        '⏰ مهمة تصوير بعد ساعة',
        v_when || COALESCE(' — ' || v_loc, ''),
        jsonb_build_object('act', 'photography_reminder_1h', 'ref_id', v_task.id::TEXT)
      );
      v_count := v_count + 1;
    END IF;

    -- ختم العلم فوراً (dedup: مرة واحدة بالعمر)
    UPDATE public.photography_tasks SET rmnd_1h = 1 WHERE id = v_task.id;
  END LOOP;

  RETURN v_count;
END;
$function$;

-- ③ ─────────────────────────────────────────── رباعي التحصين
REVOKE ALL     ON FUNCTION public.send_photography_reminders()  FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.send_photography_reminders()  FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.send_photography_reminders()  TO service_role;

-- ④ ─────────────────────────────────────────── الجدولة (تُضاف للكرون القائم)
-- الكرون القائم `appointment-reminders-15min` يشغّل دالة المواعيد فقط؛
-- نعيد جدولته ليشغّل الدالتين معاً بنفس النبضة (بلا كرون إضافي).
SELECT cron.schedule(
  'appointment-reminders-15min',
  '*/15 * * * *',
  $cron$ SELECT public.send_appointment_reminders(); SELECT public.send_photography_reminders(); $cron$
);

-- ============================================================================
-- ✅ تحققات ما بعد اللصق (المتوقع مكتوب بجانب كل استعلام)
-- ============================================================================

-- ① العمود والقيد موجودان  → المتوقع: صف واحد (rmnd_1h | integer | 0)
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'photography_tasks'
  AND column_name = 'rmnd_1h';

-- ② الدالة محصّنة  → المتوقع: secdef=true · cfg يحوي search_path · anon/auth=false · service=true
SELECT p.proname,
       p.prosecdef AS secdef,
       array_to_string(p.proconfig, ',') AS cfg,
       has_function_privilege('anon',          p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role',  p.oid, 'EXECUTE') AS svc_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'send_photography_reminders';

-- ③ الكرون يشغّل الدالتين  → المتوقع: صف واحد، command يحوي send_photography_reminders
SELECT jobname, schedule, active, command
FROM cron.job WHERE jobname = 'appointment-reminders-15min';

-- ④ تشغيل يدوي آمن  → المتوقع: 0 (لا مهام خلال الساعة القادمة الآن) — لا يكتب شيئاً
SELECT public.send_photography_reminders() AS reminders_sent;
