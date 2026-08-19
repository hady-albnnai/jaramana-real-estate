-- ══════════════════════════════════════════════════════════════════════
-- 2026-08-19 — إصلاحات إشعارات العروض والمدفوعات (م2، م6، م8، م11 من
-- خطة الإصلاح الشاملة 2026-08-19) — يُنشر بعد التحقق الحي (git pull + فحص pg_trigger)
-- ══════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────────────────────────────────────
-- ① م2/م11: notify_admin_on_new_offer — النص الصحيح + المستلمون الصحيحون
-- المشكلة: النص كان «أضاف موظفاً عرضاً جديداً» حتى عندما يضيف مستخدم عادي
-- (added_by = NULL يسقط على كلمة 'موظف' الحرفية)، والمستلمون كانوا
-- role >= 4 فيشملون المحامي (7) والمعقّب (8) الذين لا علاقة لهم بمراجعة
-- العروض ⇒ المحامي يستلم إشعارات عروض لا تخصّه.
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_admin_on_new_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_actor_name TEXT;
  staff RECORD;
BEGIN
  IF NEW.sts <> 1 THEN RETURN NEW; END IF;

  -- من أضاف العرض فعلياً: added_by (موظف إداري) أو صاحب العرض (مستخدم عادي)
  SELECT nm INTO v_actor_name FROM users WHERE id = COALESCE(NEW.added_by, NEW.usr_id);
  v_actor_name := COALESCE(NULLIF(v_actor_name, ''), 'مستخدم');

  v_title := '🆕 عرض جديد بانتظار المراجعة';
  v_body  := 'أضاف ' || v_actor_name || ' عرضاً جديداً: ' || COALESCE(NEW.ttl, '');

  -- أشعر الشخص الذي أضاف العرض (موظف الإدارة نفسه — تأكيد شخصي)
  IF NEW.added_by IS NOT NULL THEN
    PERFORM notify_user(NEW.added_by, 0, v_title, v_body, NEW.id::text, 'offer');
  END IF;

  -- أشعر موظفي المكتب فما فوق (4،5،6) فقط — لا المحامي (7) ولا المعقّب (8)
  FOR staff IN
    SELECT id FROM users
    WHERE role IN (4, 5, 6)
      AND i_del = 0
      AND sts = 0
      AND (NEW.added_by IS NULL OR id <> NEW.added_by)
  LOOP
    PERFORM notify_user(staff.id, 0, v_title, v_body, NEW.id::text, 'offer');
  END LOOP;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.notify_admin_on_new_offer() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notify_admin_on_new_offer() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_admin_on_new_offer() TO service_role;

-- ⚠️ تحقق حي قبل النشر: التريغر الذي يوقظ هذه الدالة غير موجود في الريبو
-- (انحراف ريبو↔سيرفر). الإشعار كان يصل فعلاً ⇒ التريغر موجود حياً باسم
-- مجهول. تحقّق:
--   SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
--   WHERE c.relname='offers' AND NOT t.tgisinternal;
-- إن لم يوجد تريغر يوقظها (فقط حينها) نفّذ:
--   DROP TRIGGER IF EXISTS trg_new_offer_admin_notify ON offers;
--   CREATE TRIGGER trg_new_offer_admin_notify
--     AFTER INSERT ON offers FOR EACH ROW EXECUTE FUNCTION notify_admin_on_new_offer();

-- ──────────────────────────────────────────────────────────────────────
-- ② م6: trg_offer_status_changed — تجاهل فرع الاعتماد (1→2) لمنع الازدواج
-- فرع 1→2 كان يرسل «✅ تم نشر العرض الخاص بك» مكرراً مع إشعار الدالة
-- admin_review_offer_internal (نفس الحدث = إشعاران للمستخدم).
-- القرار: الدالة هي مصدر إشعار الاعتماد (بعد تعديل ③)، والتريغر يتجاهل
-- 1→2 ويبقى مسؤولاً عن الرفض (3) والانتهاء (4) والحجز (5) فقط.
-- ──────────────────────────────────────────────────────────────────────
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

  -- م6 (2026-08-19): فرع الاعتماد (1→2) تجاهل — إشعاره يصدر من
  -- admin_review_offer_internal حصراً (مع «ونشره») لمنع الازدواج.
  IF NEW.sts = 2 AND OLD.sts = 1 THEN
    RETURN NEW;
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

  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, ts_crt)
  VALUES (NEW.usr_id, v_type, v_title, v_body, NEW.id, 'offer_status', NOW());
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_offer_status_changed() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_offer_status_changed() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offer_status_changed() TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- ③ م6: admin_review_offer_internal — عنوان الاعتماد «ونشره»
-- (إعادة تعريف النسخة الكاملة المحدثة بـ TTL 30 يوماً مع التعديل الوحيد:
--  العنوان/النص في INSERT وsend_push — «تم اعتماد العرض الخاص بك ونشره»)
-- ──────────────────────────────────────────────────────────────────────
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

  SELECT usr_id, ttl, sts INTO v_owner_uid, v_ttl, v_cur_sts
  FROM offers WHERE id = p_offer_id AND i_del = 0;

  -- BUG-016 (2026-08-14): فحص وجود العرض (كان UPDATE بلا صفوف يعيد نجاحاً وهمياً)
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
    -- IMG-001 (2026-08-15): لا اعتماد لعرض بلا صورة (آخر بوابة قبل النشر)
    IF COALESCE(jsonb_array_length(NULLIF(
         (SELECT imgs FROM offers WHERE id = p_offer_id), 'null'::jsonb)), 0) < 1 THEN
      RAISE EXCEPTION 'OFFER_IMAGE_REQUIRED';
    END IF;

    -- OFFER-TTL-001 (2026-08-15): مدة العرض 30 يوماً من لحظة النشر الفعلي
    UPDATE offers
       SET sts    = 2,
           i_pub  = 1,
           ts_pub = NOW(),
           ts_end = NOW() + INTERVAL '30 days'
     WHERE id = p_offer_id AND i_del = 0;

    -- م6 (2026-08-19): العنوان صار «ونشره» (طلب المالك) — كان «تم اعتماده»
    -- فقط رغم أن النص يقول «تم اعتماده ونشره»
    IF v_owner_uid IS NOT NULL THEN
      INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
      VALUES (
        v_owner_uid, 1,
        '✅ تم اعتماد العرض الخاص بك ونشره',
        'العرض الخاص بك «' || COALESCE(v_ttl, '') || '» تم اعتماده ونشره — يمكنك مشاهدته الآن في الصفحة الرئيسية.',
        p_offer_id::TEXT, 'offer_approved', 0, 0, NOW()
      );
      PERFORM public.send_push_notification(
        v_owner_uid,
        '✅ تم اعتماد العرض الخاص بك ونشره',
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
$function$;

REVOKE ALL ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) TO service_role;

-- ──────────────────────────────────────────────────────────────────────
-- ④ م8: إشعار «دفعة جديدة» للإدارة عند إنشاء أي دفعة (AFTER INSERT)
-- كانت كل تريغرات الدفعات AFTER UPDATE OF sts وتشعر الدافع فقط ⇒ لا إشعار
-- للإدارة إطلاقاً عند وصول دفعة جديدة (فشل التحقق من شارة المدفوعات).
-- هذا التريغر يشعر نائب المدير والمدير (5،6 — حاملو إدارة المدفوعات)
-- فوراً بكل دفعة جديدة (sts=0) مع push. الـ act الجديد payment_review
-- يُضاف في الواجهة إلى notification_router (شاشة المدفوعات).
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trg_payment_new_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title TEXT;
  v_body TEXT;
  staff RECORD;
BEGIN
  -- فقط الدفعات الجديدة قيد المراجعة (sts=0 عند الإنشاء في المسار الطبيعي)
  IF NEW.sts <> 0 THEN RETURN NEW; END IF;

  v_title := '💳 دفعة جديدة بانتظار الموافقة';
  v_body  := 'وصلت دفعة جديدة بقيمة ' || COALESCE(NEW.amt::text, '0') ||
             ' — راجعها في شاشة المدفوعات.';

  FOR staff IN
    SELECT id FROM users
    WHERE role IN (5, 6)  -- نائب المدير والمدير — صلاحية manage_payments
      AND i_del = 0 AND sts = 0
  LOOP
    INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
    VALUES (staff.id, 3, v_title, v_body, NEW.id::text, 'payment_review', 0, 0, NOW());
    PERFORM public.send_push_notification(staff.id, v_title, v_body,
      jsonb_build_object('act', 'payment_review', 'ref_id', NEW.id::text));
  END LOOP;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.trg_payment_new_notify() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_payment_new_notify() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_payment_new_notify() TO service_role;

DROP TRIGGER IF EXISTS trg_payment_new_notify ON payments;
CREATE TRIGGER trg_payment_new_notify
AFTER INSERT ON payments
FOR EACH ROW EXECUTE FUNCTION public.trg_payment_new_notify();

-- ──────────────────────────────────────────────────────────────────────
-- ⑤ م13: تسريع Push الأحداث الحرجة للاستشارة (مهلة انضمام دقيقتين)
-- المشكلة: كل Push الاستشارات يمر عبر outbox يعالجه كرون كل دقيقة ⇒
-- «تأخر إشعار بدأ الجلسة» رغم أن مهلة انضمام المستخدم دقيقتان فقط.
-- الحل: للأحداث الحرجة (المحامي جاهز / العميل انضم) يُرسل push فوراً من
-- التريغر، ويبقى outbox كاحتياط موثوق (لو فشل FCM يعيد المعالج المحاولة).
-- إعادة تعريف enqueue_consultation_notification_push بالنسخة الحية + الإضافة.
-- ──────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enqueue_consultation_notification_push()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $function$
DECLARE v_role integer;
BEGIN
  SELECT role INTO v_role FROM public.users WHERE id=NEW.uid;
  IF NEW.act IN ('legal_session_auto_started','legal_session_ended','legal_waitlist_available')
     OR (NEW.act='legal_onsite_confirmed' AND v_role=7) THEN
    INSERT INTO public.consultation_event_outbox(event_key,event_type,recipient_uid,reference_id,payload)
    VALUES('notification:'||NEW.id,NEW.act,NEW.uid,
      CASE WHEN NEW.ref_id ~* '^[0-9a-f-]{36}$' THEN NEW.ref_id::uuid ELSE NULL END,
      jsonb_build_object('title',NEW.ttl,'body',NEW.bdy,'act',NEW.act,'ref_id',NEW.ref_id))
    ON CONFLICT(event_key) DO NOTHING;
  END IF;

  -- م13 (2026-08-19): الأحداث الحرجة تُرسل push فوراً — لا انتظار كرون الدقيقة
  -- (مهلة انضمام المستخدم دقيقتان فقط؛ أي تأخير يكسر التجربة). الـ outbox
  -- أعلاه يبقى احتياطاً: لو فشل FCM هنا سيعيد المعالج المحاولة.
  IF NEW.act IN ('legal_lawyer_ready','legal_user_joined') THEN
    BEGIN
      PERFORM public.send_push_notification(NEW.uid, NEW.ttl, NEW.bdy,
        jsonb_build_object('act', NEW.act, 'ref_id', NEW.ref_id));
    EXCEPTION WHEN OTHERS THEN
      NULL; -- فشل FCM هنا لا يُسقط الإشعار — outbox يتكفل
    END;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.enqueue_consultation_notification_push() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.enqueue_consultation_notification_push() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_consultation_notification_push() TO service_role;
