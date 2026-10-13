-- ============================================
-- Migration #8 — 2026-06-06
-- payments.channel + Storage buckets (config_assets, payment_proofs)
-- ============================================
-- التغييرات:
--   1. إضافة عمود `channel TEXT` لجدول payments
--      (يخزّن: 'haram' | 'sham_cash' | 'balance' | 'bank')
--      ✅ نُبقي `mtd INT` للتوافق الخلفي (يمكن حذفه لاحقاً)
--   2. CHECK constraint اختياري على القيم المسموحة
--   3. Index على channel للفلترة السريعة في admin
--   4. إنشاء bucket `config_assets` (عام للقراءة) — لصورة QR شام كاش وأصول الإعدادات
--   5. إنشاء bucket `payment_proofs` (خاص) — لإيصالات المستخدمين
--   6. RLS لـ payment_proofs:
--      - INSERT: المستخدم المسجّل (auth.uid() = owner)
--      - SELECT: صاحب الإيصال + admin/owner
--      - DELETE: admin/owner فقط
-- ============================================

-- 1️⃣ عمود channel
ALTER TABLE payments ADD COLUMN IF NOT EXISTS channel TEXT;

-- 2️⃣ CHECK constraint (كامل مجموعة القنوات — محدّث 2026-07-27: إضافة syriatel_cash)
ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_channel_check;
ALTER TABLE payments
  ADD CONSTRAINT payments_channel_check
  CHECK (channel IS NULL OR channel IN ('haram', 'sham_cash', 'balance', 'bank', 'syriatel_cash'));

-- 3️⃣ Index على channel
CREATE INDEX IF NOT EXISTS idx_payments_channel ON payments(channel) WHERE channel IS NOT NULL;

-- 4️⃣ Backfill من mtd القديم (اختياري — للسجلات القديمة)
-- mtd: 1=haram, 2=sham_cash, 3=balance, 4=bank (افتراضي قديم — قد يختلف)
UPDATE payments
SET channel = CASE mtd
  WHEN 1 THEN 'haram'
  WHEN 2 THEN 'sham_cash'
  WHEN 3 THEN 'balance'
  WHEN 4 THEN 'bank'
  ELSE NULL
END
WHERE channel IS NULL AND mtd IS NOT NULL;

-- ============================================
-- 5️⃣ Storage Buckets
-- ============================================

-- bucket config_assets (عام للقراءة)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'config_assets',
  'config_assets',
  true,
  5242880,  -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 5242880,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']::text[];

-- bucket payment_proofs (خاص)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'payment_proofs',
  'payment_proofs',
  false,
  10485760,  -- 10MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']::text[];

-- ============================================
-- 6️⃣ RLS policies — Storage objects
-- ============================================

-- ---------- config_assets ----------
-- قراءة عامة (bucket عام أصلاً، لكن نضيف policy للوضوح)
DROP POLICY IF EXISTS "config_assets_public_read" ON storage.objects;
CREATE POLICY "config_assets_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'config_assets');

-- رفع/حذف: admin أو owner فقط (rl = 4 أو 5 في users)
DROP POLICY IF EXISTS "config_assets_admin_write" ON storage.objects;
CREATE POLICY "config_assets_admin_write"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'config_assets'
    AND EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND rl IN (4, 5)
    )
  );

DROP POLICY IF EXISTS "config_assets_admin_update" ON storage.objects;
CREATE POLICY "config_assets_admin_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'config_assets'
    AND EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND rl IN (4, 5)
    )
  );

DROP POLICY IF EXISTS "config_assets_admin_delete" ON storage.objects;
CREATE POLICY "config_assets_admin_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'config_assets'
    AND EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND rl IN (4, 5)
    )
  );

-- ---------- payment_proofs ----------
-- رفع: أي مستخدم مسجّل (يرفع لمجلده باسمه = uid)
-- المسار المتفق عليه: payment_proofs/{uid}/{timestamp}_{filename}
DROP POLICY IF EXISTS "payment_proofs_user_insert" ON storage.objects;
CREATE POLICY "payment_proofs_user_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'payment_proofs'
    AND auth.uid() IS NOT NULL
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- قراءة: صاحب الإيصال + admin/owner
DROP POLICY IF EXISTS "payment_proofs_select" ON storage.objects;
CREATE POLICY "payment_proofs_select"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'payment_proofs'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR EXISTS (
        SELECT 1 FROM users WHERE id = auth.uid() AND rl IN (4, 5)
      )
    )
  );

-- حذف: admin/owner فقط (المستخدم لا يحذف بعد الرفع — للمراجعة)
DROP POLICY IF EXISTS "payment_proofs_admin_delete" ON storage.objects;
CREATE POLICY "payment_proofs_admin_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'payment_proofs'
    AND EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND rl IN (4, 5)
    )
  );

-- ============================================
-- ✅ Migration #8 جاهز
-- ============================================
DO $$
BEGIN
  RAISE NOTICE '✅ Migration #8 applied:';
  RAISE NOTICE '   - payments.channel column added';
  RAISE NOTICE '   - Bucket config_assets (public)';
  RAISE NOTICE '   - Bucket payment_proofs (private + RLS)';
END $$;
