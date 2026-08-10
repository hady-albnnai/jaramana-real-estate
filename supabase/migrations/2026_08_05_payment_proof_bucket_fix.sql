-- ============================================================================
-- 🔧 إصلاح تحميل إيصال الدفع - إنشاء bucket وإضافة policies (Bug #22)
-- ============================================================================
--
-- المشكلة: عند محاولة عرض إيصال الدفع، يفشل التحميل
-- السبب: bucket payment_proofs قد لا يكون موجوداً أو ليس لديه policies صحيحة
--
-- الحل: إنشاء bucket إذا لم يكن موجوداً + إضافة storage policies
-- ============================================================================

-- إنشاء bucket payment_proofs إذا لم يكن موجوداً
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'payment_proofs',
  'payment_proofs',
  false,  -- bucket خاص (ليس عام)
  10485760,  -- 10 MB limit
  ARRAY['image/jpeg', 'image/png', 'image/jpg', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

-- حذف policies القديمة (إذا موجودة)
DROP POLICY IF EXISTS "Users can upload their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Users can view their own payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Admins can view all payment proofs" ON storage.objects;
DROP POLICY IF EXISTS "Service role can manage payment proofs" ON storage.objects;

-- ✅ Policy 1: المستخدمون يمكنهم رفع إثباتات الدفع الخاصة بهم
CREATE POLICY "Users can upload their own payment proofs"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment_proofs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ✅ Policy 2: المستخدمون يمكنهم عرض إثباتات الدفع الخاصة بهم فقط
CREATE POLICY "Users can view their own payment proofs"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment_proofs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- ✅ Policy 3: الموظفون (role >= 2) يمكنهم عرض جميع إثباتات الدفع
CREATE POLICY "Admins can view all payment proofs"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment_proofs'
  AND EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
    AND role >= 2
    AND i_del = 0
  )
);

-- ✅ Policy 4: Service role يمكنه إدارة جميع إثباتات الدفع
CREATE POLICY "Service role can manage payment proofs"
ON storage.objects FOR ALL
TO service_role
USING (bucket_id = 'payment_proofs')
WITH CHECK (bucket_id = 'payment_proofs');

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① Bucket موجود → المتوقع: 1
SELECT COUNT(*) AS bucket_exists
FROM storage.buckets
WHERE id = 'payment_proofs';

-- ② Policies موجودة → المتوقع: 4
SELECT COUNT(*) AS policies_count
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND policyname LIKE '%payment proofs%';
