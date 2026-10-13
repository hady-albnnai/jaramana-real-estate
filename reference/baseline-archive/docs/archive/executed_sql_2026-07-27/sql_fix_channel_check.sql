-- ═══════════════════════════════════════════════════
-- إصلاح payments_channel_check — إضافة syriatel_cash
-- بَغ انكشف بالاختبار الشامل 2026-07-27
-- شغّل الملف كاملاً — آمن وقابل للتكرار
-- ═══════════════════════════════════════════════════

-- فحص (اختياري): القيم المستخدمة فعلاً بالدفعات
SELECT DISTINCT channel FROM public.payments;

-- الإصلاح: استبدال القيد بالنسخة الشاملة
ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_channel_check;
ALTER TABLE public.payments ADD CONSTRAINT payments_channel_check
  CHECK (channel IS NULL OR channel IN ('bank','haram','sham_cash','syriatel_cash','balance'));

-- تحقق: لازم يظهر التعريف الجديد وفيها syriatel_cash
SELECT conname, pg_get_constraintdef(oid) AS def
FROM pg_constraint
WHERE conname = 'payments_channel_check';
