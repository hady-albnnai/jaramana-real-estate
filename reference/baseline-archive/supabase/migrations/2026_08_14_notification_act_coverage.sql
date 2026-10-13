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

  -- 🔒 ACT-001 (2026-08-14): كان الإشعار يُكتب بلا عمود `act` ⇒ يظهر في
  -- الدرج لكن الضغط عليه **لا يفعل شيئاً**، لأن الموجّه الموحّد
  -- (notification_router) يقرأ `act` ليقرّر الشاشة. الموظف يرى «طلب إتمام
  -- معاملة» ولا يستطيع فتحه فيبحث عنه يدوياً في القوائم.
  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
    -- 🔒 BUG-027 (2026-08-14): كان النوع 20 بينما قيد notifications_tp_check
  -- يسمح بـ0..5 فقط ⇒ **كل** طلب إتمام يفشل بخطأ قيد قاعدة، والمعاملة
  -- المنجزة ميدانياً لا تصل الإدارة إطلاقاً. أُكِّد حياً (جدول
  -- completion_requests فارغ رغم 14 موعداً). النوع الصحيح 2 = تشغيلي
  -- (مواعيد ومهام) وفق البيانات الحية.
  SELECT u.id, 2, 'طلب إتمام معاملة', 'المنفذ أرسل طلب إتمام لموعد — يرجى المراجعة',
      p_appointment_id, 'completion_request', NOW() FROM users u WHERE u.role >= 4 AND u.sts = 0 AND u.i_del = 0;
  RETURN TRUE;
END; $function$;
CREATE OR REPLACE FUNCTION public.trg_offer_status_changed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_offer_title TEXT;
  v_offer_num TEXT;
  v_title TEXT;
  v_body TEXT;
  v_type INT;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;
  v_offer_title := COALESCE(NEW.ttl, 'عرض');
  v_offer_num := COALESCE(NEW.offer_number::TEXT, '');

  IF NEW.sts = 2 AND OLD.sts = 1 THEN
    v_title := '✅ تم نشر العرض الخاص بك';
    v_body := 'تمت الموافقة على العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" وهو متاح الآن للجمهور.';
    v_type := 0;
  ELSIF NEW.sts = 3 AND OLD.sts = 1 THEN
    v_title := '❌ تم رفض العرض الخاص بك';
    v_body := 'العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" مرفوض. السبب: ' || COALESCE(NEW.rsn, 'غير محدد');
    v_type := 0;
  ELSIF NEW.sts = 4 AND OLD.sts = 2 THEN
    v_title := '⏰ انتهت صلاحية العرض الخاص بك';
    v_body := 'العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" انتهت مدته. يمكنك تجديده بالنقاط.';
    v_type := 0;
  ELSIF NEW.sts = 5 AND OLD.sts = 2 THEN
    v_title := '🔒 العرض الخاص بك محجوز';
    v_body := 'تم حجز العرض رقم ' || v_offer_num || ' — "' || v_offer_title || '" بانتظار إتمام الصفقة.';
    v_type := 0;
  ELSE
    RETURN NEW;
  END IF;

  -- 🔒 ACT-001 (2026-08-14): كان الإشعار بلا عمود `act` ⇒ صاحب العرض يستلم
  -- إشعار تغيّر حالة العرض الخاص به ولا يستطيع فتحه بالضغط، لأن الموجّه الموحّد يقرأ `act`
  -- ليقرّر الشاشة. القيمة offer_status تُوجّه إلى تفاصيل العرض.
  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (NEW.usr_id, v_type, v_title, v_body, NEW.id, 'offer_status', NOW());
  RETURN NEW;
END;
$function$;
