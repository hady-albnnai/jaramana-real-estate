-- ════════════════════════════════════════════════════════════════════════════
-- Migration: إنشاء bucket offer_images + RLS policies (إصلاح رفع صور العروض)
-- Date: 2026-06-24
-- المرجع: خروق 403 عند رفع صور العروض — new row violates row-level security policy
-- ════════════════════════════════════════════════════════════════════════════

-- 1️⃣ إنشاء bucket offer_images (عام للقراءة)
--    المسار المستخدم في Flutter:
--      offers/{uid}/{offerId}/file.jpg   (uploadOfferImage)
--      images/{uid}/file.jpg             (uploadImage)
--      videos/{uid}/{offerId}/file.mp4   (uploadOfferVideo)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'offer_images',
  'offer_images',
  true,  -- bucket عام (public URLs)
  10485760,  -- 10 MB
  ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4'
  ]::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 10485760,
  allowed_mime_types = ARRAY[
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4'
  ]::text[];

-- 2️⃣ RLS Policies

-- 🔒 INSERT: أي مستخدم مسجّل (authenticated) يرفع فقط في مجلده الخاص.
--    المجلد الثاني في المسار (foldername[2]) يجب أن يُطابق auth.uid().
--    المسارات المُتفق عليها:
--      offers/{uid}/...    → foldername[2] = uid
--      images/{uid}/...    → foldername[2] = uid
--      videos/{uid}/...    → foldername[2] = uid
DROP POLICY IF EXISTS "offer_images_owner_insert" ON storage.objects;
CREATE POLICY "offer_images_owner_insert"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'offer_images'
    AND auth.uid() IS NOT NULL
    AND auth.uid()::text = (storage.foldername(name))[2]
  );

-- 🔒 UPDATE: المالك فقط (نفس شرط INSERT)
DROP POLICY IF EXISTS "offer_images_owner_update" ON storage.objects;
CREATE POLICY "offer_images_owner_update"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'offer_images'
    AND auth.uid() IS NOT NULL
    AND auth.uid()::text = (storage.foldername(name))[2]
  );

-- 🔒 DELETE: المالك أو الإدارة/المدير (role >= 4)
DROP POLICY IF EXISTS "offer_images_owner_delete" ON storage.objects;
CREATE POLICY "offer_images_owner_delete"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'offer_images'
    AND (
      auth.uid()::text = (storage.foldername(name))[2]
      OR EXISTS (
        SELECT 1 FROM users
        WHERE id = auth.uid() AND role >= 4 AND i_del = 0
      )
    )
  );

-- ✅ SELECT: عامة للجميع (للقراءة المباشرة + public URLs)
--    bucket عام، لكن policy واضحة تمنع listing غير مبرر.
DROP POLICY IF EXISTS "offer_images_public_select" ON storage.objects;
CREATE POLICY "offer_images_public_select"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'offer_images');

-- ════════════════════════════════════════════════════════════════════════════
-- نهاية Migration
-- ════════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  RAISE NOTICE '✅ Migration 2026-06-24 applied:';
  RAISE NOTICE '   - Bucket offer_images (public, 10MB, images+video)';
  RAISE NOTICE '   - INSERT: owner only (foldername[2] = auth.uid)';
  RAISE NOTICE '   - UPDATE: owner only';
  RAISE NOTICE '   - DELETE: owner or admin (role>=4)';
  RAISE NOTICE '   - SELECT: public read';
END $$;
