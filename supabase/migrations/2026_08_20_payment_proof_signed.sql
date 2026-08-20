-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — دَين 1: إقفال فتحة إغراق رفع إثباتات الدفع
--
-- الخلفية: كان الرفع يتم مباشرةً من العميل عبر سياسة INSERT على
-- storage.objects تسمح لأي مستخدم مسجّل بالرفع لمجلده — بلا حصة
-- يومية (فتحة إغراق بالعدد)، ولمستخدمي الجلسة المخصّصة (بلا JWT)
-- قد يفشل الرفع أصلاً لأن auth.uid() = NULL.
--
-- الإصلاح (من الريبو الجديد):
--   • أكشن user-account:sign_payment_proof_upload — المسار والنوع
--     (jpeg/png/webp) والحجم (≤5MB) والحصة اليومية (10/يوم) بقرار
--     السيرفر، ثم الرفع إلى رابط توقيع مؤقت.
--   • هذا الملف: حذف بوالصي الرفع المفتوحة نهائياً — لا يُقبل أي
--     رفع مباشر بعد الآن، والقراءة تبقى لصاحب الإثبات والموظفين
--     (عرض فقط — لا يشكّل أي فتحة كتابة).
-- حدود الباكيت (10MB + أنواع محددة) كانت موجودة أصلاً وتبقى.
-- ══════════════════════════════════════════════════════════════════

-- إزالة **كل** بوالصي الكتابة المباشرة للمستخدم (رفع/تعديل/حذف) عبر
-- كل الأجيال: 2026-06-06 و2026-06-28 و2026-08-05. القراءة تبقى لصاحب
-- الإثبات والموظفين، والكتابة صارت حصراً عبر توقيع الخادم (أو دور الخدمة).
DROP POLICY IF EXISTS "Users can upload their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "payment_proofs_user_insert" ON storage.objects;
DROP POLICY IF EXISTS "payment_proofs_insert_own" ON storage.objects;
DROP POLICY IF EXISTS "payment_proofs_update_own_or_admin" ON storage.objects;
DROP POLICY IF EXISTS "payment_proofs_delete_own_or_admin" ON storage.objects;
-- أسماء حيّة مكتشفة باللقطة (انحراف سيرفر — غير موجودة بأي ملف ريبو)
DROP POLICY IF EXISTS "payment_proofs_insert" ON storage.objects;
DROP POLICY IF EXISTS "payment_proofs_update" ON storage.objects;
DROP POLICY IF EXISTS "payment_proofs_admin_delete" ON storage.objects;

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج:
--   direct_insert_policies = 0  ⇒ الباب المفتوح مقفول (الرفع صار بالتوقيع فقط)
--   read_policies > 0           ⇒ قراءة صاحب الإثبات والإدارة باقية
-- ──────────────────────────────────────────────────────────────────────
SELECT
  (SELECT COUNT(*) FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects' AND policyname ILIKE '%proof%'
      AND cmd='INSERT') AS direct_insert_policies,
  (SELECT COALESCE(string_agg(policyname||':'||cmd, ', ' ORDER BY policyname), 'none')
    FROM pg_policies
    WHERE schemaname='storage' AND tablename='objects' AND policyname ILIKE '%proof%'
      AND cmd IN ('INSERT','UPDATE','DELETE')) AS remaining_write_policies;
