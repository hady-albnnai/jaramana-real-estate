-- ============================================================================
-- 2026_08_15 — OFFER-TTL-001: ضبط مدة العرض (30 يوماً) عند النشر
-- ============================================================================
-- بلاغ المالك: «العدّاد لعروضي المنشورة غير ظاهر» و«العرض 14 يمكن تجديده
-- مع أن المفروض لا يُجدَّد إلا قبل انتهائه بيومين».
-- السبب الجذري: create_offer_internal تُدرج ts_end = NULL، وبوابة الاعتماد
-- كانت تضبط ts_pub فقط ⇒ العرض يُنشر بلا تاريخ انتهاء إطلاقاً.
-- القاعدة (قرار المالك): أي عرض مدته تبدأ بـ30 يوماً وتتناقص، وتُحسب من
-- النشر الفعلي لا الإنشاء (المراجعة قد تستغرق أياماً).
-- ملاحظة: مُستخرَج من القاعدة الحية بعد تطبيقه (أرشفة).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.admin_review_offer_internal(p_admin_uid uuid, p_offer_id uuid, p_approve boolean, p_reject_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE 
  v_role INT;
  v_owner_uid UUID;
  v_ttl TEXT;
  v_cur_sts INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN 
    RAISE EXCEPTION 'AUTH_MISMATCH'; 
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 4 THEN 
    RAISE EXCEPTION 'NOT_AUTHORIZED'; 
  END IF;

  -- جلب مالك العرض وعنوانه للإشعار
  SELECT usr_id, ttl, sts INTO v_owner_uid, v_ttl, v_cur_sts
  FROM offers WHERE id = p_offer_id AND i_del = 0;

  -- 🔒 BUG-016 (2026-08-14): لم يكن هناك أي فحص وجود ⇒ مراجعة عرض **غير
  -- موجود إطلاقاً** كانت تُرجع success:true (لأن UPDATE بلا صفوف لا يفشل)
  -- ويظن المدير أنه اعتمد شيئاً. أُكِّد حياً بـuuid أصفار.
  IF v_owner_uid IS NULL AND NOT EXISTS (
    SELECT 1 FROM offers WHERE id = p_offer_id AND i_del = 0
  ) THEN
    RAISE EXCEPTION 'OFFER_NOT_FOUND';
  END IF;

  -- منع إعادة اعتماد عرض منشور سلفاً (يعيد النشر ويكرّر الإشعار)
  IF p_approve AND v_cur_sts = 2 THEN
    RAISE EXCEPTION 'OFFER_ALREADY_PUBLISHED';
  END IF;

  IF p_approve THEN
    -- 🖼️ IMG-001 (2026-08-15): لا اعتماد لعرض بلا صورة
    -- طبقة ثانية بعد create_offer_internal: العرض قد يُعدَّل بعد الإنشاء،
    -- وقد تكون هناك عروض قديمة بلا صور سبقت القاعدة. الاعتماد = نشر
    -- للعموم، فهو آخر بوابة يجب أن تحرس الجودة. الرسالة صريحة (§13).
    IF COALESCE(jsonb_array_length(NULLIF(
         (SELECT imgs FROM offers WHERE id = p_offer_id), 'null'::jsonb)), 0) < 1 THEN
      RAISE EXCEPTION 'OFFER_IMAGE_REQUIRED';
    END IF;

    -- ═══════════════════════════════════════════════════════════════
    -- 📅 OFFER-TTL-001 (2026-08-15): ضبط مدة العرض عند النشر
    -- ═══════════════════════════════════════════════════════════════
    -- بلاغ المالك: «العدّاد بالنسبة لعروضي المنشورة غير ظاهر»، و«العرض
    -- 14 يمكن تجديده مع أن المفروض لا يُجدَّد إلا قبل انتهائه بيومين».
    --
    -- السبب الجذري: `create_offer_internal` تُدرج ts_pub وts_end = NULL،
    -- وهذه البوابة كانت تضبط ts_pub **فقط** ⇒ العرض يُنشر **بلا تاريخ
    -- انتهاء إطلاقاً** (مؤكَّد حياً: ts_end فارغ للعرضين 14 و15).
    -- الأثر المتسلسل: لا عدّاد أيام · daysUntilExpiration يقع على قيمة
    -- افتراضية ⇒ حارس «التجديد قبل يومين» لا يعمل · العرض لا ينتهي أبداً.
    --
    -- القاعدة (قرار المالك): «أي عرض مدته تبدأ بـ30 يوماً وتتناقص».
    -- تُحسب من لحظة النشر الفعلي لا الإنشاء — فالمراجعة قد تستغرق أياماً
    -- ولا يعدل أن تُخصم من مدة المُعلِن.
    -- ⚠️ عند إعادة النشر بعد رفض/تعديل: تُحسب مدة جديدة كاملة (ts_pub
    --    يُحدَّث أيضاً)، وهذا مقصود لأن العرض يعود للجمهور من جديد.
    UPDATE offers
       SET sts    = 2,
           i_pub  = 1,
           ts_pub = NOW(),
           ts_end = NOW() + INTERVAL '30 days'
     WHERE id = p_offer_id AND i_del = 0;
    
    -- 🔔 إشعار صاحب العرض بالاعتماد (2026-07-31)
    IF v_owner_uid IS NOT NULL THEN
      INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
      VALUES (
        v_owner_uid, 1,
        '✅ تم اعتماد العرض الخاص بك',
        'العرض الخاص بك «' || COALESCE(v_ttl, '') || '» تم اعتماده ونشره — يمكنك مشاهدته الآن في الصفحة الرئيسية.',
        p_offer_id::TEXT, 'offer_approved', 0, 0, NOW()
      );
      PERFORM public.send_push_notification(
        v_owner_uid,
        '✅ تم اعتماد العرض الخاص بك',
        COALESCE(v_ttl, 'عرض جديد'),
        jsonb_build_object('act', 'offer_approved', 'ref_id', p_offer_id::TEXT)
      );
    END IF;
    
    PERFORM public.log_admin_action(p_admin_uid, 101, 'اعتماد العرض العقاري ونشره للعموم', p_offer_id::TEXT, 'offers');
  ELSE
    IF COALESCE(trim(p_reject_reason), '') = '' THEN
      RAISE EXCEPTION 'REJECTION_REASON_REQUIRED';
    END IF;
    UPDATE offers SET sts = 3, rsn = trim(p_reject_reason), i_pub = 0 
    WHERE id = p_offer_id AND i_del = 0;
    
    -- 🔔 إشعار صاحب العرض بالرفض + السبب (2026-07-31)
    IF v_owner_uid IS NOT NULL THEN
      INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
      VALUES (
        v_owner_uid, 1,
        '❌ تم رفض العرض الخاص بك',
        'العرض الخاص بك «' || COALESCE(v_ttl, '') || '» تم رفضه — السبب: ' || trim(p_reject_reason),
        p_offer_id::TEXT, 'offer_rejected', 0, 0, NOW()
      );
      PERFORM public.send_push_notification(
        v_owner_uid,
        '❌ تم رفض العرض الخاص بك',
        COALESCE(v_ttl, '') || ' — ' || trim(p_reject_reason),
        jsonb_build_object('act', 'offer_rejected', 'ref_id', p_offer_id::TEXT)
      );
    END IF;
    
    PERFORM public.log_admin_action(p_admin_uid, 102, 'رفض العرض العقاري: ' || trim(p_reject_reason), p_offer_id::TEXT, 'offers');
  END IF;
  RETURN FOUND;
END;
$function$
;

REVOKE ALL ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) TO service_role;

-- ردم العروض المنشورة بلا ts_end (نُفِّذ حياً: 4 عروض)
UPDATE offers
   SET ts_end = COALESCE(ts_pub, ts_crt) + INTERVAL '30 days'
 WHERE i_del = 0 AND sts = 2 AND ts_end IS NULL;
