-- ============================================================================
-- 🟠 حجب وثيقة الملكية (doc_img) عن العملاء المباشرين
-- التاريخ: 2026-07-29
--
-- الثغرة (مُثبتة حيّاً): عمود doc_img ضمن offers المقروء anon، وقيمته رابط
-- .../storage/v1/object/**public**/... ⇒ جُلبت الصورة بلا أي مفتاح:
--   HTTP 200 · 289,526 بايت · image/jpeg
-- بينما الواجهة تحميها بشرط دور (offer_detail_screen.dart:1104 role>=employee)
-- ⇒ الحماية تجميلية، وأي زائر يقرأ REST يحصل على وثائق ملكية الجميع.
--
-- ⚠️ محاولة أولى فشلت وتراجعنا عنها فوراً (مسجّلة للتعلّم):
--    REVOKE SELECT + GRANT عمودي (كل الأعمدة عدا doc_img) ⇒ منطقي نظرياً،
--    لكنه يكسر التطبيق كلياً: العميل يستخدم .select() المفتوحة (SELECT *)
--    في 12+ موضع، وPostgres يرفضها 42501 عند نقص أي عمود ⇒ الرئيسية والبحث
--    وعروضي كلها 401. أُعيد المنح خلال ثوانٍ وأُثبت رجوع 200.
--    الدرس: منع الأعمدة غير متوافق مع select(*) — لا يُستخدم هنا.
--
-- ✅ الحل المعتمد: العمود يبقى مقروءاً (فلا شيء ينكسر) لكن **فارغاً** للعملاء:
--    ① عمود جديد doc_img_admin يحمل الرابط الحقيقي، محجوب عن anon/authenticated
--       بعدم منح أي صلاحية عليه إطلاقاً (عمود جديد = بلا منح افتراضي للأدوار).
--    ② ترحيل القيم الحالية إليه، وتفريغ doc_img.
--    ③ تريغر يحوّل أي كتابة لاحقة على doc_img إلى العمود الإداري ويُفرّغ الظاهر.
--    ⇒ SELECT * يبقى ناجحاً، وdoc_img يعود '' دائماً للعميل.
--
-- الإدارة غير متأثرة: تقرأ عبر إيدج admin-offers بمفتاح service_role.
-- ============================================================================

-- ① ─────────────── العمود الإداري
ALTER TABLE public.offers
  ADD COLUMN IF NOT EXISTS doc_img_admin TEXT DEFAULT '';

-- لا مِنَح لأدوار العميل عليه (تصريح للنية + حماية من default privileges)
REVOKE ALL (doc_img_admin) ON public.offers FROM anon, authenticated;

-- ② ─────────────── ترحيل القيم الحالية وتفريغ الظاهر
UPDATE public.offers
SET doc_img_admin = doc_img,
    doc_img = ''
WHERE COALESCE(doc_img, '') <> '';

-- ③ ─────────────── تريغر: أي كتابة لاحقة تُحوَّل تلقائياً
CREATE OR REPLACE FUNCTION public.trg_offers_shield_doc_img()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  -- أي قيمة تصل لـ doc_img تُخزَّن بالعمود الإداري ويُفرَّغ الظاهر
  IF COALESCE(NEW.doc_img, '') <> '' THEN
    NEW.doc_img_admin := NEW.doc_img;
    NEW.doc_img := '';
  END IF;

  -- تحديث لا يمس الوثيقة: لا نفقد القيمة الإدارية المحفوظة
  IF TG_OP = 'UPDATE'
     AND COALESCE(NEW.doc_img_admin, '') = ''
     AND COALESCE(OLD.doc_img_admin, '') <> '' THEN
    NEW.doc_img_admin := OLD.doc_img_admin;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL     ON FUNCTION public.trg_offers_shield_doc_img() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_offers_shield_doc_img() FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.trg_offers_shield_doc_img() TO service_role;

DROP TRIGGER IF EXISTS offers_shield_doc_img ON public.offers;
CREATE TRIGGER offers_shield_doc_img
  BEFORE INSERT OR UPDATE ON public.offers
  FOR EACH ROW EXECUTE FUNCTION public.trg_offers_shield_doc_img();

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① لا وثيقة ظاهرة لأي عرض  → المتوقع: 0
SELECT count(*) AS visible_docs
FROM public.offers WHERE COALESCE(doc_img, '') <> '';

-- ② الوثائق محفوظة إدارياً  → المتوقع: 3 (عدد ما كان مكشوفاً)
SELECT count(*) AS preserved_docs
FROM public.offers WHERE COALESCE(doc_img_admin, '') <> '';

-- ③ العمود الإداري بلا منح لأدوار العميل  → المتوقع: false, false
SELECT has_column_privilege('anon',          'public.offers', 'doc_img_admin', 'SELECT') AS anon_reads,
       has_column_privilege('authenticated', 'public.offers', 'doc_img_admin', 'SELECT') AS auth_reads;

-- ④ التريغر مركّب  → المتوقع: صف واحد
SELECT tgname FROM pg_trigger
WHERE tgrelid = 'public.offers'::regclass AND tgname = 'offers_shield_doc_img';
