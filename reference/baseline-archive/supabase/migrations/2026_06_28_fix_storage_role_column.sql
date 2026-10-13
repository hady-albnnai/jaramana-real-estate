-- =============================================
-- FIX: توحيد استخدام عمود `role` بدل `rl` في سياسات Storage
-- (كان فيه تضارب بين role و rl)
-- =============================================

-- 1. التأكد من وجود العمود role (الصحيح)
-- (لو العمود rl موجود و role غير موجود، نعدل السياسات)

-- 2. تحديث سياسات payment_proofs (2026_06_06_payment_channel_and_storage.sql)
-- نستبدل rl بـ role

DROP POLICY IF EXISTS "payment_proofs_select_own_or_admin" ON storage.objects;
CREATE POLICY "payment_proofs_select_own_or_admin"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'payment_proofs' AND
  (
    (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role >= 4
    )
  )
);

DROP POLICY IF EXISTS "payment_proofs_insert_own" ON storage.objects;
CREATE POLICY "payment_proofs_insert_own"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment_proofs' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "payment_proofs_update_own_or_admin" ON storage.objects;
CREATE POLICY "payment_proofs_update_own_or_admin"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'payment_proofs' AND
  (
    (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role >= 4
    )
  )
);

DROP POLICY IF EXISTS "payment_proofs_delete_own_or_admin" ON storage.objects;
CREATE POLICY "payment_proofs_delete_own_or_admin"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'payment_proofs' AND
  (
    (storage.foldername(name))[1] = auth.uid()::text
    OR EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role >= 4
    )
  )
);

-- ملاحظة: لو فيه سياسات قديمة تستخدم rl، يفضل حذفها يدوياً من Dashboard
-- هذا الملف يضمن استخدام role فقط في المستقبل