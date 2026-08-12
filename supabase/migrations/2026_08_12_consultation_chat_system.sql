-- ═══════════════════════════════════════════════════════════════
-- نظام المحادثة للاستشارات القانونية
-- التاريخ: 2026-08-12
-- ═══════════════════════════════════════════════════════════════

-- ── 1. إضافة أعمدة جديدة لجدول legal_consultations ──────────
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS attachments TEXT[] DEFAULT '{}';
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS lawyer_alias TEXT DEFAULT '';
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS chat_started_at TIMESTAMPTZ;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS chat_duration_minutes INT DEFAULT 15;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS extended BOOLEAN DEFAULT FALSE;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS extended_by TEXT;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS reactivate_count INT DEFAULT 0;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS last_reactivate_at TIMESTAMPTZ;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS rating INT;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS rating_comment TEXT;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS converted_to_onsite BOOLEAN DEFAULT FALSE;
ALTER TABLE legal_consultations ADD COLUMN IF NOT EXISTS onsite_discount NUMERIC DEFAULT 0;

-- ── 2. إنشاء جدول consultation_chats ────────────────────────
CREATE TABLE IF NOT EXISTS consultation_chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  consultation_id UUID NOT NULL REFERENCES legal_consultations(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id),
  message_type TEXT NOT NULL CHECK (message_type IN ('text', 'voice', 'image', 'system')),
  content TEXT NOT NULL DEFAULT '',
  file_url TEXT,
  file_name TEXT,
  duration_seconds INT,
  is_read BOOLEAN DEFAULT FALSE,
  i_del INT DEFAULT 0,
  ts_crt TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_cchat_consultation ON consultation_chats(consultation_id, ts_crt ASC);
CREATE INDEX IF NOT EXISTS idx_cchat_sender ON consultation_chats(sender_id);
CREATE INDEX IF NOT EXISTS idx_cchat_unread ON consultation_chats(consultation_id, is_read) WHERE is_read = false;

-- ── 3. RLS ──────────────────────────────────────────────────
ALTER TABLE consultation_chats ENABLE ROW LEVEL SECURITY;

-- لا صلاحيات مباشرة — كل العمليات عبر Edge Function (service_role)
REVOKE ALL ON consultation_chats FROM anon, authenticated;
GRANT SELECT, INSERT ON consultation_chats TO service_role;

-- ── 4. Storage Bucket للملفات ───────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('consultation_files', 'consultation_files', false)
ON CONFLICT (id) DO NOTHING;

-- ── 5. دالة مساعدة: التحقق من انتهاء المحادثة ──────────────
CREATE OR REPLACE FUNCTION public.is_chat_expired(p_consultation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_started TIMESTAMPTZ;
  v_duration INT;
BEGIN
  SELECT chat_started_at, chat_duration_minutes
  INTO v_started, v_duration
  FROM legal_consultations
  WHERE id = p_consultation_id AND i_del = 0;

  IF v_started IS NULL THEN RETURN TRUE; END IF;
  RETURN NOW() > (v_started + (v_duration || ' minutes')::INTERVAL);
END;
$$;

REVOKE ALL ON FUNCTION public.is_chat_expired(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_chat_expired(UUID) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.is_chat_expired(UUID) TO service_role;

-- ── 6. تحديث الأسعار: حذف service_type=2 (باقة التوثيق) ────
-- نترك الأعمدة كما هي — التعديل يكون في الكود فقط
-- service_type: 0=هاتفية (500 ل.س), 1=حضورية (2000 ل.س)
