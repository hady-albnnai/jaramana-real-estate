-- ══════════════════════════════════════════════════════════════════════════════
-- 2026-08-27: إدارة حسابات النشر الاجتماعي من داخل التطبيق
--
-- الهدف: بدلاً من مفاتيح البيئة الثابتة (META_FACEBOOK_PAGE_ID /
-- META_PAGE_ACCESS_TOKEN / META_INSTAGRAM_ACCOUNT_ID) يصبح بالإمكان إضافة أي
-- عدد من حسابات فيسبوك/إنستغرام مع توكناتها من شاشة إدارية بالتطبيق
-- (Edge Function: social-accounts)، والناشر publishOfferToSocial ينشر على
-- كل الحسابات المفعّلة.
--
-- التوافق الخلفي:
--   1) مسار مفاتيح البيئة يبقى يعمل: إن لم يوجد أي حساب في social_accounts
--      يستخدم الناشر مفاتيح البيئة كما كان (claim_social_publication القديمة).
--   2) صفوف social_publications القديمة (account_id = NULL) تبقى كما هي —
--      تحميها فهارس جزئية fريدة تحافظ على حصرية (offer_id, platform) للمسار القديم
--      وتضيف حصرية (offer_id, account_id) للمسار الجديد.
--
-- الأمان: الجدول يخزّن توكنات وصول حساسة:
--   • RLS مفعّل بلا أي سياسة للعملاء (anon/authenticated لا يصلون لشيء).
--   • REVOKE صريح من anon/authenticated (دفاع مضاعف لو عُطّلت RLS بالخطأ).
--   • التوكن لا يعود للعميل أبداً — دالة social-accounts تعيد آخر 4 محارف فقط.
--
-- الترتيب: شغّل هذا الملف أولاً ثم انشر الدوال:
--   supabase functions deploy social-accounts --no-verify-jwt
--   supabase functions deploy admin-offers --no-verify-jwt
--   supabase functions deploy publish-to-social --no-verify-jwt
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─────────────────────────────────────────────
-- 1) جدول حسابات النشر
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.social_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- المنصة: فيسبوك (صفحة) أو إنستغرام (حساب مهني) — القائمة قابلة للتوسعة لاحقاً
  platform TEXT NOT NULL CHECK (platform IN ('facebook', 'instagram')),
  -- اسم للعرض داخل التطبيق (يختاره المدير)
  name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 1 AND 100),
  -- المعرف لدى Meta: Page ID لفيسبوك / IG Business ID لإنستغرام
  account_external_id TEXT NOT NULL
    CHECK (char_length(btrim(account_external_id)) BETWEEN 3 AND 64),
  -- توكن الوصول (Page Access Token طويل الأمد). لا يغادر السيرفر أبداً.
  access_token TEXT NOT NULL CHECK (char_length(access_token) BETWEEN 10 AND 4096),
  -- اسم الصفحة/الحساب الحقيقي كما أعاده Graph API عند آخر تحقق ناجح
  verified_name TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  last_error TEXT NOT NULL DEFAULT '',
  last_verified_at TIMESTAMPTZ,
  i_del INT NOT NULL DEFAULT 0 CHECK (i_del IN (0, 1)),
  ts_crt TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ts_upd TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- الحسابات المفعّلة لكل منصة (يقرؤها الناشر عند كل عملية نشر)
CREATE INDEX IF NOT EXISTS idx_social_accounts_active
  ON public.social_accounts(platform, is_active) WHERE i_del = 0;

ALTER TABLE public.social_accounts ENABLE ROW LEVEL SECURITY;
-- لا سياسات للعملاء: الوصول حصراً عبر service_role (Edge Functions).
REVOKE ALL ON public.social_accounts FROM anon, authenticated;
GRANT ALL ON public.social_accounts TO service_role;

-- ─────────────────────────────────────────────
-- 2) ربط سجلات النشر بالحسابات
-- ─────────────────────────────────────────────
ALTER TABLE public.social_publications
  ADD COLUMN IF NOT EXISTS account_id UUID
  REFERENCES public.social_accounts(id) ON DELETE SET NULL;

-- ─────────────────────────────────────────────
-- 3) الحصرية: فهرس جزئي لكل مسار
--    (بديل القيد UNIQUE(offer_id, platform) القديم الذي كان يمنع تعدد
--     الحسابات لنفس المنصة)
-- ─────────────────────────────────────────────
-- 3-أ) إسقاط القيد الفريد القديم إن وُجد (اسمه الافتراضي أو أي اسم آخر)
DO $$
DECLARE v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint
  WHERE conrelid = 'public.social_publications'::regclass
    AND contype = 'u'
    AND pg_get_constraintdef(oid) ~* 'offer_id[^,]*,\s*platform|platform[^,]*,\s*offer_id';
  IF v_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.social_publications DROP CONSTRAINT %I', v_constraint);
  END IF;
END $$;

-- 3-ب) منشور واحد كحد أقصى لكل (عرض، حساب) — المسار الجديد متعدد الحسابات
CREATE UNIQUE INDEX IF NOT EXISTS idx_social_pub_offer_account
  ON public.social_publications(offer_id, account_id)
  WHERE account_id IS NOT NULL;

-- 3-ج) حصرية المسار القديم (مفاتيح البيئة): منشور واحد لكل (عرض، منصة)
--      حيث account_id IS NULL — يحمي من التكرار كما كان القيد القديم.
CREATE UNIQUE INDEX IF NOT EXISTS idx_social_pub_offer_platform_legacy
  ON public.social_publications(offer_id, platform)
  WHERE account_id IS NULL;

-- ─────────────────────────────────────────────
-- 4) claim_social_publication (القديمة — إعادة إنشاء بنفس التوقيع)
--    التغيير الوحيد: ON CONFLICT يستهدف الفهرس الجزئي الجديد بدل القيد المُسقط.
--    تستخدمها آلية fallback بمفاتيح البيئة فقط.
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_social_publication(
  p_offer_id UUID,
  p_platform TEXT,
  p_attempt_token UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.social_publications%ROWTYPE;
BEGIN
  IF p_platform NOT IN ('facebook', 'instagram') THEN
    RAISE EXCEPTION 'INVALID_SOCIAL_PLATFORM';
  END IF;

  INSERT INTO public.social_publications (
    offer_id, platform, status, attempt_token, attempts, updated_at
  ) VALUES (
    p_offer_id, p_platform, 'publishing', p_attempt_token, 1, NOW()
  )
  ON CONFLICT (offer_id, platform) WHERE account_id IS NULL DO NOTHING
  RETURNING * INTO v_row;

  IF FOUND THEN
    RETURN 'claimed';
  END IF;

  SELECT * INTO v_row
  FROM public.social_publications
  WHERE offer_id = p_offer_id
    AND platform = p_platform
    AND account_id IS NULL
  FOR UPDATE;

  IF v_row.status = 'published' THEN
    RETURN 'published';
  END IF;

  IF v_row.status IN ('pending', 'failed')
     OR (v_row.status = 'publishing' AND v_row.updated_at < NOW() - INTERVAL '10 minutes') THEN
    UPDATE public.social_publications
    SET status = 'publishing',
        attempt_token = p_attempt_token,
        attempts = attempts + 1,
        error_message = '',
        updated_at = NOW()
    WHERE id = v_row.id;
    RETURN 'claimed';
  END IF;

  RETURN 'busy';
END;
$$;

REVOKE ALL ON FUNCTION public.claim_social_publication(UUID, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_social_publication(UUID, TEXT, UUID) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_social_publication(UUID, TEXT, UUID) TO service_role;

-- ─────────────────────────────────────────────
-- 5) claim_social_publication_v2 (الجديدة — لكل حساب على حدة)
--    تُستخدم من الناشر متعدد الحسابات: حجز ذرّي لكل (عرض، حساب)
--    يمنع النشر المزدوج عند إعادة المحاولة أو التزامن.
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.claim_social_publication_v2(
  p_offer_id UUID,
  p_account_id UUID,
  p_platform TEXT,
  p_attempt_token UUID
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.social_publications%ROWTYPE;
BEGIN
  IF p_platform NOT IN ('facebook', 'instagram') THEN
    RAISE EXCEPTION 'INVALID_SOCIAL_PLATFORM';
  END IF;
  IF p_account_id IS NULL THEN
    RAISE EXCEPTION 'ACCOUNT_ID_REQUIRED';
  END IF;

  INSERT INTO public.social_publications (
    offer_id, account_id, platform, status, attempt_token, attempts, updated_at
  ) VALUES (
    p_offer_id, p_account_id, p_platform, 'publishing', p_attempt_token, 1, NOW()
  )
  ON CONFLICT (offer_id, account_id) WHERE account_id IS NOT NULL DO NOTHING
  RETURNING * INTO v_row;

  IF FOUND THEN
    RETURN 'claimed';
  END IF;

  SELECT * INTO v_row
  FROM public.social_publications
  WHERE offer_id = p_offer_id
    AND account_id = p_account_id
  FOR UPDATE;

  IF v_row.status = 'published' THEN
    RETURN 'published';
  END IF;

  IF v_row.status IN ('pending', 'failed')
     OR (v_row.status = 'publishing' AND v_row.updated_at < NOW() - INTERVAL '10 minutes') THEN
    UPDATE public.social_publications
    SET status = 'publishing',
        attempt_token = p_attempt_token,
        attempts = attempts + 1,
        error_message = '',
        updated_at = NOW()
    WHERE id = v_row.id;
    RETURN 'claimed';
  END IF;

  RETURN 'busy';
END;
$$;

REVOKE ALL ON FUNCTION public.claim_social_publication_v2(UUID, UUID, TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.claim_social_publication_v2(UUID, UUID, TEXT, UUID) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_social_publication_v2(UUID, UUID, TEXT, UUID) TO service_role;

COMMIT;
