-- ══════════════════════════════════════════════════════════════════════
-- حذف كل بيانات مستخدم الاختبار (الاستشارات + الدفعات + الإشعارات + كل
-- التوابع) — للبدء من جديد في اختبار مسار الاستشارة.
-- الاستخدام: استبدل __TEST_USER_NAME__ باسم المستخدم ثم نفّذ في SQL Editor
-- أو عبر سكربت النشر (scripts/deploy_supabase.sh مع CLEANUP=true).
-- النتيجة: صف واحد بأعداد كل جدول محذوف + user_id.
-- ══════════════════════════════════════════════════════════════════════
WITH
u AS (
  SELECT id FROM public.users
  WHERE nm = '__TEST_USER_NAME__' OR nm ILIKE '%' || '__TEST_USER_NAME__' || '%'
     OR usr = '__TEST_USER_NAME__' OR usr ILIKE '%' || '__TEST_USER_NAME__' || '%'
),
cons AS (
  SELECT id FROM public.legal_consultations WHERE user_uid IN (SELECT id FROM u)
  UNION
  SELECT (meta->>'continue_chat')::uuid FROM public.payments
   WHERE uid IN (SELECT id FROM u) AND meta->>'continue_chat' IS NOT NULL
  UNION
  SELECT parent_consultation_id FROM public.consultation_intents
   WHERE user_uid IN (SELECT id FROM u) AND parent_consultation_id IS NOT NULL
),
pays AS (
  SELECT id FROM public.payments
  WHERE uid IN (SELECT id FROM u)
     OR (meta->>'continue_chat')::uuid IN (SELECT id FROM cons)
),
intents AS (
  SELECT id FROM public.consultation_intents WHERE user_uid IN (SELECT id FROM u)
),
d_chats AS (
  DELETE FROM public.consultation_chats
  WHERE consultation_id IN (SELECT id FROM cons) RETURNING 1
),
d_sess AS (
  DELETE FROM public.consultation_chat_sessions
  WHERE consultation_id IN (SELECT id FROM cons)
     OR payment_id IN (SELECT id FROM pays) RETURNING 1
),
d_out AS (
  DELETE FROM public.consultation_event_outbox
  WHERE recipient_uid IN (SELECT id FROM u)
     OR reference_id IN (SELECT id FROM cons) RETURNING 1
),
d_notif AS (
  DELETE FROM public.notifications
  WHERE uid IN (SELECT id FROM u)
     OR ref_id IN (SELECT id::text FROM cons)
     OR ref_id IN (SELECT id::text FROM pays) RETURNING 1
),
d_earn AS (
  -- 🔧 2026-08-19: أرباح المحامين ترتبط بـ payment_id/consultation_id —
  -- كانت تُحذف الدفعات قبلها فيفشل بقيود FK (lawyer_earnings_payment_id_fkey)
  DELETE FROM public.lawyer_earnings
  WHERE payment_id IN (SELECT id FROM pays)
     OR consultation_id IN (SELECT id FROM cons) RETURNING 1
),
d_pay AS (
  DELETE FROM public.payments
  WHERE uid IN (SELECT id FROM u)
     OR id IN (SELECT id FROM pays) RETURNING 1
),
d_res AS (
  DELETE FROM public.lawyer_time_reservations
  WHERE consultation_intent_id IN (SELECT id FROM intents) RETURNING 1
),
d_appt AS (
  DELETE FROM public.appointments
  WHERE consultation_id IN (SELECT id FROM cons)
     OR (req_uid IN (SELECT id FROM u) AND kind = 'legal') RETURNING 1
),
d_int AS (
  DELETE FROM public.consultation_intents
  WHERE id IN (SELECT id FROM intents) RETURNING 1
),
d_cred AS (
  DELETE FROM public.consultation_credits
  WHERE user_uid IN (SELECT id FROM u)
     OR consultation_id IN (SELECT id FROM cons) RETURNING 1
),
d_cons AS (
  DELETE FROM public.legal_consultations
  WHERE id IN (SELECT id FROM cons)
     OR user_uid IN (SELECT id FROM u) RETURNING 1
)
SELECT
  (SELECT string_agg(id::text, ',') FROM u)  AS user_id,
  (SELECT count(*) FROM d_chats)             AS chats_deleted,
  (SELECT count(*) FROM d_sess)              AS sessions_deleted,
  (SELECT count(*) FROM d_out)               AS outbox_deleted,
  (SELECT count(*) FROM d_notif)             AS notifications_deleted,
  (SELECT count(*) FROM d_earn)              AS earnings_deleted,
  (SELECT count(*) FROM d_pay)               AS payments_deleted,
  (SELECT count(*) FROM d_res)               AS reservations_deleted,
  (SELECT count(*) FROM d_appt)              AS appointments_deleted,
  (SELECT count(*) FROM d_int)               AS intents_deleted,
  (SELECT count(*) FROM d_cred)              AS credits_deleted,
  (SELECT count(*) FROM d_cons)              AS consultations_deleted;
