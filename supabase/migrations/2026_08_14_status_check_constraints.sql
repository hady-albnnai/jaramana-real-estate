-- ============================================================================
-- PERF-003 / SEC-007 — قيود CHECK مفقودة على أعمدة الحالة
-- ============================================================================
-- الوضع: كل جداول الحالة تحمل قيد CHECK يحرس مجال القيم، **عدا** عمودين:
--   • legal_consultations.status  (المجال 0..5 حسب LOGIC_SPEC)
--   • expediting_tasks.status     (المجال 0..3)
--
-- لماذا يهم؟ القيد هو **آخر خط دفاع** حين تخطئ الدالة. وهذا ليس افتراضياً:
-- BUG-027 و BUG-028 كانا بالضبط قيمة خارج المجال (tp=20 و tp=10)، وقيد
-- notifications_tp_check هو الذي كشفهما — لولاه لكانت الإشعارات تُكتب بنوع
-- لا تعرضه أي شاشة، والعطل يبقى صامتاً لشهور.
-- هذان العمودان بلا هذا الحارس: أي خطأ برمجي يكتب status=99 يمرّ بصمت،
-- والاستشارة/المهمة تختفي من كل الشاشات (لأنها تصفّي بقيم محددة).
--
-- ملاحظة: القيم الحالية كلها ضمن المجال (تحقُّق حي: 0,1,3 للتعقيب) فلا خطر
-- من إضافة القيد الآن.
-- ============================================================================

ALTER TABLE public.legal_consultations
  DROP CONSTRAINT IF EXISTS legal_consultations_status_check;
ALTER TABLE public.legal_consultations
  ADD CONSTRAINT legal_consultations_status_check
  CHECK (status >= 0 AND status <= 5);
COMMENT ON CONSTRAINT legal_consultations_status_check ON public.legal_consultations IS
  '0 بانتظار المحامي · 1 مؤكدة · 2 مكتملة · 3 ملغاة · 4 مرفوضة نهائياً · 5 بانتظار استكمال بيانات';

ALTER TABLE public.expediting_tasks
  DROP CONSTRAINT IF EXISTS expediting_tasks_status_check;
ALTER TABLE public.expediting_tasks
  ADD CONSTRAINT expediting_tasks_status_check
  CHECK (status >= 0 AND status <= 3);
COMMENT ON CONSTRAINT expediting_tasks_status_check ON public.expediting_tasks IS
  '0 بانتظار · 1 قيد الاستخراج · 2 بانتظار المراجعة · 3 معتمدة';
