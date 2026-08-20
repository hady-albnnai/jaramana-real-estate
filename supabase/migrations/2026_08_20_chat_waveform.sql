-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — م14 المرحلة ج: موجة صوتية بصرية لرسائل المحادثة
--
-- عمود waveform jsonb على consultation_chats: مصفوفة سعات 0..1
-- (حتى 120 عينة) تُلتقط أثناء التسجيل وترسم كأعمدة بصرية في فقاعة
-- الرسالة الصوتية مع تظليل موضع التشغيل وإمكانية السحب للتقديم.
-- الرسائل القديمة بلا موجة تبقى waveform=NULL وتُعرض بالأيقونة المعتادة.
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.consultation_chats
  ADD COLUMN IF NOT EXISTS waveform jsonb;

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج: waveform_column_patched = true
-- ──────────────────────────────────────────────────────────────────────
SELECT EXISTS (
  SELECT 1 FROM information_schema.columns
  WHERE table_schema='public' AND table_name='consultation_chats'
    AND column_name='waveform'
) AS waveform_column_patched;
