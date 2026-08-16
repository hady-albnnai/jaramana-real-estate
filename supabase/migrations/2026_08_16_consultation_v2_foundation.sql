-- =============================================================================
-- 2026-08-16 — Consultation Flow V2: additive foundation (لا تعطيل للمسار القديم)
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA extensions;

-- نوع الموعد وربطه القانوني. كل البيانات القديمة مواعيد عروض.
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'offer',
  ADD COLUMN IF NOT EXISTS consultation_id uuid;

DO $ddl$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='appointments_kind_check') THEN
    ALTER TABLE public.appointments ADD CONSTRAINT appointments_kind_check
      CHECK (kind IN ('offer','legal'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='appointments_consultation_id_fkey') THEN
    ALTER TABLE public.appointments ADD CONSTRAINT appointments_consultation_id_fkey
      FOREIGN KEY (consultation_id) REFERENCES public.legal_consultations(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='legal_consultations_appointment_id_fkey') THEN
    ALTER TABLE public.legal_consultations ADD CONSTRAINT legal_consultations_appointment_id_fkey
      FOREIGN KEY (appointment_id) REFERENCES public.appointments(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='consultation_credits_user_uid_fkey') THEN
    ALTER TABLE public.consultation_credits ADD CONSTRAINT consultation_credits_user_uid_fkey
      FOREIGN KEY (user_uid) REFERENCES public.users(id) ON DELETE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='consultation_credits_consultation_id_fkey') THEN
    ALTER TABLE public.consultation_credits ADD CONSTRAINT consultation_credits_consultation_id_fkey
      FOREIGN KEY (consultation_id) REFERENCES public.legal_consultations(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='consultation_credits_source_consultation_id_fkey') THEN
    ALTER TABLE public.consultation_credits ADD CONSTRAINT consultation_credits_source_consultation_id_fkey
      FOREIGN KEY (source_consultation_id) REFERENCES public.legal_consultations(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='consultation_credits_granted_by_fkey') THEN
    ALTER TABLE public.consultation_credits ADD CONSTRAINT consultation_credits_granted_by_fkey
      FOREIGN KEY (granted_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END;
$ddl$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_appointments_legal_consultation
  ON public.appointments(consultation_id) WHERE consultation_id IS NOT NULL;

-- مسودة الخدمة قبل الدفع: لا تضيع عند إغلاق التطبيق.
CREATE TABLE IF NOT EXISTS public.consultation_intents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  flow text NOT NULL CHECK (flow IN ('phone_new','onsite_new','phone_renew','onsite_convert')),
  parent_consultation_id uuid REFERENCES public.legal_consultations(id) ON DELETE CASCADE,
  subject text NOT NULL DEFAULT '',
  attachments text[] NOT NULL DEFAULT '{}',
  service_type integer NOT NULL CHECK (service_type IN (0,1)),
  lawyer_uid uuid REFERENCES public.users(id) ON DELETE SET NULL,
  reservation_id uuid,
  quoted_amount numeric NOT NULL CHECK (quoted_amount >= 0),
  base_discount numeric NOT NULL DEFAULT 0 CHECK (base_discount >= 0),
  price_snapshot jsonb NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'draft' CHECK (status IN (
    'draft','payment_pending','payment_needs_slot','paid','materialized','expired','cancelled','failed'
  )),
  idempotency_key uuid NOT NULL,
  expires_at timestamptz,
  materialized_consultation_id uuid REFERENCES public.legal_consultations(id) ON DELETE SET NULL,
  failure_code text,
  ts_crt timestamptz NOT NULL DEFAULT now(),
  ts_upd timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_uid,idempotency_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_consultation_intent_open_flow
  ON public.consultation_intents(user_uid,flow,COALESCE(parent_consultation_id,'00000000-0000-0000-0000-000000000000'::uuid))
  WHERE status IN ('draft','payment_pending','payment_needs_slot','paid');

-- حجز موحد يمنع تداخل hold مع موعد مؤكد داخل قاعدة البيانات نفسها.
CREATE TABLE IF NOT EXISTS public.lawyer_time_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lawyer_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  user_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  consultation_intent_id uuid NOT NULL REFERENCES public.consultation_intents(id) ON DELETE CASCADE,
  slot_start timestamptz NOT NULL,
  slot_end timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'held' CHECK (status IN ('held','confirmed','released','expired','cancelled')),
  hold_expires_at timestamptz NOT NULL,
  appointment_id uuid REFERENCES public.appointments(id) ON DELETE SET NULL,
  idempotency_key uuid NOT NULL,
  ts_crt timestamptz NOT NULL DEFAULT now(),
  ts_upd timestamptz NOT NULL DEFAULT now(),
  CHECK (slot_end > slot_start),
  UNIQUE(user_uid,idempotency_key)
);

ALTER TABLE public.consultation_intents
  DROP CONSTRAINT IF EXISTS consultation_intents_reservation_id_fkey;
ALTER TABLE public.consultation_intents
  ADD CONSTRAINT consultation_intents_reservation_id_fkey
  FOREIGN KEY (reservation_id) REFERENCES public.lawyer_time_reservations(id) ON DELETE SET NULL
  DEFERRABLE INITIALLY DEFERRED;

DO $exclude$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='lawyer_time_no_overlap') THEN
    ALTER TABLE public.lawyer_time_reservations ADD CONSTRAINT lawyer_time_no_overlap
      EXCLUDE USING gist (
        lawyer_uid WITH =,
        tstzrange(slot_start,slot_end,'[)') WITH &&
      ) WHERE (status IN ('held','confirmed'));
  END IF;
END;
$exclude$;

CREATE INDEX IF NOT EXISTS idx_lawyer_reservation_expiry
  ON public.lawyer_time_reservations(hold_expires_at)
  WHERE status='held';

-- كل فترة محادثة سجل مستقل.
CREATE TABLE IF NOT EXISTS public.consultation_chat_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id uuid NOT NULL REFERENCES public.legal_consultations(id) ON DELETE CASCADE,
  ordinal integer NOT NULL CHECK (ordinal > 0),
  kind text NOT NULL CHECK (kind IN ('initial','renewal','legacy_aggregate')),
  payment_id uuid REFERENCES public.payments(id) ON DELETE SET NULL,
  duration_minutes integer NOT NULL CHECK (duration_minutes > 0 AND duration_minutes <= 240),
  free_extension_minutes integer NOT NULL DEFAULT 0 CHECK (free_extension_minutes IN (0,5)),
  status text NOT NULL DEFAULT 'ready' CHECK (status IN (
    'ready','join_window','active','ended','cancelled','reversed'
  )),
  lawyer_ready_at timestamptz,
  join_deadline timestamptz,
  user_joined_at timestamptz,
  starts_at timestamptz,
  ends_at timestamptz,
  start_reason text CHECK (start_reason IS NULL OR start_reason IN ('user_joined','grace_expired','legacy')),
  ready_idempotency_key uuid,
  join_idempotency_key uuid,
  ended_at timestamptz,
  ts_crt timestamptz NOT NULL DEFAULT now(),
  ts_upd timestamptz NOT NULL DEFAULT now(),
  UNIQUE(consultation_id,ordinal)
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_session_payment
  ON public.consultation_chat_sessions(payment_id) WHERE payment_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_session_live
  ON public.consultation_chat_sessions(consultation_id)
  WHERE status IN ('join_window','active');
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_session_ready
  ON public.consultation_chat_sessions(consultation_id)
  WHERE status='ready';

-- انتظار موعد المحامي نفسه.
CREATE TABLE IF NOT EXISTS public.consultation_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  lawyer_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  parent_consultation_id uuid NOT NULL REFERENCES public.legal_consultations(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','notified','consumed','cancelled')),
  notified_at timestamptz,
  ts_crt timestamptz NOT NULL DEFAULT now(),
  ts_upd timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_consultation_waitlist_active
  ON public.consultation_waitlist(user_uid,lawyer_uid,parent_consultation_id)
  WHERE status='active';

-- Outbox يجعل الإشعار الخارجي قابلاً لإعادة المحاولة دون تكرار الحدث.
CREATE TABLE IF NOT EXISTS public.consultation_event_outbox (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_key text NOT NULL UNIQUE,
  event_type text NOT NULL,
  recipient_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reference_id uuid,
  payload jsonb NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','processing','sent','failed','cancelled')),
  attempts integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  last_error text,
  sent_at timestamptz,
  ts_crt timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_consultation_outbox_pending
  ON public.consultation_event_outbox(next_attempt_at)
  WHERE status IN ('pending','failed');

ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS consultation_intent_id uuid;
DO $payment_fk$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='payments_consultation_intent_id_fkey') THEN
    ALTER TABLE public.payments ADD CONSTRAINT payments_consultation_intent_id_fkey
      FOREIGN KEY (consultation_intent_id) REFERENCES public.consultation_intents(id) ON DELETE SET NULL;
  END IF;
END;
$payment_fk$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_payment_consultation_intent
  ON public.payments(consultation_intent_id) WHERE consultation_intent_id IS NOT NULL;

-- الجداول الجديدة لا تُقرأ أو تُكتب مباشرة من العميل.
ALTER TABLE public.consultation_intents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.lawyer_time_reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultation_chat_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultation_waitlist ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.consultation_event_outbox ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.consultation_intents FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.lawyer_time_reservations FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.consultation_chat_sessions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.consultation_waitlist FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.consultation_event_outbox FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.consultation_intents TO service_role;
GRANT ALL ON TABLE public.lawyer_time_reservations TO service_role;
GRANT ALL ON TABLE public.consultation_chat_sessions TO service_role;
GRANT ALL ON TABLE public.consultation_waitlist TO service_role;
GRANT ALL ON TABLE public.consultation_event_outbox TO service_role;

-- ملفات الاستشارة: Edge/service_role فقط، وحدود فعلية للباكيت.
DROP POLICY IF EXISTS consultation_files_insert ON storage.objects;
DROP POLICY IF EXISTS consultation_files_select ON storage.objects;
UPDATE storage.buckets
SET file_size_limit = 8388608,
    allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','audio/mp4']::text[]
WHERE id='consultation_files';

-- تحقق بنيوي داخل نفس المعاملة.
DO $verify$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='kind') THEN
    RAISE EXCEPTION 'APPOINTMENT_KIND_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='lawyer_time_no_overlap') THEN
    RAISE EXCEPTION 'RESERVATION_EXCLUSION_MISSING';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname='public' AND indexname='uq_chat_session_live') THEN
    RAISE EXCEPTION 'CHAT_SESSION_LIVE_GUARD_MISSING';
  END IF;
END;
$verify$;
