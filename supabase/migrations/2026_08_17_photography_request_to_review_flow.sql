-- ============================================================================
-- 2026-08-17 — دورة طلب التصوير: مسودة مخفية → عرض كامل للمراجعة
--
-- طلب التصوير يحفظ كل بيانات العرض في offers كمسودة تقنية photo_req=1/sts=0.
-- لا يصل إلى مراجعة العروض ولا يطلق إشعار العرض العام قبل صور المصور.
-- عند تسليم المصور، تدمج الصور ذرياً وتنتقل المسودة إلى sts=1.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_offer_internal(p_user_uid uuid, p_offer jsonb)
 RETURNS SETOF offers
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
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
  IF NOT v_is_admin_action AND NOT v_is_photo_request THEN
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
    CASE WHEN v_is_photo_request THEN 0 ELSE 1 END,
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

-- إنشاء العرض التقني والمهمة والإشعار الإداري ضمن معاملة واحدة؛ لا تبقى
-- مسودة يتيمة إذا انقطع الاتصال بين إنشاء العرض وإنشاء المهمة.
CREATE OR REPLACE FUNCTION public.create_photography_request_internal(
  p_user_uid uuid,
  p_offer jsonb
)
RETURNS SETOF public.offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_offer public.offers%ROWTYPE;
  v_task_id uuid;
  v_staff record;
BEGIN
  SELECT * INTO v_offer
  FROM public.create_offer_internal(
    p_user_uid,
    COALESCE(p_offer, '{}'::jsonb) || jsonb_build_object('photo_req', 1)
  );
  IF v_offer.id IS NULL THEN RAISE EXCEPTION 'OFFER_CREATE_FAILED'; END IF;

  INSERT INTO public.photography_tasks(off_id, requested_by, ttl, notes, loc, sts)
  VALUES(v_offer.id, p_user_uid, v_offer.ttl, '', COALESCE(v_offer.loc, '{}'::jsonb), 0)
  RETURNING id INTO v_task_id;

  FOR v_staff IN
    SELECT id FROM public.users
    WHERE role BETWEEN 3 AND 6 AND sts = 0 AND i_del = 0
  LOOP
    PERFORM public.notify_user(
      v_staff.id,
      1,
      '📸 طلب تصوير جديد لعرض',
      'طلب تصوير للعرض: ' || COALESCE(v_offer.ttl, '') || ' — يرجى إسناد مصوّر.',
      v_task_id::text,
      'photography_request_new'
    );
  END LOOP;

  RETURN NEXT v_offer;
END;
$function$;

-- لا تظهر المسودة التقنية ضمن «عروضي» قبل اكتمال التصوير.
CREATE OR REPLACE FUNCTION public.get_user_offers_internal(p_user_uid uuid)
RETURNS SETOF public.offers
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  RETURN QUERY
  SELECT * FROM public.offers
  WHERE usr_id = p_user_uid
    AND i_del = 0
    AND NOT (COALESCE(photo_req, 0) = 1 AND sts = 0)
  ORDER BY ts_crt DESC;
END;
$function$;

-- تسليم المصور يغلق خطوة التصوير ويفتح مراجعة العرض العادية في عملية ذرية واحدة.
CREATE OR REPLACE FUNCTION public.submit_photography_task_internal(
  p_photographer_uid uuid,
  p_task_id uuid,
  p_media jsonb,
  p_photographer_note text DEFAULT ''::text,
  p_replace boolean DEFAULT false
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_old       jsonb;
  v_final     jsonb;
  v_off_id    uuid;
  v_photo_req integer;
  v_offer_sts integer;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_photographer_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  IF jsonb_typeof(COALESCE(p_media, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_MEDIA_ARRAY';
  END IF;
  IF jsonb_array_length(COALESCE(p_media, '[]'::jsonb)) = 0 THEN
    RAISE EXCEPTION 'MEDIA_REQUIRED';
  END IF;

  SELECT COALESCE(media, '[]'::jsonb), off_id
    INTO v_old, v_off_id
  FROM public.photography_tasks
  WHERE id = p_task_id
    AND photographer_id = p_photographer_uid
    AND sts IN (0, 1, 4)
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TASK_NOT_FOUND_OR_NOT_ALLOWED';
  END IF;

  IF COALESCE(p_replace, false) THEN
    v_final := COALESCE(p_media, '[]'::jsonb);
  ELSE
    SELECT COALESCE(jsonb_agg(u.val ORDER BY u.ord), '[]'::jsonb)
      INTO v_final
    FROM (
      SELECT DISTINCT ON (val) val, ord
      FROM (
        SELECT value AS val, ordinality AS ord
          FROM jsonb_array_elements(v_old) WITH ORDINALITY
        UNION ALL
        SELECT value AS val, ordinality + jsonb_array_length(v_old) AS ord
          FROM jsonb_array_elements(COALESCE(p_media, '[]'::jsonb)) WITH ORDINALITY
      ) merged
      ORDER BY val, ord
    ) u;
  END IF;

  UPDATE public.photography_tasks
     SET media = v_final,
         photographer_note = COALESCE(p_photographer_note, ''),
         sts = 2,
         ts_submit = NOW(),
         ts_upd = NOW()
   WHERE id = p_task_id;

  IF v_off_id IS NOT NULL THEN
    SELECT COALESCE(photo_req, 0), sts
      INTO v_photo_req, v_offer_sts
    FROM public.offers
    WHERE id = v_off_id AND i_del = 0
    FOR UPDATE;

    -- حصراً مسودة طلب المستخدم؛ مهام تصوير العروض المنشورة تبقى بمسار الربط القديم.
    IF FOUND AND v_photo_req = 1 AND v_offer_sts = 0 THEN
      UPDATE public.offers
         SET imgs = v_final,
             sts = 1,
             rsn = ''
       WHERE id = v_off_id;
    END IF;
  END IF;

  RETURN TRUE;
END;
$function$;

-- إحصاء عروض المستخدم لا يحسب مسودة طلب التصوير قبل اكتمالها.
CREATE OR REPLACE FUNCTION public.update_user_stats_on_offer()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_count integer;
  v_uid uuid;
BEGIN
  v_uid := CASE WHEN TG_OP = 'DELETE' THEN OLD.usr_id ELSE NEW.usr_id END;
  IF v_uid IS NULL THEN
    IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
  END IF;
  SELECT COUNT(*) INTO v_count
  FROM public.offers
  WHERE usr_id = v_uid
    AND i_del = 0
    AND NOT (COALESCE(photo_req, 0) = 1 AND sts = 0);
  UPDATE public.users
     SET stats = jsonb_set(COALESCE(stats, '{}'::jsonb), '{off}', to_jsonb(v_count)),
         ts_upd = NOW()
   WHERE id = v_uid;
  IF TG_OP = 'DELETE' THEN RETURN OLD; ELSE RETURN NEW; END IF;
END;
$function$;

-- الطلب الملغى قبل بدء التصوير لا يبقى كعرض تقني قابل للمراجعة.
UPDATE public.offers o
   SET i_del = 1
 WHERE COALESCE(o.photo_req, 0) = 1
   AND o.i_del = 0
   AND COALESCE(jsonb_array_length(NULLIF(o.imgs, 'null'::jsonb)), 0) = 0
   AND EXISTS (
     SELECT 1 FROM public.photography_tasks t
     WHERE t.off_id = o.id AND t.sts = 5
   );

-- تحويل الطلبات النشطة الموجودة قبل الإصلاح إلى مسودات، وتنظيف إشعار العرض المبكر فقط.
UPDATE public.offers o
   SET sts = 0
 WHERE COALESCE(o.photo_req, 0) = 1
   AND o.sts = 1
   AND COALESCE(jsonb_array_length(NULLIF(o.imgs, 'null'::jsonb)), 0) = 0
   AND EXISTS (
     SELECT 1 FROM public.photography_tasks t
     WHERE t.off_id = o.id AND t.sts IN (0, 1)
   );

DELETE FROM public.notifications n
USING public.offers o
WHERE n.ref_id = o.id::text
  AND n.act = 'offer'
  AND COALESCE(o.photo_req, 0) = 1
  AND (o.sts = 0 OR o.i_del = 1);

-- إعادة احتساب العداد للمستخدمين المتأثرين بالمسودات التقنية.
UPDATE public.users u
SET stats = jsonb_set(
      COALESCE(u.stats, '{}'::jsonb),
      '{off}',
      to_jsonb((SELECT COUNT(*) FROM public.offers o
                WHERE o.usr_id = u.id AND o.i_del = 0
                  AND NOT (COALESCE(o.photo_req, 0) = 1 AND o.sts = 0)))
    ),
    ts_upd = NOW()
WHERE EXISTS (SELECT 1 FROM public.offers o WHERE o.usr_id = u.id AND COALESCE(o.photo_req, 0) = 1);

REVOKE ALL ON FUNCTION public.create_offer_internal(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_offer_internal(uuid, jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_offer_internal(uuid, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.create_photography_request_internal(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.create_photography_request_internal(uuid, jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_photography_request_internal(uuid, jsonb) TO service_role;
REVOKE ALL ON FUNCTION public.get_user_offers_internal(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_user_offers_internal(uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_offers_internal(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.submit_photography_task_internal(uuid, uuid, jsonb, text, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.submit_photography_task_internal(uuid, uuid, jsonb, text, boolean) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_photography_task_internal(uuid, uuid, jsonb, text, boolean) TO service_role;
REVOKE ALL ON FUNCTION public.update_user_stats_on_offer() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.update_user_stats_on_offer() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_stats_on_offer() TO service_role;
