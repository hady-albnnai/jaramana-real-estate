CREATE OR REPLACE FUNCTION public.get_my_tasks(p_user_uid uuid DEFAULT NULL::uuid)
 RETURNS TABLE(appointment_id uuid, off_id uuid, offer_number text, display_title text, task_type text, client_name text, client_phone text, appointment_date timestamp with time zone, location jsonb, description text, price numeric, offer_cur integer, outcome text, sts integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_uid UUID;
BEGIN
  v_uid := COALESCE(p_user_uid, auth.uid());
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  RETURN QUERY
  SELECT
    a.id            AS appointment_id,
    a.off_id,
    COALESCE(o.ttl, '')  AS offer_number,
    COALESCE(o.ttl, '')  AS display_title,
    CASE WHEN o.typ = 0 THEN 'property' ELSE 'car' END AS task_type,
    ''::TEXT         AS client_name,
    ''::TEXT         AS client_phone,
    a.dt             AS appointment_date,
    COALESCE(o.loc, '{}'::jsonb) AS location,
    COALESCE(o.descript, '') AS description,
    COALESCE(o.prc, 0)  AS price,
    COALESCE(o.cur, 0)  AS offer_cur,
    a.outcome,
    a.sts
  FROM appointments a
  JOIN offers o ON o.id = a.off_id
  WHERE a.supervisor_uid = v_uid
    AND a.sts IN (0, 1)
    AND a.outcome IS NULL
    -- 🔒 BUG-026 (2026-08-14): كان الشرط `a.dt::date = CURRENT_DATE` — أي
    -- «مهام اليوم فقط». النتيجة: موعد نشط (sts 0/1) بلا نتيجة ومضى تاريخه
    -- **يختفي من شاشات المنفّذ الثلاث كلها**: get_my_tasks تشترط اليوم،
    -- get_postponed_tasks تشترط المستقبل (> CURRENT_DATE)، و
    -- get_completed_tasks تشترط outcome. أُكِّد حياً: موعد بتاريخ أمس أعطى
    -- 0/0/0 — فلا يستطيع المنفّذ تسجيل نتيجته ولا إغلاقه، ويبقى معلّقاً أبداً.
    -- الآن: اليوم **وما فاته** — المتأخر يظهر أولاً ليُعالَج.
    AND a.dt::date <= CURRENT_DATE
  ORDER BY a.dt ASC;
END;
$function$;
CREATE OR REPLACE FUNCTION public.request_completion_by_appointment(p_user_uid uuid, p_appointment_id uuid, p_notes text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE v_appt RECORD; v_existing INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  SELECT * INTO v_appt FROM appointments WHERE id = p_appointment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  IF v_appt.supervisor_uid <> p_user_uid THEN RAISE EXCEPTION 'NOT_YOUR_TASK'; END IF;
  SELECT COUNT(*) INTO v_existing FROM completion_requests WHERE app_id = p_appointment_id AND decision = 'pending';
  IF v_existing > 0 THEN RAISE EXCEPTION 'يوجد طلب إتمام معلق مسبقاً'; END IF;

  UPDATE appointments SET outcome = 'accept', executor_notes = COALESCE(p_notes, ''),
    completion_date = NOW(), sts = CASE WHEN sts IN (0, 1) THEN 2 ELSE sts END WHERE id = p_appointment_id;
  INSERT INTO completion_requests (app_id, req_by, notes) VALUES (p_appointment_id, p_user_uid, COALESCE(p_notes, ''));

  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, ts_crt)
    -- 🔒 BUG-027 (2026-08-14): كان النوع 20 بينما قيد notifications_tp_check
  -- يسمح بـ0..5 فقط ⇒ **كل** طلب إتمام يفشل بخطأ قيد قاعدة، والمعاملة
  -- المنجزة ميدانياً لا تصل الإدارة إطلاقاً. أُكِّد حياً (جدول
  -- completion_requests فارغ رغم 14 موعداً). النوع الصحيح 2 = تشغيلي
  -- (مواعيد ومهام) وفق البيانات الحية.
  SELECT u.id, 2, 'طلب إتمام معاملة', 'المنفذ أرسل طلب إتمام لموعد — يرجى المراجعة',
      p_appointment_id, NOW() FROM users u WHERE u.role >= 4 AND u.sts = 0 AND u.i_del = 0;
  RETURN TRUE;
END; $function$;
CREATE OR REPLACE FUNCTION public.process_completion_request(p_admin_uid uuid, p_request_id uuid, p_decision text, p_office_notes text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT;
  v_req RECORD;
  v_appt RECORD;
  v_off_id UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN RAISE EXCEPTION 'AUTH_MISMATCH'; END IF;
  IF p_decision NOT IN ('approved', 'rejected') THEN RAISE EXCEPTION 'INVALID_DECISION'; END IF;

  SELECT role INTO v_role FROM public.users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 4 THEN RAISE EXCEPTION 'NOT_AUTHORIZED'; END IF;

  SELECT * INTO v_req FROM public.completion_requests WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'REQUEST_NOT_FOUND'; END IF;
  IF v_req.decision <> 'pending' THEN RAISE EXCEPTION 'REQUEST_ALREADY_PROCESSED'; END IF;

  SELECT * INTO v_appt FROM public.appointments WHERE id = v_req.app_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'APPOINTMENT_NOT_FOUND'; END IF;
  v_off_id := v_appt.off_id;

  UPDATE public.completion_requests
  SET decision = p_decision,
      decided_by = p_admin_uid,
      office_notes = COALESCE(p_office_notes, ''),
      ts_decided = NOW()
  WHERE id = p_request_id;

  IF p_decision = 'approved' THEN
    UPDATE public.appointments SET sts = 2 WHERE id = v_req.app_id AND sts <> 2;
    UPDATE public.offers SET sts = 5, i_pub = 0 WHERE id = v_off_id AND sts IN (2, 5);

    UPDATE public.appointments
    SET sts = 3, cnl_rsn = 'تم إتمام معاملة على هذا العرض', dt_end = NOW()
    WHERE off_id = v_off_id AND id <> v_req.app_id AND sts IN (0, 1);

    IF v_appt.req_id IS NOT NULL THEN
      UPDATE public.requests
      SET sts = 2,
          closed_at = NOW(),
          closed_by = p_admin_uid,
          closed_reason = 'fulfilled_by_offer_completion',
          closed_note = COALESCE(p_office_notes, ''),
          closed_offer_id = v_off_id,
          closed_appointment_id = v_req.app_id,
          closed_completion_request_id = p_request_id,
          rmnd_ren = 0
      WHERE id = v_appt.req_id
        AND i_del = 0
        AND sts IN (0, 1, 4);

      PERFORM public.notify_user(
        v_appt.req_uid, 1,
        'تمت تلبية طلبك',
        'تم إغلاق طلبك بعد إتمام معاملة مرتبطة به عبر المكتب.',
        v_appt.req_id::TEXT, 'request'
      );
    END IF;

    INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, ts_crt)
      SELECT a.req_uid, 0, 'تم إلغاء موعدك', 'تم إلغاء موعدك لأن العرض اكتمل بمعاملة أخرى.', a.id::TEXT, NOW()
      FROM public.appointments a
      WHERE a.off_id = v_off_id AND a.id <> v_req.app_id AND a.sts = 3
        AND a.cnl_rsn = 'تم إتمام معاملة على هذا العرض';

  ELSIF p_decision = 'rejected' THEN
    UPDATE public.appointments SET sts = 4, outcome = 'reject' WHERE id = v_req.app_id;
    UPDATE public.offers SET sts = 2, i_pub = 1 WHERE id = v_off_id AND sts = 5;
  END IF;

  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, ts_crt) VALUES (
    -- 🔒 BUG-027 (2026-08-14): tp=20 خارج قيد notifications_tp_check (0..5)
    -- ⇒ **معالجة طلب الإتمام تفشل دائماً** بخطأ قيد قاعدة، فلا الإدارة تعتمد
    -- ولا ترفض، والمعاملة المنجزة ميدانياً تبقى معلّقة أبداً.
    v_req.req_by, 2,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب الإتمام' ELSE 'تم رفض طلب الإتمام' END,
    CASE WHEN p_decision = 'approved' THEN 'تمت الموافقة على طلب إتمام المعاملة ✓'
         ELSE 'تم رفض طلب الإتمام: ' || COALESCE(p_office_notes, '') END,
    v_req.app_id::TEXT, NOW()
  );
  RETURN TRUE;
END;
$function$;
CREATE OR REPLACE FUNCTION public.submit_broker_request_internal(p_user_uid uuid, p_business_name text, p_category integer, p_experience text DEFAULT ''::text, p_about text DEFAULT ''::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_vrf INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_user_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  -- التحقق من التوثيق (شرط مسبق)
  SELECT vrf INTO v_vrf FROM users WHERE id = p_user_uid AND i_del = 0;
  IF v_vrf IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND';
  END IF;
  IF v_vrf < 2 THEN
    RAISE EXCEPTION 'IDENTITY_NOT_VERIFIED';
  END IF;

  -- حفظ بيانات الوساطة
  UPDATE users
  SET brk_nm = COALESCE(p_business_name, ''),
      brk_cls = COALESCE(p_category, 0),
      ts_upd = NOW()
  WHERE id = p_user_uid AND i_del = 0;

  -- إذا موثق أصلاً (vrf=2) → تفعيل فوري كوسيط
  IF v_vrf = 2 THEN
    UPDATE users
    SET role = 1, brk = 1, ts_upd = NOW()
    WHERE id = p_user_uid;

    INSERT INTO notifications (uid, tp, ttl, bdy, ts_crt)
    VALUES (
      p_user_uid, 4,
      '🎉 تم تفعيل حسابك كوسيط',
      'تهانينا! تم قبولك كوسيط عقاري باسم «' || COALESCE(p_business_name, '') || '». افتح لوحة الوسيط من حسابك.',
      NOW()
    );
  ELSE
    -- غير موثق → يحتاج مراجعة (vrf → 1)
    UPDATE users SET vrf = 1 WHERE id = p_user_uid AND vrf = 0;
  END IF;

  INSERT INTO activity_log (uid, act, det, ts_crt)
  VALUES (
    -- 🔒 BUG-028 (2026-08-14): tp=10 خارج القيد (0..5) ⇒ **كل طلب انضمام
    -- كوسيط يفشل** بخطأ قيد قاعدة. النوع 4 = شؤون الحساب والتوثيق (وهو
    -- المستخدم فعلياً لإشعار «تم تفعيل حسابك كوسيط»).
    p_user_uid, 4,
    'broker_request: ' || COALESCE(p_business_name, '') ||
      ' cat=' || COALESCE(p_category::TEXT, '0') ||
      CASE WHEN COALESCE(trim(p_experience), '') <> ''
           THEN ' exp=' || p_experience ELSE '' END,
    NOW()
  );

  RETURN TRUE;
END;
$function$;
