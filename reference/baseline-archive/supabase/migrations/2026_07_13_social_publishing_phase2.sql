-- Phase 2: real Facebook + Instagram publishing.
-- Apply before deploying publish-to-social/admin-offers.

BEGIN;

-- soc_pub: 0=disabled, 1=queued, 2=published on both configured platforms.
ALTER TABLE public.offers DROP CONSTRAINT IF EXISTS offers_soc_pub_check;
ALTER TABLE public.offers
  ADD CONSTRAINT offers_soc_pub_check CHECK (soc_pub IN (0, 1, 2));

-- One durable result per offer/platform prevents duplicate posts on retry.
CREATE TABLE IF NOT EXISTS public.social_publications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  offer_id UUID NOT NULL REFERENCES public.offers(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('facebook', 'instagram')),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'publishing', 'published', 'failed')),
  post_id TEXT NOT NULL DEFAULT '',
  attempt_token UUID,
  attempts INTEGER NOT NULL DEFAULT 0,
  error_message TEXT NOT NULL DEFAULT '',
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (offer_id, platform)
);
CREATE INDEX IF NOT EXISTS idx_social_publications_status
  ON public.social_publications(status, updated_at);

ALTER TABLE public.social_publications ENABLE ROW LEVEL SECURITY;
-- No client policies: only service-role Edge Functions access this table.

-- Atomic claim. A 10-minute stale claim can be retried after an interrupted function.
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
  ON CONFLICT (offer_id, platform) DO NOTHING
  RETURNING * INTO v_row;

  IF FOUND THEN
    RETURN 'claimed';
  END IF;

  SELECT * INTO v_row
  FROM public.social_publications
  WHERE offer_id = p_offer_id AND platform = p_platform
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

-- Auto mode is off by default; admin may enable it from /admin/config.
UPDATE public.app_config
SET value = jsonb_set(
  value,
  '{socialPublishing}',
  COALESCE(value->'socialPublishing', '{}'::jsonb)
    || '{"autoPublish": false}'::jsonb,
  true
)
WHERE key = 'main'
  AND NOT (COALESCE(value->'socialPublishing', '{}'::jsonb) ? 'autoPublish');

COMMIT;
