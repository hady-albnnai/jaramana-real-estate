-- ============================================================================
-- PERF-004 — فهارس مفقودة على أعمدة ربط كثيرة الاستعلام
-- ============================================================================
-- المسح كشف ثلاثة أعمدة ربط بلا فهرس، أهمها:
--   • appointments.supervisor_uid — تصفّي به **كل** استعلامات شاشة المنفّذ
--     الثلاث (get_my_tasks · get_postponed_tasks · get_completed_tasks) في
--     كل فتحة شاشة ⇒ مسح كامل للجدول.
--   • appointments.bkr_id — لوحة الوسيط.
--   • activity_log.uid — سجل التدقيق لكل موظف.
-- غير محسوس اليوم (عشرات الصفوف) لكنه يتدهور خطياً، والفهرس أرخص الآن
-- بكثير منه على جدول ممتلئ لاحقاً.
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_appointments_supervisor
  ON public.appointments (supervisor_uid, sts, dt);

CREATE INDEX IF NOT EXISTS idx_appointments_broker
  ON public.appointments (bkr_id, sts);

CREATE INDEX IF NOT EXISTS idx_activity_log_uid
  ON public.activity_log (uid, ts_crt DESC);
