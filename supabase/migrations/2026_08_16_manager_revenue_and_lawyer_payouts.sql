-- =============================================================================
-- 2026-08-16 — manager-only revenue report + lawyer payouts
-- =============================================================================
ALTER TABLE public.payments
 ADD COLUMN IF NOT EXISTS approved_at timestamptz,
 ADD COLUMN IF NOT EXISTS decision_at timestamptz,
 ADD COLUMN IF NOT EXISTS approval_time_estimated boolean NOT NULL DEFAULT false;

UPDATE public.payments SET approved_at=COALESCE(approved_at,ts_crt),decision_at=COALESCE(decision_at,ts_crt),
 approval_time_estimated=true WHERE sts=1 AND approved_at IS NULL;
UPDATE public.payments SET decision_at=COALESCE(decision_at,ts_crt),approval_time_estimated=true
 WHERE sts IN(2,3) AND decision_at IS NULL;

CREATE OR REPLACE FUNCTION public.trg_payment_decision_timestamps()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF NEW.sts IS DISTINCT FROM OLD.sts THEN
  NEW.decision_at:=now();
  NEW.approval_time_estimated:=false;
  IF NEW.sts=1 THEN NEW.approved_at:=now(); END IF;
 END IF;
 RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_payment_decision_timestamps ON public.payments;
CREATE TRIGGER trg_payment_decision_timestamps BEFORE UPDATE OF sts ON public.payments
 FOR EACH ROW EXECUTE FUNCTION public.trg_payment_decision_timestamps();
REVOKE ALL ON FUNCTION public.trg_payment_decision_timestamps() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_payment_decision_timestamps() FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.trg_payment_decision_timestamps() TO service_role;

CREATE TABLE IF NOT EXISTS public.lawyer_payouts(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 lawyer_uid uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
 amount numeric(14,2) NOT NULL CHECK(amount>0),
 currency integer NOT NULL DEFAULT 1,
 paid_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
 note text NOT NULL DEFAULT '',
 paid_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.lawyer_payouts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.lawyer_payouts FROM PUBLIC,anon,authenticated;
GRANT ALL ON TABLE public.lawyer_payouts TO service_role;

ALTER TABLE public.lawyer_earnings
 ADD COLUMN IF NOT EXISTS payout_id uuid REFERENCES public.lawyer_payouts(id) ON DELETE SET NULL,
 ADD COLUMN IF NOT EXISTS paid_at timestamptz,
 ADD COLUMN IF NOT EXISTS paid_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.lawyer_earnings DROP CONSTRAINT IF EXISTS lawyer_earnings_status_check;
ALTER TABLE public.lawyer_earnings ADD CONSTRAINT lawyer_earnings_status_check
 CHECK(status IN('pending','earned','paid','reversed','cancelled'));

CREATE OR REPLACE FUNCTION public.mark_lawyer_earnings_paid(
 p_manager_uid uuid,p_lawyer_uid uuid,p_note text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer; v_amount numeric; v_payout uuid; v_count integer;
BEGIN
 SELECT role INTO v_role FROM public.users WHERE id=p_manager_uid AND sts=0 AND i_del=0;
 IF v_role<>6 THEN RAISE EXCEPTION 'ONLY_MANAGER_CAN_MARK_PAYOUT'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('lawyer-payout:'||p_lawyer_uid::text,0));
 PERFORM 1 FROM public.lawyer_earnings
  WHERE lawyer_uid=p_lawyer_uid AND status='earned' FOR UPDATE;
 SELECT COALESCE(sum(lawyer_amount),0),count(*) INTO v_amount,v_count
 FROM public.lawyer_earnings WHERE lawyer_uid=p_lawyer_uid AND status='earned';
 IF v_amount<=0 OR v_count=0 THEN RAISE EXCEPTION 'NO_LAWYER_PAYABLE_BALANCE'; END IF;
 INSERT INTO public.lawyer_payouts(lawyer_uid,amount,paid_by,note)
 VALUES(p_lawyer_uid,v_amount,p_manager_uid,trim(COALESCE(p_note,''))) RETURNING id INTO v_payout;
 UPDATE public.lawyer_earnings SET status='paid',payout_id=v_payout,paid_at=now(),paid_by=p_manager_uid,ts_upd=now()
 WHERE lawyer_uid=p_lawyer_uid AND status='earned';
 INSERT INTO public.notifications(uid,tp,ttl,bdy,ref_id,act,i_rd,i_del,ts_crt)
 VALUES(p_lawyer_uid,3,'💰 تم تسجيل دفع مستحقاتك',
  'سجّل المكتب دفع مبلغ '||to_char(v_amount,'FM999G999G999')||' ل.س من مستحقات الاستشارات.',
  v_payout::text,'lawyer_payout_paid',0,0,now());
 RETURN jsonb_build_object('success',true,'payout_id',v_payout,'amount',v_amount,'entries',v_count);
END;
$function$;
REVOKE ALL ON FUNCTION public.mark_lawyer_earnings_paid(uuid,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mark_lawyer_earnings_paid(uuid,uuid,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.mark_lawyer_earnings_paid(uuid,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_manager_revenue_report(
 p_manager_uid uuid,p_from timestamptz,p_to timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer; v_from timestamptz; v_to timestamptz;
 v_gross numeric; v_packages numeric; v_featured numeric; v_legal numeric; v_lawyer numeric;
 v_pending numeric; v_reversed numeric; v_channels jsonb; v_daily jsonb; v_deals jsonb;
 v_lawyers jsonb; v_entries jsonb;
BEGIN
 SELECT role INTO v_role FROM public.users WHERE id=p_manager_uid AND sts=0 AND i_del=0;
 IF v_role<>6 THEN RAISE EXCEPTION 'ONLY_MANAGER_CAN_VIEW_REVENUE'; END IF;
 v_from:=COALESCE(p_from,'2000-01-01'::timestamptz); v_to:=COALESCE(p_to,now()+interval '1 day');
 IF v_to<=v_from THEN RAISE EXCEPTION 'INVALID_DATE_RANGE'; END IF;

 WITH approved AS (SELECT * FROM public.payments WHERE sts=1 AND cur=1 AND approved_at>=v_from AND approved_at<v_to)
 SELECT COALESCE(sum(amt),0),COALESCE(sum(amt) FILTER(WHERE tp=0),0),
  COALESCE(sum(amt) FILTER(WHERE tp=1),0),COALESCE(sum(amt) FILTER(WHERE tp=2),0)
 INTO v_gross,v_packages,v_featured,v_legal FROM approved;

 SELECT COALESCE(sum(e.lawyer_amount),0) INTO v_lawyer
 FROM public.lawyer_earnings e JOIN public.payments p ON p.id=e.payment_id
 WHERE p.sts=1 AND p.cur=1 AND p.approved_at>=v_from AND p.approved_at<v_to
  AND e.status IN('pending','earned','paid');
 SELECT COALESCE(sum(amt),0) INTO v_pending FROM public.payments
  WHERE sts=0 AND cur=1 AND ts_crt>=v_from AND ts_crt<v_to;
 SELECT COALESCE(sum(amt),0) INTO v_reversed FROM public.payments
  WHERE sts=3 AND cur=1 AND decision_at>=v_from AND decision_at<v_to;

 SELECT COALESCE(jsonb_agg(jsonb_build_object('channel',channel,'amount',amount,'operations',operations)
  ORDER BY amount DESC),'[]'::jsonb) INTO v_channels FROM (
  SELECT COALESCE(channel,'unknown') channel,sum(amt) amount,count(*) operations FROM public.payments
  WHERE sts=1 AND cur=1 AND approved_at>=v_from AND approved_at<v_to GROUP BY channel) q;

 SELECT COALESCE(jsonb_agg(jsonb_build_object('day',revenue_day,'gross',gross,'lawyer_share',lawyer_share,
  'office_net',gross-lawyer_share) ORDER BY revenue_day),'[]'::jsonb) INTO v_daily FROM (
  SELECT (p.approved_at AT TIME ZONE 'Asia/Damascus')::date revenue_day,sum(p.amt) gross,
   COALESCE(sum(e.lawyer_amount) FILTER(WHERE e.status IN('pending','earned','paid')),0) lawyer_share
  FROM public.payments p LEFT JOIN public.lawyer_earnings e ON e.payment_id=p.id
  WHERE p.sts=1 AND p.cur=1 AND p.approved_at>=v_from AND p.approved_at<v_to GROUP BY 1) q;

 SELECT COALESCE(jsonb_agg(jsonb_build_object('currency',cur,'amount',amount,'deals',deals)
  ORDER BY cur),'[]'::jsonb) INTO v_deals FROM (
  SELECT cur,sum(com_val) amount,count(*) deals FROM public.deals
  WHERE sts IN(1,2) AND i_del=0 AND COALESCE(ts_cmpl,ts_crt)>=v_from AND COALESCE(ts_cmpl,ts_crt)<v_to
  GROUP BY cur) q;

 SELECT COALESCE(jsonb_agg(jsonb_build_object('lawyer_uid',lawyer_uid,'lawyer_name',nm,
  'pending',pending,'payable',payable,'paid',paid) ORDER BY payable DESC),'[]'::jsonb)
 INTO v_lawyers FROM (
  SELECT e.lawyer_uid,u.nm,
   COALESCE(sum(e.lawyer_amount) FILTER(WHERE e.status='pending'),0) pending,
   COALESCE(sum(e.lawyer_amount) FILTER(WHERE e.status='earned'),0) payable,
   COALESCE(sum(e.lawyer_amount) FILTER(WHERE e.status='paid'),0) paid
  FROM public.lawyer_earnings e JOIN public.users u ON u.id=e.lawyer_uid
  GROUP BY e.lawyer_uid,u.nm) q;

 SELECT COALESCE(jsonb_agg(entry ORDER BY recognized_at DESC),'[]'::jsonb) INTO v_entries FROM (
  SELECT jsonb_build_object('source','payment','id',p.id,'category',CASE p.tp WHEN 0 THEN 'package' WHEN 1 THEN 'featured' ELSE 'legal' END,
   'gross',p.amt,'deduction',COALESCE(e.lawyer_amount,0),'office_net',p.amt-COALESCE(e.lawyer_amount,0),
   'currency',p.cur,'channel',p.channel,'recognized_at',p.approved_at,'estimated_time',p.approval_time_estimated) entry,p.approved_at recognized_at
  FROM public.payments p LEFT JOIN public.lawyer_earnings e ON e.payment_id=p.id
  WHERE p.sts=1 AND p.approved_at>=v_from AND p.approved_at<v_to
  UNION ALL
  SELECT jsonb_build_object('source','deal','id',d.id,'category','deal_commission','gross',d.com_val,
   'deduction',0,'office_net',d.com_val,'currency',d.cur,'channel',NULL,
   'recognized_at',COALESCE(d.ts_cmpl,d.ts_crt),'estimated_time',false),COALESCE(d.ts_cmpl,d.ts_crt)
  FROM public.deals d WHERE d.sts IN(1,2) AND d.i_del=0
   AND COALESCE(d.ts_cmpl,d.ts_crt)>=v_from AND COALESCE(d.ts_cmpl,d.ts_crt)<v_to
  LIMIT 300) q;

 RETURN jsonb_build_object('success',true,'from',v_from,'to',v_to,
  'payments_syp',jsonb_build_object('gross',v_gross,'packages',v_packages,'featured',v_featured,
   'legal_gross',v_legal,'lawyer_share',v_lawyer,'office_net',v_gross-v_lawyer,
   'pending',v_pending,'reversed',v_reversed),
  'deal_commissions',v_deals,'channels',v_channels,'daily',v_daily,'lawyers',v_lawyers,'entries',v_entries);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_manager_revenue_report(uuid,timestamptz,timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_manager_revenue_report(uuid,timestamptz,timestamptz) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_manager_revenue_report(uuid,timestamptz,timestamptz) TO service_role;

CREATE OR REPLACE FUNCTION public.admin_reverse_payment_v3(
 p_admin_uid uuid,p_payment_id uuid,p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
BEGIN
 IF EXISTS(SELECT 1 FROM public.lawyer_earnings WHERE payment_id=p_payment_id AND status='paid') THEN
  RAISE EXCEPTION 'LAWYER_SHARE_ALREADY_PAID';
 END IF;
 RETURN public.admin_reverse_payment_v2(p_admin_uid,p_payment_id,p_reason);
END;
$function$;
REVOKE ALL ON FUNCTION public.admin_reverse_payment_v3(uuid,uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_reverse_payment_v3(uuid,uuid,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reverse_payment_v3(uuid,uuid,text) TO service_role;

CREATE OR REPLACE FUNCTION public.get_manager_revenue_report_period(
 p_manager_uid uuid,p_period text
)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_today date:=(now() AT TIME ZONE 'Asia/Damascus')::date; v_from timestamptz; v_to timestamptz;
BEGIN
 v_to:=((v_today+1)::timestamp AT TIME ZONE 'Asia/Damascus');
 CASE COALESCE(p_period,'month')
  WHEN 'today' THEN v_from:=(v_today::timestamp AT TIME ZONE 'Asia/Damascus');
  WHEN '7days' THEN v_from:=((v_today-6)::timestamp AT TIME ZONE 'Asia/Damascus');
  WHEN 'month' THEN v_from:=(date_trunc('month',v_today::timestamp) AT TIME ZONE 'Asia/Damascus');
  WHEN 'all' THEN v_from:='2000-01-01'::timestamptz;
  ELSE RAISE EXCEPTION 'INVALID_REVENUE_PERIOD';
 END CASE;
 RETURN public.get_manager_revenue_report(p_manager_uid,v_from,v_to);
END;
$function$;
REVOKE ALL ON FUNCTION public.get_manager_revenue_report_period(uuid,text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_manager_revenue_report_period(uuid,text) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.get_manager_revenue_report_period(uuid,text) TO service_role;
