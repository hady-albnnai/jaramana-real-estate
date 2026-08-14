-- ============================================================================
-- 2026_08_15 — وحدة سعر الباقات (USD) + إلزام صورة للعرض
-- ============================================================================
-- قراران من المالك (2026-08-15):
--   1) 💱 «التناقض بالأسعار ناتج عن عدم تحديد الوحدة — 10 دولار و 25 دولار»
--      ⇒ pkg.<id>.pr بالدولار، والمبلغ المحصَّل = pr × fx.usd_syp بالليرة.
--   2) 🖼️ «إلزام صورة واحدة على الأقل» للعرض — إنشاءً واعتماداً.
--
-- الأثر: SEC-003 كان يرفض كل شراء باقة بـAMOUNT_MISMATCH (expected 10 got
-- 150000) لأنه قارن وحدتين مختلفتين. هذه الهجرة تُصلح المقارنة لا السعر.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_payment_internal(p_user_uid uuid, p_payment jsonb)
 RETURNS SETOF payments
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user        users%ROWTYPE;
  v_pending_cnt INT;
  v_tp          INT;
  v_offer_id    UUID;
  v_weeks       INT;
  v_cfg         JSONB;
  v_expected    NUMERIC;
  v_client_amt  NUMERIC;
  v_pkg         INT;
  v_fx          NUMERIC;   -- 💱 PRICE-UNIT-001: سعر صرف الدولار مقابل الليرة
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user
  FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  IF COALESCE(trim(p_payment->>'proof'), '') = '' OR
     COALESCE(trim(p_payment->>'ref'),   '') = '' THEN
    RAISE EXCEPTION 'MISSING_PAYMENT_PROOF_OR_REFERENCE';
  END IF;

  v_tp := COALESCE((p_payment->>'tp')::INT, 0);

  IF v_tp = 1 THEN
    v_offer_id := NULLIF(p_payment->'meta'->>'offer_id', '')::UUID;
    v_weeks := COALESCE((p_payment->'meta'->>'weeks')::INT, 0);
    IF v_offer_id IS NULL OR v_weeks < 1 OR v_weeks > 4 THEN
      RAISE EXCEPTION 'INVALID_FEATURED_AD_META';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM offers WHERE id = v_offer_id AND usr_id = p_user_uid AND i_del = 0) THEN
      RAISE EXCEPTION 'NOT_OFFER_OWNER';
    END IF;
    SELECT COUNT(*) INTO v_pending_cnt
    FROM payments
    WHERE uid = p_user_uid AND sts = 0 AND tp = 1
      AND meta->>'offer_id' = v_offer_id::TEXT;
    IF v_pending_cnt > 0 THEN
      RAISE EXCEPTION 'PENDING_PAYMENT_EXISTS';
    END IF;
  ELSIF v_tp = 2 THEN
    -- ⚖️ الاستشارة القانونية (أُضيف 2026-08-14 بطلب المالك)
    -- الثغرة السابقة: tp=2 كان يسقط في فرع ELSE الذي يقيّد عدّه بـ tp=0،
    -- فلا يجد شيئاً ويسمح دائماً ⇒ مرّت دفعتان بفارق 43 ثانية (وقع فعلاً).
    -- القاعدة: المنع لنفس النوع فقط (pkg: 0=هاتفية · 1=حضورية)؛ النوع الآخر
    -- مسموح. ودفعة التجديد تُميَّز بـ meta.continue_chat فلا تتعارض مع
    -- استشارة جديدة، ولا يُسمح بتجديدين معلّقين لنفس المحادثة.
    IF NULLIF(p_payment->'meta'->>'continue_chat','') IS NOT NULL THEN
      SELECT COUNT(*) INTO v_pending_cnt
      FROM payments
      WHERE uid = p_user_uid AND sts = 0 AND tp = 2
        AND meta->>'continue_chat' = p_payment->'meta'->>'continue_chat';
      IF v_pending_cnt > 0 THEN
        RAISE EXCEPTION 'PENDING_RENEWAL_PAYMENT_EXISTS';
      END IF;
    ELSE
      SELECT COUNT(*) INTO v_pending_cnt
      FROM payments
      WHERE uid = p_user_uid AND sts = 0 AND tp = 2
        AND COALESCE(pkg, 0) = COALESCE((p_payment->>'pkg')::INT, 0)
        AND NULLIF(meta->>'continue_chat','') IS NULL;
      IF v_pending_cnt > 0 THEN
        RAISE EXCEPTION 'PENDING_CONSULTATION_PAYMENT_EXISTS';
      END IF;
    END IF;
  ELSE
    SELECT COUNT(*) INTO v_pending_cnt
    FROM payments
    WHERE uid = p_user_uid
      AND sts = 0
      AND pkg = COALESCE((p_payment->>'pkg')::INT, 0)
      AND tp  = 0;
    IF v_pending_cnt > 0 THEN
      RAISE EXCEPTION 'PENDING_PAYMENT_EXISTS';
    END IF;
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 🔒 SEC-003 (2026-08-14): احتساب المبلغ **خادمياً** — لا ثقة بالعميل.
  -- ═══════════════════════════════════════════════════════════════════
  -- الثغرة: كان `amt` يُكتب حرفياً كما يرسله العميل
  -- (`COALESCE((p_payment->>'amt')::NUMERIC, 0)`) بلا أي مقارنة بالسعر
  -- المعلن في app_config، لا هنا ولا في approve_payment_final.
  -- ⇒ تطبيق معدَّل يرسل amt=1 لباقة سعرها 10 فيقبله السيرفر، ويرى المدير
  -- «دفعة معلّقة» بمبلغ 1 فيعتمدها ظنّاً أنها صحيحة.
  -- دليل حي من بيانات الإنتاج: نفس الباقة (فضي pr=10) سُجِّلت مرة بـ150000
  -- ومرة بـ1500 — فارق 100 ضعف، وكلاهما قُبل.
  -- القاعدة الآن: السيرفر يحسب السعر من app_config ويكتبه، ومبلغ العميل
  -- يُستخدم للمقارنة فقط؛ أي اختلاف يُرفض صراحةً (لا تصحيح صامت §13).
  SELECT value INTO v_cfg FROM app_config WHERE key = 'main';
  v_client_amt := COALESCE((p_payment->>'amt')::NUMERIC, -1);
  v_pkg := COALESCE((p_payment->>'pkg')::INT, 0);

  IF v_tp = 0 THEN
    -- ═════════════════════════════════════════════════════════════════
    -- 💱 PRICE-UNIT-001 (2026-08-15): وحدة سعر الباقة = **دولار أمريكي**
    -- ═════════════════════════════════════════════════════════════════
    -- قرار المالك الحاسم: «التناقض بالأسعار ناتج عن عدم تحديد الوحدة —
    -- 10 دولار و 25 دولار». أي `pkg.<id>.pr` قيمته بالدولار لا بالليرة.
    -- الواجهة كانت محقّة: `payment_screen.dart` ترسل pr × fx.usd_syp،
    -- والدفعات الحقيقية بالإنتاج 150000 = 10 × 15000 ⇒ مطابقة تامة.
    -- الخلل كان في SEC-003 نفسه: قارن المبلغ المرسل (ليرة) بالسعر الخام
    -- (دولار) ⇒ AMOUNT_MISMATCH كاذب على كل شراء باقة.
    -- الآن: المتوقَّع = pr × سعر الصرف، والدفعة تُسجَّل بالليرة (cur=1).
    -- ⚠️ لا قيمة صرف افتراضية (قاعدة المالك: «لا شيء افتراضي») — غيابها
    --    خطأ صريح يُعلَن لا يُبتلع (§13).
    -- ملاحظة: fmsp / legalPrice / photoPrice كلها **بالليرة مباشرة** —
    --    مؤكَّد من الدفعات الحقيقية (500 / 2000) — فلا تُضرب بالصرف.
    v_expected := (v_cfg->'pkg'->(v_pkg::TEXT)->>'pr')::NUMERIC;
    IF v_expected IS NULL THEN
      RAISE EXCEPTION 'PACKAGE_PRICE_NOT_FOUND';
    END IF;
    v_fx := (v_cfg->'fx'->>'usd_syp')::NUMERIC;
    IF v_fx IS NULL OR v_fx <= 0 THEN
      RAISE EXCEPTION 'FX_RATE_NOT_CONFIGURED';
    END IF;
    v_expected := v_expected * v_fx;
  ELSIF v_tp = 1 THEN
    -- إعلان مميّز: السعر حسب عدد الأسابيع من fmsp.w<n>
    v_expected := (v_cfg->'fmsp'->>('w' || v_weeks::TEXT))::NUMERIC;
    IF v_expected IS NULL THEN
      RAISE EXCEPTION 'FEATURED_PRICE_NOT_FOUND';
    END IF;
  ELSIF v_tp = 2 THEN
    -- استشارة قانونية: تجديد · هاتفية (pkg=0) · حضورية (pkg=1)
    IF NULLIF(p_payment->'meta'->>'continue_chat','') IS NOT NULL THEN
      v_expected := COALESCE((v_cfg->'legalPrice'->>'renew')::NUMERIC, 500);
    ELSIF v_pkg = 1 THEN
      v_expected := COALESCE((v_cfg->'legalPrice'->>'onsite')::NUMERIC, 2000);
    ELSE
      v_expected := COALESCE((v_cfg->'legalPrice'->>'phone')::NUMERIC, 500);
    END IF;
  ELSE
    RAISE EXCEPTION 'UNSUPPORTED_PAYMENT_TYPE';
  END IF;

  IF v_expected < 0 THEN
    RAISE EXCEPTION 'INVALID_CONFIGURED_PRICE';
  END IF;

  -- المقارنة: نرفض الاختلاف بدل تصحيحه بصمت، حتى ينكشف أي خلل في الواجهة
  -- بدل أن يُدفن. (الخدمة المجانية v_expected=0 تتطلب amt=0 أيضاً.)
  IF v_client_amt <> v_expected THEN
    RAISE EXCEPTION 'AMOUNT_MISMATCH: expected % got %', v_expected, v_client_amt;
  END IF;

  RETURN QUERY
  INSERT INTO payments (
    uid, tp, pkg, amt, cur, mtd, channel, proof, ref, meta, sts, appr_by, ts_crt
  ) VALUES (
    p_user_uid,
    v_tp,
    COALESCE((p_payment->>'pkg')::INT,     0),
    v_expected,  -- 🔒 SEC-003: القيمة الخادمية لا قيمة العميل
    COALESCE((p_payment->>'cur')::INT,     1),
    COALESCE((p_payment->>'mtd')::INT,     0),
    COALESCE(p_payment->>'channel', ''),
    COALESCE(p_payment->>'proof',   ''),
    COALESCE(p_payment->>'ref',     ''),
    COALESCE(p_payment->'meta', '{}'::jsonb),
    0,
    NULL,
    NOW()
  ) RETURNING *;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.create_offer_internal(p_user_uid uuid, p_offer jsonb)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_user users%ROWTYPE;
  v_config JSONB;
  v_limit INT;
  v_used INT;
  v_recent_deleted INT;
  v_duplicate BOOLEAN;
  v_effective_pkg INT;
  v_title TEXT;
  v_contact_ph TEXT;
  v_desc TEXT;
  v_exact_loc TEXT;
  v_soc_txt TEXT;
  v_price NUMERIC;
  v_admin_role INT;
  v_added_by UUID := NULL;
  v_is_admin_action BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  -- التحقق من هوية المنفذ الإداري (added_by) وحراسته من التلاعب
  IF p_offer ? 'added_by' AND NULLIF(p_offer->>'added_by', '') IS NOT NULL THEN
    SELECT role INTO v_admin_role FROM users
    WHERE id = (p_offer->>'added_by')::UUID AND sts = 0 AND i_del = 0;

    IF COALESCE(v_admin_role, 0) >= 4 THEN
      v_added_by := (p_offer->>'added_by')::UUID;
      v_is_admin_action := TRUE;
    ELSE
      -- إذا حاول شخص غير إداري تمرير added_by نرفض القيمة ونعتبرها NULL
      v_added_by := NULL;
    END IF;
  ELSE
    -- إذا كان المنفذ هو المستخدم نفسه ولكنه موظف إداري يضيف لنفسه
    IF COALESCE(v_user.role, 0) >= 4 THEN
      v_added_by := p_user_uid;
      v_is_admin_action := TRUE;
    END IF;
  END IF;

  v_title := app_assert_text_len(COALESCE(p_offer->>'ttl', p_offer->>'title'), 'title', 2, 120);
  v_contact_ph := app_assert_phone(p_offer->>'contact_ph');
  v_price := app_assert_price(COALESCE((p_offer->>'prc')::NUMERIC, 0), TRUE);
  v_desc := app_clean_text(p_offer->>'descript', 2000);
  v_exact_loc := app_clean_text(p_offer->>'exact_loc', 300);
  v_soc_txt := app_clean_text(p_offer->>'soc_txt', 500);

  -- الإدارة الداخلية (موظف مكتب فما فوق أو إضافة إدارية لعميل) غير مقيّدة بحصة.
  IF NOT v_is_admin_action THEN
    SELECT value INTO v_config FROM app_config WHERE key = 'main';

    v_effective_pkg := CASE
      WHEN COALESCE(v_user.b_pkg, 0) = 0 THEN 0
      WHEN v_user.pkg_grace IS NOT NULL AND v_user.pkg_grace > NOW() THEN v_user.b_pkg
      WHEN v_user.pkg_end IS NOT NULL AND v_user.pkg_end > NOW() THEN v_user.b_pkg
      ELSE 0
    END;

    v_limit := COALESCE((v_config->'pkg'->(v_effective_pkg::TEXT)->>'o')::INT,
      CASE WHEN COALESCE(v_user.role, 0) = 1 THEN 5 ELSE 1 END)
      -- التجميع (2026-07-27): السقف الإضافي من الباقات المكدّسة يُحتسب ما دامت الباقة فعالة
      + CASE WHEN v_effective_pkg > 0 THEN COALESCE(v_user.pkg_xoff, 0) ELSE 0 END;

    SELECT COUNT(*) INTO v_used
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 0
      AND sts IN (0, 1, 2, 5);

    SELECT COUNT(*) INTO v_recent_deleted
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 1
      AND ts_crt >= NOW() - INTERVAL '24 hours';

    v_used := COALESCE(v_used, 0) + COALESCE(v_recent_deleted, 0);
    IF v_used >= v_limit THEN
      RAISE EXCEPTION 'QUOTA_EXCEEDED';
    END IF;
  END IF;

  SELECT check_offer_duplicate(
    v_title,
    v_price,
    COALESCE(p_offer->'loc', '{"r":0,"d":""}'::jsonb),
    p_user_uid
  ) INTO v_duplicate;

  IF v_duplicate THEN
    RAISE EXCEPTION 'DUPLICATE_OFFER';
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- 🖼️ IMG-001 (2026-08-15): صورة واحدة على الأقل إلزامية
  -- ═══════════════════════════════════════════════════════════════════
  -- الفجوة: لا فحص إطلاقاً ⇒ 4 عروض منشورة بلا أي صورة بالإنتاج. الواجهة
  -- تعرض بديلاً فلا تنهار، لكن عرضاً بلا صورة = بلاغ وهمي بصرياً وتجربة
  -- سيئة، وقرار المالك (2026-08-15): «إلزام صورة واحدة على الأقل».
  -- الفحص هنا (طبقة الإنشاء) + في admin_review_offer_internal (طبقة
  -- الاعتماد) — دفاع بطبقتين لأن العرض قد يُعدَّل بين الإنشاء والمراجعة.
  -- استثناء واحد مشروع: **طلب التصوير**. في هذا المسار المستخدم يطلب من
  -- المكتب أن يصوّر عقاره، فالعرض يُنشأ عمداً بلا صور والمصوّر يضيفها لاحقاً.
  -- (مؤكَّد حياً: العرضان 10 و15 بلا صور مصدرهما photography_tasks.)
  -- ⚠️ الراية يرسلها العميل فهي غير موثوقة نظرياً، لكن الالتفاف عليها لا
  -- يفيد المهاجم: العرض يبقى sts=1 (مراجعة) وبوابة الاعتماد
  -- `admin_review_offer_internal` تفرض الصورة **بلا أي استثناء** ⇒ لا شيء
  -- ينشر للعموم بلا صورة مهما فعل العميل.
  IF COALESCE((p_offer->>'photo_req')::INT, 0) <> 1
     AND COALESCE(jsonb_array_length(NULLIF(p_offer->'imgs', 'null'::jsonb)), 0) < 1 THEN
    RAISE EXCEPTION 'OFFER_IMAGE_REQUIRED';
  END IF;

  RETURN QUERY
  INSERT INTO offers (
    usr_id, brk_id, brk_pct, typ, trx, cat, sub, contact_ph,
    ttl, prc, cur, loc, descript, imgs, vdo, doc_tp, doc_img,
    exact_loc, specs, com, sts, rsn, vws, fvs, i_pub, i_soc,
    soc_pub, soc_txt, i_dup, dup_of, avl, i_del, ts_crt, ts_pub, ts_end, ts_ren, added_by
  ) VALUES (
    p_user_uid,
    COALESCE(NULLIF(p_offer->>'brk_id', '')::UUID, CASE WHEN v_user.role = 1 AND v_user.brk = 1 THEN p_user_uid ELSE NULL END),
    COALESCE((p_offer->>'brk_pct')::NUMERIC, 0),
    COALESCE((p_offer->>'typ')::INT, 0),
    COALESCE((p_offer->>'trx')::INT, 0),
    COALESCE((p_offer->>'cat')::INT, 0),
    COALESCE((p_offer->>'sub')::INT, 0),
    v_contact_ph,
    v_title,
    v_price,
    COALESCE((p_offer->>'cur')::INT, 0),
    COALESCE(p_offer->'loc', '{}'::jsonb),
    v_desc,
    COALESCE(p_offer->'imgs', '[]'::jsonb),
    app_clean_text(p_offer->>'vdo', 500),
    COALESCE((p_offer->>'doc_tp')::INT, 0),
    app_clean_text(p_offer->>'doc_img', 500),
    v_exact_loc,
    COALESCE(p_offer->'specs', '{}'::jsonb),
    COALESCE((p_offer->>'com')::NUMERIC, 0),
    1,
    '',
    0,
    0,
    0,
    COALESCE((p_offer->>'i_soc')::INT, 0),
    0,
    v_soc_txt,
    0,
    NULL,
    COALESCE(p_offer->'avl', '{}'::jsonb),
    0,
    NOW(),
    NULL,
    NULL,
    NULL,
    v_added_by
  ) RETURNING *;
END;
$function$
;

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

    UPDATE offers SET sts = 2, i_pub = 1, ts_pub = NOW() 
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

-- ============================================================================
-- §7 رباعي التحصين — يُعاد بعد كل CREATE OR REPLACE
-- ============================================================================
REVOKE ALL ON FUNCTION public.create_payment_internal(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_payment_internal(uuid, jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_payment_internal(uuid, jsonb) TO service_role;

-- ============================================================================
-- 🖼️ IMG-001 — معالجة العروض المنشورة بلا صور (4 عروض بالإنتاج)
-- ============================================================================
-- لا نحذفها ولا نخفيها بصمت: نُعيدها لقائمة المراجعة (sts=1, i_pub=0) مع
-- سبب صريح وإشعار لصاحبها يطلب إضافة صورة. هكذا لا يضيع عرض ولا يبقى
-- منشور مخالف للقاعدة الجديدة.
WITH tgt AS (
  SELECT id, usr_id, ttl FROM offers
  WHERE i_del = 0 AND sts = 2
    AND COALESCE(jsonb_array_length(NULLIF(imgs, 'null'::jsonb)), 0) < 1
), upd AS (
  UPDATE offers o
  SET sts = 1, i_pub = 0,
      rsn = 'مطلوب إضافة صورة واحدة على الأقل قبل إعادة النشر'
  FROM tgt WHERE o.id = tgt.id
  RETURNING o.id
)
INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
SELECT tgt.usr_id, 0,
       '🖼️ العرض الخاص بك يحتاج صورة',
       'العرض الخاص بك «' || COALESCE(tgt.ttl, '') || '» أُعيد لقائمة المراجعة لأنه بلا صور. أضِف صورة واحدة على الأقل ليُعاد نشره.',
       tgt.id::TEXT, 'offer_needs_image', 0, 0, NOW()
FROM tgt;
