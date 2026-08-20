-- ══════════════════════════════════════════════════════════════════
-- 2026-08-20 — مزامنة حقيقة سند الملكية الحي (إقفال الدَّين 2)
--
-- الحقيقة الحية (من drift_markers):
--   • التريغر الحي ينقل أي سند وصوله إلى جدول offer_documents
--     (offer_id, doc_url, ts_upd) ويُفرّغ doc_img الظاهر — أحدث من
--     ملف 2026_07_29 بالريبو الذي كان يستخدم عمود doc_img_admin
--     (محذوف لاحقاً حياً — انحراف غير موثق).
--   • 0 وثيقة ظاهرة بأي عرض ⇒ لا تسريب قائم.
--   • 0 صفوف بجدول offer_documents (فرّغ سابقاً).
-- هذا الملف يسجّل بالريبو: الجدول + التريغر الحي حرفياً.
-- CREATE/REPLACE + IF NOT EXISTS = idempotent.
-- ══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.offer_documents (
  offer_id uuid PRIMARY KEY,
  doc_url text NOT NULL DEFAULT '',
  ts_upd timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.offer_documents ENABLE ROW LEVEL SECURITY;

-- الجدول يُدار عبر مفتاح الخدمة فقط (التريغر + الإيدجات) — لا قراءة عميل
REVOKE ALL ON public.offer_documents FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_offers_shield_doc_img()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF COALESCE(NEW.doc_img,'') <> '' THEN
    INSERT INTO public.offer_documents (offer_id, doc_url)
    VALUES (NEW.id, NEW.doc_img)
    ON CONFLICT (offer_id) DO UPDATE SET doc_url = EXCLUDED.doc_url, ts_upd = NOW();
    NEW.doc_img := '';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_offers_shield_doc_img() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_offers_shield_doc_img() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offers_shield_doc_img() TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- تحقق نهائي مدمج:
--   table_ok = true · trigger_uses_offer_documents = true ·
--   exposed_docs = 0 (لا سند ظاهر للعملاء)
-- ──────────────────────────────────────────────────────────────────────
SELECT
  (SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='offer_documents')) AS table_ok,
  (SELECT pg_get_functiondef(oid) LIKE '%offer_documents%'
     FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='trg_offers_shield_doc_img' LIMIT 1) AS trigger_uses_offer_documents,
  (SELECT count(*) FROM public.offers WHERE COALESCE(doc_img,'')<>'') AS exposed_docs;
