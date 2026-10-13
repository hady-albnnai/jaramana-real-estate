-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: نظام التوثيق الرسمي للمستخدمين (vrf)
-- التاريخ: 2026-06-06
-- المرجع: docs/LOGIC_SPEC.md §2.1 (التوثيق الرسمي)
-- الهدف: إضافة عمود vrf لتتبع حالة التوثيق الرسمي بعد مراجعة الإدارة.
--   0 = غير موثق (الافتراضي)
--   1 = قيد المراجعة (المستخدم رفع وثائقه وينتظر الإدارة)
--   2 = موثق رسمياً (راجعت الإدارة الوثائق ووافقت)
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) إضافة العمود (idempotent — آمن للتشغيل أكثر من مرة)
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS vrf SMALLINT NOT NULL DEFAULT 0;

-- 2) قيد التحقق من القيم المسموحة
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_vrf_check'
  ) THEN
    ALTER TABLE users
      ADD CONSTRAINT users_vrf_check CHECK (vrf IN (0, 1, 2));
  END IF;
END $$;

-- 3) فهرس لتسريع استعلامات الإدارة (طلبات التوثيق قيد المراجعة)
CREATE INDEX IF NOT EXISTS idx_users_vrf_pending
  ON users (vrf)
  WHERE vrf = 1;

-- 4) قاعدة المنطق: الوسيط (brk=1) يجب أن يكون موثقاً ليُعتبر فعّالاً.
--    (لا نفرض هذا كـ CONSTRAINT لأنه قد يكون قيد المراجعة، بل نتركه للمنطق التطبيقي.)

-- 5) تعليق توضيحي على العمود
COMMENT ON COLUMN users.vrf IS
  'حالة التوثيق الرسمي: 0=غير موثق، 1=قيد المراجعة، 2=موثق بعد مراجعة الإدارة. مرجع: docs/LOGIC_SPEC.md §2.1';
