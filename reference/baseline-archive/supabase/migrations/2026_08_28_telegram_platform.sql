-- ══════════════════════════════════════════════════════════════════════════════
-- 2026-08-28: إضافة منصة تليجرام لنظام حسابات النشر
--
-- الهدف: تمكين النشر التلقائي على قنوات تليجرام (بوت + قناة) — بلا تسجيل
-- مطورين وبلا عقوبات (خلافاً لـ Meta) — كخيار مفتوح قابل للتفعيل متى شاء
-- المالك من شاشة «حسابات النشر» (نفس الجدول: platform='telegram'،
-- account_external_id = معرف القناة مثل ‎-100xxxxxxxxxx، access_token = توكن البوت).
--
-- idempotent: DROP IF EXISTS + ADD للقيود، وCREATE OR REPLACE للدوال.
-- الترتيب: شغّل هذا الملف ثم انشر الدوال الثلاث (social-accounts + admin-offers
-- + publish-to-social).
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1) توسيع قيود المنصة لتشمل تليجرام ──
ALTER TABLE public.social_accounts DROP CONSTRAINT IF EXISTS social_accounts_platform_check;
ALTER TABLE public.social_accounts
  ADD CONSTRAINT social_accounts_platform_check
  CHECK (platform IN ('facebook', 'instagram', 'telegram'));

ALTER TABLE public.social_publications DROP CONSTRAINT IF EXISTS social_publications_platform_check;
ALTER TABLE public.social_publications
  ADD CONSTRAINT social_publications_platform_check
  CHECK (platform IN ('facebook', 'instagram', 'telegram'));

-- ── 2) تحديث حاجزي المنصة في دالتي الحجز (نفس الأجساد، المنصة تليجرام مسموحة) ──

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
  IF p_platform NOT IN ('facebook', 'instagram', 'telegram') THEN
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
  IF p_platform NOT IN ('facebook', 'instagram', 'telegram') THEN
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
