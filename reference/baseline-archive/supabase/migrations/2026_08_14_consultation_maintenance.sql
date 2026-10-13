-- ═══════════════════════════════════════════════════════════════════
-- 2026_08_14_consultation_maintenance.sql
-- الفجوة المكتشفة بمراجعة النضج: **لا مهمة مجدولة للاستشارات إطلاقاً**
-- (cron.job فيه 8 مهام: عروض/باقات/طلبات/مواعيد — ولا شيء للاستشارات).
--
-- الأثر التراكمي (يظهر بعد أسبوع تشغيل لا في اختبار يوم):
--  ① محادثة انتهى وقتها تبقى status=1 للأبد إن لم يضغط المحامي «إتمام»
--     ⇒ تتراكم بـ«النشطة» وتضخّم active_tasks_count فيبدو المحامي مشغولاً
--     وهو ليس كذلك ⇒ **يفسد ترتيب الإسناد** (الأقل انشغالاً).
--  ② المحامي يقبل ولا يفتح المحادثة: العميل دفع وينتظر بلا سقف زمني.
--  ③ موعد حضوري مرّ ولم يُسجَّل: يبقى معلقاً بلا نتيجة.
-- ═══════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.consultations_daily_maintenance()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_closed   INT := 0;
  v_nudged   INT := 0;
  v_appts    INT := 0;
  v_synced   INT := 0;
  r          RECORD;
BEGIN
  -- ① إغلاق المحادثات المنتهية: مضى وقتها + تجاوزت 7 أيام من بدئها
  FOR r IN
    SELECT id, user_uid, lawyer_uid
      FROM legal_consultations
     WHERE status = 1
       AND i_del = 0
       AND chat_started_at IS NOT NULL
       AND NOW() > chat_started_at + INTERVAL '7 days'
  LOOP
    UPDATE legal_consultations
       SET status = 2, ts_upd = NOW()
     WHERE id = r.id;
    v_closed := v_closed + 1;

    INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
    VALUES (r.user_uid, 1, '✅ اكتملت استشارتك',
            'انتهت مدة المحادثة (7 أيام) وأُغلقت الاستشارة. يسعدنا تقييمك للخدمة.',
            r.id::text, 'legal_consultation_update', 0, 0, NOW());
  END LOOP;

  -- ② تنبيه المحامي الذي قَبِل ولم يفتح المحادثة خلال 24 ساعة
  FOR r IN
    SELECT id, lawyer_uid, user_uid
      FROM legal_consultations
     WHERE status = 1
       AND i_del = 0
       AND chat_started_at IS NULL
       AND service_type = 0                    -- الهاتفية فقط (الحضورية بموعد)
       AND lawyer_uid IS NOT NULL
       AND NOW() > ts_upd + INTERVAL '24 hours'
  LOOP
    INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
    VALUES (r.lawyer_uid, 1, '⏰ استشارة تنتظر منك',
            'قبلتَ استشارة ولم تفتح المحادثة بعد — العميل بانتظارك.',
            r.id::text, 'legal_consultation_nudge', 0, 0, NOW());
    v_nudged := v_nudged + 1;
  END LOOP;

  -- ③ المواعيد الحضورية التي مرّت بيوم ولم تُسجَّل نتيجتها ⇒ تذكير المحامي
  FOR r IN
    SELECT a.id, a.bkr_id
      FROM appointments a
     WHERE a.bkr_id IS NOT NULL
       AND a.off_id IS NULL                    -- مواعيد قانونية لا عروض
       AND a.sts = 1
       AND NOW() > a.dt + INTERVAL '1 day'
  LOOP
    INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
    VALUES (r.bkr_id, 1, '📅 موعد بانتظار التسجيل',
            'مرّ موعد جلسة ولم تسجّل نتيجتها — افتح «مواعيدي» وسجّل «تمّت الجلسة».',
            r.id::text, 'legal_appointment_nudge', 0, 0, NOW());
    v_appts := v_appts + 1;
  END LOOP;

  -- ④ إعادة حساب عدادات الانشغال لكل المحامين (المصدر الموثوق للإسناد)
  FOR r IN SELECT uid FROM lawyer_profiles LOOP
    PERFORM public.update_lawyer_active_tasks(r.uid);
    v_synced := v_synced + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true, 'closed_chats', v_closed, 'nudged_lawyers', v_nudged,
    'nudged_appointments', v_appts, 'counters_synced', v_synced, 'ran_at', NOW());
END;
$function$;

REVOKE ALL ON FUNCTION public.consultations_daily_maintenance() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.consultations_daily_maintenance() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consultations_daily_maintenance() TO service_role;

-- جدولة يومية 3:30 صباحاً (بين مهام الصيانة القائمة)
SELECT cron.unschedule('daily-consultations-maintenance')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-consultations-maintenance');

SELECT cron.schedule('daily-consultations-maintenance', '30 3 * * *',
                     'SELECT public.consultations_daily_maintenance();');
