CREATE OR REPLACE FUNCTION public.create_deal_internal(p_admin_uid uuid, p_deal jsonb)
 RETURNS SETOF deals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role   INT;
  v_off_id UUID;
  v_brk_uid UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 5 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- 🔒 BUG-010 (2026-08-14): التحقق من القيم المالية.
  -- كانت الدالة تقبل أي رقم عبر COALESCE(...,0) بلا أي فحص، فأُنشئت حياً
  -- صفقات بسعر -50000 وبعمولة 500% وبسعر صفر — ثلاثتها بيانات مالية فاسدة
  -- تدخل التقارير والإحصاءات. لا سقف ولا أرضية ولا رسالة خطأ.
  IF COALESCE((p_deal->>'fin_prc')::NUMERIC, 0) <= 0 THEN
    RAISE EXCEPTION 'INVALID_DEAL_PRICE';
  END IF;
  IF COALESCE((p_deal->>'fin_prc')::NUMERIC, 0) > 1000000000000 THEN
    RAISE EXCEPTION 'DEAL_PRICE_TOO_LARGE';
  END IF;
  IF COALESCE((p_deal->>'com_pct')::NUMERIC, 0) < 0
     OR COALESCE((p_deal->>'com_pct')::NUMERIC, 0) > 100 THEN
    RAISE EXCEPTION 'INVALID_COMMISSION_PCT';
  END IF;
  IF COALESCE((p_deal->>'com_val')::NUMERIC, 0) < 0 THEN
    RAISE EXCEPTION 'INVALID_COMMISSION_VALUE';
  END IF;

  v_off_id := NULLIF(p_deal->>'off_id', '')::UUID;

  -- 🔗 ربط الصفقة بالوسيط تلقائياً من العرض (2026-07-31)
  -- إذا brk_uid مش محدد يدوياً + العرض إله وسيط → نأخذ brk_id من العرض
  v_brk_uid := NULLIF(p_deal->>'brk_uid', '')::UUID;
  IF v_brk_uid IS NULL AND v_off_id IS NOT NULL THEN
    SELECT brk_id INTO v_brk_uid FROM offers WHERE id = v_off_id AND brk_id IS NOT NULL;
  END IF;

  -- تحويل العرض إلى محجوز
  IF v_off_id IS NOT NULL THEN
    UPDATE offers SET sts = 5, i_pub = 0 WHERE id = v_off_id AND sts = 2;
  END IF;

  RETURN QUERY
  INSERT INTO deals (
    off_id, app_id, sell_uid, buy_uid, brk_uid, fin_prc, cur,
    com_pct, com_val, com_note, form, sts, cmpl_by, i_del, ts_crt, ts_cmpl
  ) VALUES (
    v_off_id,
    NULLIF(p_deal->>'app_id', '')::UUID,
    NULLIF(p_deal->>'sell_uid', '')::UUID,
    NULLIF(p_deal->>'buy_uid', '')::UUID,
    v_brk_uid,
    COALESCE((p_deal->>'fin_prc')::NUMERIC, 0),
    COALESCE((p_deal->>'cur')::INT, 1),
    COALESCE((p_deal->>'com_pct')::NUMERIC, 0),
    COALESCE((p_deal->>'com_val')::NUMERIC, 0),
    NULLIF(p_deal->>'com_note', ''),
    COALESCE(p_deal->'form', '{}'::jsonb),
    COALESCE((p_deal->>'sts')::INT, 0),
    NULL, 0, NOW(), NULL
  ) RETURNING *;
END;
$function$;
CREATE OR REPLACE FUNCTION public.complete_deal_internal(p_admin_uid uuid, p_deal_id uuid, p_commission numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role   INT;
  v_off_id UUID;
  v_is_broker_offer BOOLEAN;
  v_cur_sts INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0;
  IF v_role IS NULL OR v_role < 5 THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  -- 🔒 BUG-011 (2026-08-14): حراسة الإتمام.
  -- ثلاث فجوات مؤكَّدة حياً: (1) لا فحص وجود ⇒ إتمام صفقة غير موجودة كان
  -- يرجع نجاحاً كاذباً؛ (2) لا فحص حالة ⇒ **إتمام مزدوج** لنفس الصفقة نجح
  -- مرتين فتتضاعف النقاط والإحصاءات؛ (3) لا فحص عمولة ⇒ حُفظت com_val=-999.
  SELECT sts, off_id INTO v_cur_sts, v_off_id
  FROM deals WHERE id = p_deal_id AND i_del = 0;

  IF v_cur_sts IS NULL THEN
    RAISE EXCEPTION 'DEAL_NOT_FOUND';
  END IF;
  IF v_cur_sts = 1 THEN
    RAISE EXCEPTION 'DEAL_ALREADY_COMPLETED';
  END IF;
  IF p_commission IS NOT NULL AND p_commission < 0 THEN
    RAISE EXCEPTION 'INVALID_COMMISSION_VALUE';
  END IF;

  -- التحقق إذا كان العرض من وسيط (brk_id غير فارغ)
  IF v_off_id IS NOT NULL THEN
    SELECT (brk_id IS NOT NULL) INTO v_is_broker_offer FROM offers WHERE id = v_off_id;
  ELSE
    v_is_broker_offer := FALSE;
  END IF;

  -- إكمال الصفقة — الوسيط معفى من العمولة تلقائياً
  UPDATE deals
  SET sts = 1,
      cmpl_by = p_admin_uid,
      ts_cmpl = NOW(),
      com_val = CASE WHEN v_is_broker_offer THEN 0 ELSE COALESCE(p_commission, com_val) END,
      com_note = COALESCE(p_note, com_note)
  WHERE id = p_deal_id AND i_del = 0;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DEAL_NOT_FOUND';
  END IF;

  -- تحويل العرض إلى مكتمل
  IF v_off_id IS NOT NULL THEN
    UPDATE offers SET sts = 6, i_pub = 0 WHERE id = v_off_id AND sts IN (2, 5);

    -- إلغاء أي مواعيد متبقية
    UPDATE appointments
    SET sts = 3,
        cnl_rsn = 'تم إكمال صفقة على هذا العرض',
        dt_end = NOW()
    WHERE off_id = v_off_id AND sts IN (0, 1);
  END IF;

  RETURN TRUE;
END;
$function$;
