-- Backfill renewal sessions that existed before lawyer_earnings triggers.
INSERT INTO public.lawyer_earnings(lawyer_uid,consultation_id,session_id,payment_id,
 service_kind,gross_amount,share_percent,lawyer_amount,office_amount,status,earned_at)
SELECT c.lawyer_uid,c.id,s.id,s.payment_id,'phone_renewal',p.amt,
 public.legal_lawyer_share_percent(),round(p.amt*public.legal_lawyer_share_percent()/100,2),
 round(p.amt-(p.amt*public.legal_lawyer_share_percent()/100),2),
 CASE WHEN s.status='ended' THEN 'earned' WHEN s.status IN('cancelled','reversed') THEN 'cancelled' ELSE 'pending' END,
 CASE WHEN s.status='ended' THEN COALESCE(s.ended_at,s.ts_upd) ELSE NULL END
FROM public.consultation_chat_sessions s
JOIN public.legal_consultations c ON c.id=s.consultation_id
JOIN public.payments p ON p.id=s.payment_id
WHERE s.kind='renewal' AND s.payment_id IS NOT NULL AND c.lawyer_uid IS NOT NULL
ON CONFLICT(payment_id) DO NOTHING;
