-- ============================================================================
-- 2026_08_15 — RATE-002: حارس التقييم يتجاهل الزبون صاحب الموعد
-- ============================================================================
-- بلاغ المالك (اختبار حي): «بالمواعيد عند الموعد المنتهي بالعرض رقم 15 أجيت
-- بدي قيّم التجربة ... وإرسال التقييم فشل».
--
-- التشخيص الحي:
--   • الموعد cd726296 على العرض 15: sts=2 (تمّت) · req_uid=هناء ·
--     own_id=يوزر2 · bkr_id=NULL (لا وسيط — حجز مباشر مع المالك).
--   • `check_rating_valid` تتحقق أن للمُقيِّم موعداً منتهياً على نفس العرض
--     عبر شرطين فقط:
--         a2.bkr_id = NEW.reviewer_uid          ← الوسيط
--         أو صفقة deals مرتبطة بالموعد          ← بائع/مشترٍ
--     ولا تفحص **`req_uid`** إطلاقاً — وهو **الزبون الذي حجز الموعد**!
--   ⇒ أي زبون عادي حجز معاينة وأتمّها **لا يستطيع التقييم أبداً**، وهو
--     الحالة الأكثر شيوعاً في التطبيق كله. الميزة كانت معطّلة عملياً إلا
--     للوسطاء ومن لهم صفقة مسجّلة.
--
-- الإصلاح: إضافة `a2.req_uid = NEW.reviewer_uid` للشرط، وتبسيط المنطق:
--   يكفي أن يكون للمُقيِّم موعد **مكتمل (sts=2)** على عرض **يملكه المستهدف**.
--   لا حاجة للاستعلام المتداخل المزدوج (a و a2 على نفس العرض) — فحص واحد
--   مباشر أوضح وأسرع ويؤدي نفس الغرض بدقة أعلى.
--
-- ⚠️ الحمايات تبقى كما هي: منع تقييم النفس · تقييم واحد لكل طرف (فهرس
--    فريد) · النجوم 1..5 · ولا تقييم بلا موعد/صفقة فعلية.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.check_rating_valid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_has_completed BOOLEAN;
BEGIN
  -- يُسمح بالتقييم إذا تحقّق أحد الثلاثة:
  --  (أ) موعد مكتمل (sts=2) على عرض يملكه المستهدف، والمُقيِّم طرف فيه
  --      إما الزبون الحاجز (req_uid) — 🆕 كان مفقوداً — أو الوسيط (bkr_id).
  --  (ب) موعد مكتمل حجزه المستهدف على عرض يملكه المُقيِّم (الاتجاه المعاكس:
  --      يحق لصاحب العرض أن يقيّم الزبون الذي حضر معه).
  --  (ج) صفقة مكتملة بين الطرفين بأي اتجاه.
  SELECT
    EXISTS (
      SELECT 1
      FROM appointments a
      JOIN offers o ON o.id = a.off_id
      WHERE a.sts = 2
        AND o.usr_id = NEW.target_uid
        AND (a.req_uid = NEW.reviewer_uid OR a.bkr_id = NEW.reviewer_uid)
    )
    OR EXISTS (
      SELECT 1
      FROM appointments a
      JOIN offers o ON o.id = a.off_id
      WHERE a.sts = 2
        AND o.usr_id = NEW.reviewer_uid
        AND (a.req_uid = NEW.target_uid OR a.bkr_id = NEW.target_uid)
    )
    OR EXISTS (
      SELECT 1 FROM deals d
      WHERE d.sts = 1
        AND ((d.sell_uid = NEW.target_uid AND d.buy_uid = NEW.reviewer_uid)
          OR (d.buy_uid  = NEW.target_uid AND d.sell_uid = NEW.reviewer_uid))
    )
  INTO v_has_completed;

  IF NOT v_has_completed THEN
    RAISE EXCEPTION
      'SECURITY: You can only rate users you have completed a deal/appointment with.';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.check_rating_valid() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_rating_valid() FROM anon, authenticated;
