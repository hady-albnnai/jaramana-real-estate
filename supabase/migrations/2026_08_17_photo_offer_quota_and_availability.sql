-- Photo-request technical offers do not consume normal offer quota.
ALTER TABLE public.offers ADD COLUMN IF NOT EXISTS photo_req integer NOT NULL DEFAULT 0;
DO $ddl$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='offers_photo_req_check') THEN
  ALTER TABLE public.offers ADD CONSTRAINT offers_photo_req_check CHECK(photo_req IN(0,1));
 END IF;
END $ddl$;
UPDATE public.offers o SET photo_req=1
WHERE EXISTS(SELECT 1 FROM public.photography_tasks p WHERE p.off_id=o.id);

CREATE OR REPLACE FUNCTION public.check_offer_duplicate(p_ttl text,p_prc numeric,p_loc jsonb,p_usr_id uuid)
RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_dup boolean;
BEGIN
 SELECT EXISTS(SELECT 1 FROM public.offers
  WHERE lower(regexp_replace(ttl,'\s+',' ','g'))=lower(regexp_replace(p_ttl,'\s+',' ','g'))
   AND prc=p_prc AND i_del=0 AND COALESCE(photo_req,0)=0) INTO v_dup;
 RETURN v_dup;
END;
$function$;

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
  v_is_photo_request BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT * INTO v_user FROM users WHERE id = p_user_uid AND i_del = 0 AND sts = 0;
  IF v_user.id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_ACTIVE_OR_NOT_FOUND';
  END IF;

  v_is_photo_request := COALESCE((p_offer->>'photo_req')::INT,0)=1;

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
      AND COALESCE(photo_req,0)=0
      AND sts IN (0, 1, 2, 5);

    SELECT COUNT(*) INTO v_recent_deleted
    FROM offers
    WHERE usr_id = p_user_uid
      AND i_del = 1
      AND COALESCE(photo_req,0)=0
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
    soc_pub, soc_txt, i_dup, dup_of, avl, i_del, ts_crt, ts_pub, ts_end, ts_ren, added_by, photo_req
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
    v_added_by,
    CASE WHEN v_is_photo_request THEN 1 ELSE 0 END
  ) RETURNING *;
END;
$function$
;

REVOKE ALL ON FUNCTION public.check_offer_duplicate(text,numeric,jsonb,uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.check_offer_duplicate(text,numeric,jsonb,uuid) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.check_offer_duplicate(text,numeric,jsonb,uuid) TO service_role;
REVOKE ALL ON FUNCTION public.create_offer_internal(uuid,jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_offer_internal(uuid,jsonb) FROM anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_offer_internal(uuid,jsonb) TO service_role;
