-- =============================================================================
-- 2026-08-16 — Lawyer financial ledger: 50% of legal service gross price
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.legal_finance_config (
 id boolean PRIMARY KEY DEFAULT true CHECK(id),
 lawyer_share_percent numeric(5,2) NOT NULL CHECK(lawyer_share_percent>=0 AND lawyer_share_percent<=100),
 ts_upd timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.legal_finance_config(id,lawyer_share_percent)
VALUES(true,50) ON CONFLICT(id) DO NOTHING;
ALTER TABLE public.legal_finance_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.legal_finance_config FROM PUBLIC,anon,authenticated;
GRANT ALL ON TABLE public.legal_finance_config TO service_role;

CREATE TABLE IF NOT EXISTS public.lawyer_earnings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 lawyer_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
 consultation_id uuid NOT NULL REFERENCES public.legal_consultations(id) ON DELETE CASCADE,
 session_id uuid REFERENCES public.consultation_chat_sessions(id) ON DELETE SET NULL,
 appointment_id uuid REFERENCES public.appointments(id) ON DELETE SET NULL,
 payment_id uuid NOT NULL REFERENCES public.payments(id) ON DELETE RESTRICT,
 service_kind text NOT NULL CHECK(service_kind IN('phone_initial','phone_renewal','onsite')),
 gross_amount numeric(14,2) NOT NULL CHECK(gross_amount>=0),
 share_percent numeric(5,2) NOT NULL CHECK(share_percent>=0 AND share_percent<=100),
 lawyer_amount numeric(14,2) NOT NULL CHECK(lawyer_amount>=0),
 office_amount numeric(14,2) NOT NULL CHECK(office_amount>=0),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN('pending','earned','reversed','cancelled')),
 earned_at timestamptz,
 reversed_at timestamptz,
 ts_crt timestamptz NOT NULL DEFAULT now(),
 ts_upd timestamptz NOT NULL DEFAULT now(),
 UNIQUE(payment_id)
);
ALTER TABLE public.lawyer_earnings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lawyer_earnings FROM PUBLIC,anon,authenticated;
GRANT ALL ON TABLE public.lawyer_earnings TO service_role;
CREATE INDEX IF NOT EXISTS idx_lawyer_earnings_lawyer_status
 ON public.lawyer_earnings(lawyer_uid,status,ts_crt DESC);
CREATE INDEX IF NOT EXISTS idx_lawyer_earnings_consultation
 ON public.lawyer_earnings(consultation_id);

CREATE OR REPLACE FUNCTION public.legal_lawyer_share_percent()
RETURNS numeric
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v numeric;
BEGIN
 SELECT lawyer_share_percent INTO v
 FROM public.legal_finance_config WHERE id=true;
 IF v IS NULL OR v<0 OR v>100 THEN RAISE EXCEPTION 'INVALID_LAWYER_SHARE_PERCENT'; END IF;
 RETURN v;
END;
$function$;

CREATE OR REPLACE FUNCTION public.insert_lawyer_earning(
 p_lawyer uuid,p_consultation uuid,p_session uuid,p_appointment uuid,p_payment uuid,p_kind text,p_gross numeric
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_pct numeric; v_id uuid;
BEGIN
 IF p_lawyer IS NULL OR p_payment IS NULL OR p_gross IS NULL THEN RETURN NULL; END IF;
 v_pct:=public.legal_lawyer_share_percent();
 INSERT INTO public.lawyer_earnings(lawyer_uid,consultation_id,session_id,appointment_id,payment_id,
  service_kind,gross_amount,share_percent,lawyer_amount,office_amount,status)
 VALUES(p_lawyer,p_consultation,p_session,p_appointment,p_payment,p_kind,p_gross,v_pct,
  round(p_gross*v_pct/100,2),round(p_gross-(p_gross*v_pct/100),2),'pending')
 ON CONFLICT(payment_id) DO UPDATE SET lawyer_uid=EXCLUDED.lawyer_uid,ts_upd=now()
 RETURNING id INTO v_id;
 RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_consultation_earning_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.payment_id IS NOT NULL AND NEW.lawyer_uid IS NOT NULL THEN
  PERFORM public.insert_lawyer_earning(NEW.lawyer_uid,NEW.id,NULL,NULL,NEW.payment_id,
   CASE WHEN NEW.service_type=1 THEN 'onsite' ELSE 'phone_initial' END,NEW.price);
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_session_earning_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE c public.legal_consultations%ROWTYPE; gross numeric;
BEGIN
 IF NEW.kind='renewal' AND NEW.payment_id IS NOT NULL THEN
  SELECT * INTO c FROM public.legal_consultations WHERE id=NEW.consultation_id;
  SELECT amt INTO gross FROM public.payments WHERE id=NEW.payment_id;
  PERFORM public.insert_lawyer_earning(c.lawyer_uid,c.id,NEW.id,NULL,NEW.payment_id,'phone_renewal',gross);
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_session_earning_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.status='ended' AND OLD.status IS DISTINCT FROM NEW.status THEN
  IF NEW.payment_id IS NOT NULL THEN
   UPDATE public.lawyer_earnings SET status='earned',earned_at=now(),ts_upd=now()
    WHERE payment_id=NEW.payment_id AND status='pending';
  ELSE
   UPDATE public.lawyer_earnings SET status='earned',earned_at=now(),ts_upd=now()
    WHERE consultation_id=NEW.consultation_id AND service_kind='phone_initial' AND status='pending';
  END IF;
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_appointment_earning_status()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.kind='legal' THEN
  UPDATE public.lawyer_earnings SET appointment_id=NEW.id,ts_upd=now()
   WHERE consultation_id=NEW.consultation_id AND appointment_id IS NULL;
  IF (NEW.sts=2 AND OLD.sts IS DISTINCT FROM NEW.sts)
     OR (NEW.sts=3 AND OLD.sts IS DISTINCT FROM NEW.sts
         AND COALESCE(NEW.cnl_rsn,'') LIKE 'إلغاء المستخدم بلا استرداد:%') THEN
   UPDATE public.lawyer_earnings SET status='earned',earned_at=now(),ts_upd=now()
    WHERE consultation_id=NEW.consultation_id AND status='pending';
  END IF;
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_appointment_earning_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.kind='legal' THEN
  UPDATE public.lawyer_earnings SET appointment_id=NEW.id,ts_upd=now()
   WHERE consultation_id=NEW.consultation_id AND appointment_id IS NULL;
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_payment_earning_reversal()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.sts=3 AND OLD.sts IS DISTINCT FROM NEW.sts THEN
  UPDATE public.lawyer_earnings SET status='reversed',reversed_at=now(),ts_upd=now()
   WHERE payment_id=NEW.id AND status<>'reversed';
 END IF;
 RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.trg_consultation_earning_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.lawyer_uid IS DISTINCT FROM OLD.lawyer_uid AND NEW.lawyer_uid IS NOT NULL THEN
  UPDATE public.lawyer_earnings SET lawyer_uid=NEW.lawyer_uid,ts_upd=now()
   WHERE consultation_id=NEW.id AND status='pending';
 END IF;
 IF NEW.status IN(3,4) AND OLD.status IS DISTINCT FROM NEW.status THEN
  UPDATE public.lawyer_earnings SET status='cancelled',ts_upd=now()
   WHERE consultation_id=NEW.id AND status='pending';
 END IF;
 RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_consultation_earning_insert ON public.legal_consultations;
CREATE TRIGGER trg_consultation_earning_insert AFTER INSERT ON public.legal_consultations
 FOR EACH ROW EXECUTE FUNCTION public.trg_consultation_earning_insert();
DROP TRIGGER IF EXISTS trg_consultation_earning_update ON public.legal_consultations;
CREATE TRIGGER trg_consultation_earning_update AFTER UPDATE ON public.legal_consultations
 FOR EACH ROW EXECUTE FUNCTION public.trg_consultation_earning_update();
DROP TRIGGER IF EXISTS trg_session_earning_insert ON public.consultation_chat_sessions;
CREATE TRIGGER trg_session_earning_insert AFTER INSERT ON public.consultation_chat_sessions
 FOR EACH ROW EXECUTE FUNCTION public.trg_session_earning_insert();
DROP TRIGGER IF EXISTS trg_session_earning_status ON public.consultation_chat_sessions;
CREATE TRIGGER trg_session_earning_status AFTER UPDATE OF status ON public.consultation_chat_sessions
 FOR EACH ROW EXECUTE FUNCTION public.trg_session_earning_status();
DROP TRIGGER IF EXISTS trg_appointment_earning_insert ON public.appointments;
CREATE TRIGGER trg_appointment_earning_insert AFTER INSERT ON public.appointments
 FOR EACH ROW EXECUTE FUNCTION public.trg_appointment_earning_insert();
DROP TRIGGER IF EXISTS trg_appointment_earning_status ON public.appointments;
CREATE TRIGGER trg_appointment_earning_status AFTER UPDATE ON public.appointments
 FOR EACH ROW EXECUTE FUNCTION public.trg_appointment_earning_status();
DROP TRIGGER IF EXISTS trg_payment_earning_reversal ON public.payments;
CREATE TRIGGER trg_payment_earning_reversal AFTER UPDATE OF sts ON public.payments
 FOR EACH ROW EXECUTE FUNCTION public.trg_payment_earning_reversal();

-- Backfill existing legal payments, including the currently active test consultation.
INSERT INTO public.lawyer_earnings(lawyer_uid,consultation_id,payment_id,service_kind,
 gross_amount,share_percent,lawyer_amount,office_amount,status,earned_at)
SELECT l.lawyer_uid,l.id,l.payment_id,CASE WHEN l.service_type=1 THEN 'onsite' ELSE 'phone_initial' END,
 l.price,public.legal_lawyer_share_percent(),round(l.price*public.legal_lawyer_share_percent()/100,2),
 round(l.price-(l.price*public.legal_lawyer_share_percent()/100),2),
 CASE WHEN l.status=2 THEN 'earned' ELSE 'pending' END,
 CASE WHEN l.status=2 THEN l.ts_upd ELSE NULL END
FROM public.legal_consultations l
WHERE l.payment_id IS NOT NULL AND l.lawyer_uid IS NOT NULL
ON CONFLICT(payment_id) DO NOTHING;

REVOKE ALL ON FUNCTION public.legal_lawyer_share_percent() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.insert_lawyer_earning(uuid,uuid,uuid,uuid,uuid,text,numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.legal_lawyer_share_percent() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.insert_lawyer_earning(uuid,uuid,uuid,uuid,uuid,text,numeric) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.legal_lawyer_share_percent() TO service_role;
GRANT EXECUTE ON FUNCTION public.insert_lawyer_earning(uuid,uuid,uuid,uuid,uuid,text,numeric) TO service_role;
REVOKE ALL ON FUNCTION public.trg_consultation_earning_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_consultation_earning_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_session_earning_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_session_earning_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_appointment_earning_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_appointment_earning_status() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_payment_earning_reversal() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_consultation_earning_insert() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_consultation_earning_update() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_session_earning_insert() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_session_earning_status() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_appointment_earning_insert() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_appointment_earning_status() FROM anon,authenticated;
REVOKE EXECUTE ON FUNCTION public.trg_payment_earning_reversal() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.trg_consultation_earning_insert() TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_consultation_earning_update() TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_session_earning_insert() TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_session_earning_status() TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_appointment_earning_insert() TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_appointment_earning_status() TO service_role;
GRANT EXECUTE ON FUNCTION public.trg_payment_earning_reversal() TO service_role;
