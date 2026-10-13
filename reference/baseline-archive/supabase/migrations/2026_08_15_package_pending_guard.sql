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
    -- ═══════════════════════════════════════════════════════════════
    -- 🔒 PKG-001 (2026-08-15): دفعة باقة معلّقة تمنع **أي** طلب باقة
    -- ═══════════════════════════════════════════════════════════════
    -- بلاغ المالك: «لازم عند الباقة الفضية ما يخليني أشترك فيها مرة
    -- ثانية ويظهر عندها أن طلبك قيد المعالجة».
    -- الثغرة: الشرط كان مقيَّداً بـ`pkg = نفس الباقة` ⇒ دفعة فضية
    -- معلّقة **لا تمنع** طلب ذهبية (ولا العكس)، فيتراكم على المستخدم
    -- طلبان ماليان معلّقان لنفس الغرض ويدفع مرتين.
    -- القاعدة الصحيحة: الباقات **غرض واحد** — طلب واحد معلّق فقط مهما
    -- كان مستواه، حتى تبتّ الإدارة. (يختلف عن الاستشارات حيث الهاتفية
    -- والحضورية خدمتان مستقلتان بقرار المالك.)
    SELECT COUNT(*) INTO v_pending_cnt
    FROM payments
    WHERE uid = p_user_uid
      AND sts = 0
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
