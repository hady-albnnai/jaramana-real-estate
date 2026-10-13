-- ══════════════════════════════════════════════════════════════════════
-- Migration: Secure Email Magic Link Auth Handler
-- Date: 2026-06-17
-- Purpose:
--   Move email Magic Link user upsert from client-side select/insert to a
--   SECURITY DEFINER RPC that derives the email from Supabase Auth JWT.
--   Also harden uniqueness for active emails and non-empty phone numbers.
-- ══════════════════════════════════════════════════════════════════════

-- 1) Remove legacy raw phone unique constraint if it exists.
--    Email-only users may have empty phone; uniqueness should apply only to
--    real non-empty phone numbers after normalization.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_ph_key;

CREATE UNIQUE INDEX IF NOT EXISTS users_unique_phone_active
  ON public.users (public.normalize_sy_phone(ph))
  WHERE i_del = 0
    AND ph IS NOT NULL
    AND btrim(ph) <> '';

-- 2) Canonical active email uniqueness, case-insensitive.
--    The older idx_users_eml_unique may be case-sensitive; keep it for
--    compatibility and add the stricter canonical form.
CREATE UNIQUE INDEX IF NOT EXISTS users_unique_email_active_lower
  ON public.users (lower(btrim(eml)))
  WHERE i_del = 0
    AND eml IS NOT NULL
    AND btrim(eml) <> '';

-- 3) Secure RPC for Supabase Auth email sessions.
--    Important: client cannot pass the email. It is read from auth.jwt().
CREATE OR REPLACE FUNCTION public.handle_email_auth_internal()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_auth_uid UUID;
  v_email TEXT;
  v_uid UUID;
  v_existing_email TEXT;
  v_is_new BOOLEAN := FALSE;
BEGIN
  v_auth_uid := auth.uid();
  v_email := lower(btrim(coalesce(auth.jwt()->>'email', '')));

  IF v_auth_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF v_email = '' THEN
    RAISE EXCEPTION 'EMAIL_REQUIRED';
  END IF;

  IF v_email !~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$' THEN
    RAISE EXCEPTION 'EMAIL_INVALID';
  END IF;

  IF v_email LIKE '%@whatsapp.local' THEN
    RAISE EXCEPTION 'PSEUDO_EMAIL_NOT_ALLOWED';
  END IF;

  -- Prevent concurrent duplicate creation for the same email.
  PERFORM pg_advisory_xact_lock(hashtext(v_email));

  -- Prefer a row already linked to this Supabase Auth UID.
  SELECT u.id, lower(btrim(coalesce(u.eml, '')))
  INTO v_uid, v_existing_email
  FROM public.users u
  WHERE u.id = v_auth_uid
    AND u.i_del = 0
  LIMIT 1;

  IF v_uid IS NOT NULL THEN
    IF v_existing_email <> '' AND v_existing_email <> v_email THEN
      RAISE EXCEPTION 'AUTH_UID_EMAIL_CONFLICT';
    END IF;

    UPDATE public.users
    SET eml = v_email,
        ts_upd = now()
    WHERE id = v_uid;

    RETURN jsonb_build_object(
      'success', true,
      'user_id', v_uid,
      'is_new', false,
      'email', v_email
    );
  END IF;

  -- Backward compatibility: existing legacy row by email may not have id=auth.uid().
  SELECT u.id
  INTO v_uid
  FROM public.users u
  WHERE lower(btrim(coalesce(u.eml, ''))) = v_email
    AND u.i_del = 0
  ORDER BY u.ts_crt ASC
  LIMIT 1;

  IF v_uid IS NULL THEN
    INSERT INTO public.users (
      id, nm, ph, eml, role, sts, i_del, ts_crt, ts_upd
    ) VALUES (
      v_auth_uid, '', '', v_email, 0, 0, 0, now(), now()
    )
    RETURNING id INTO v_uid;

    v_is_new := TRUE;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_uid,
    'is_new', v_is_new,
    'email', v_email
  );
END;
$$;

REVOKE ALL ON FUNCTION public.handle_email_auth_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_email_auth_internal() FROM anon;
GRANT EXECUTE ON FUNCTION public.handle_email_auth_internal() TO authenticated;

COMMENT ON FUNCTION public.handle_email_auth_internal() IS
  'Secure Email Magic Link handler: derives email from auth.jwt(), atomically creates/returns public.users row, and prevents client-side email spoofing.';
