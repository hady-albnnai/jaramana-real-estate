-- ═══════════════════════════════════════════════════════════════════════════
-- 2026_08_14_consultation_payment_approval.sql
-- الغرض: إغلاق عطل حرج — اعتماد دفعات الاستشارة القانونية (tp=2) كان مستحيلاً.
--
-- الحقائق الحية التي بنيت عليها هذه المايغريشن (فُحصت 2026-08-14):
--   1) approve_payment_final تعالج tp=0 وtp=1 فقط ⇒ أي دفعة tp=2 ترد
--      UNSUPPORTED_PAYMENT_TYPE ⇒ زر «قبول» بشاشة مدفوعات الإدارة معطّل خادمياً.
--   2) الدفعات القديمة tp=2 sts=1 لها appr_by = NULL ⇒ اعتُمدت بـ UPDATE يدوي
--      لا عبر مسار التطبيق — أي أن المسار لم يُختبر حقيقياً من قبل.
--   3) trg_payment_approved (على trg_payment_notify AFTER UPDATE OF sts) لا تعرف
--      tp=2 ⇒ الإشعار الواصل كان «✅ تم تفعيل اشتراكك — الباقة المجانية».
--   4) meta.continue_chat (تجديد محادثة) لم يكن يقرأه أحد عند الاعتماد ⇒ وعد
--      الواجهة «بعد التأكيد تُفتح المحادثة تلقائياً» غير منفَّذ.
--
-- التحصين: كلا الكائنين SECURITY DEFINER بـ search_path مثبّت، وACL الحي قبل
-- التعديل كان: postgres=X | service_role=X (بلا PUBLIC/anon/authenticated).
-- يُعاد تطبيق الرباعي صراحةً بنهاية الملف حفاظاً على نفس الوضع.
--
-- idempotent: CREATE OR REPLACE بنفس التوقيع تماماً (لا overload جديد).
-- ═══════════════════════════════════════════════════════════════════════════

-- ①  approve_payment_final — إضافة فرع الاستشارة القانونية (tp=2)
CREATE OR REPLACE FUNCTION public.approve_payment_final(p_payment_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_user_id UUID; v_pkg_id INT; v_admin_role INT;
  v_payment_status INT; v_payment_type INT; v_meta JSONB;
  v_config JSONB; v_pkg_duration INT; v_grace_days INT;
  v_old_pkg INT; v_old_end TIMESTAMPTZ; v_old_xoff INT;
  v_offer UUID; v_weeks INT; v_base TIMESTAMPTZ; v_new_end TIMESTAMPTZ;
  v_new_pkg INT; v_new_xoff INT; v_o_old INT; v_o_new INT;
  v_active BOOLEAN; v_upgraded BOOLEAN := false;
  -- متغيرات فرع الاستشارة القانونية (tp=2) — أُضيفت 2026-08-14
  v_svc TEXT; v_chat UUID; v_c_user UUID; v_c_started TIMESTAMPTZ;
  v_c_dur INT; v_c_renew INT;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'AUTH_UID_MISMATCH');
  END IF;
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_id AND i_del = 0;
  IF v_admin_role IS NULL OR v_admin_role < 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'FORBIDDEN');
  END IF;
  SELECT uid, pkg, sts, tp, meta INTO v_user_id, v_pkg_id, v_payment_status, v_payment_type, v_meta
  FROM payments WHERE id = p_payment_id;
  IF v_user_id IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_FOUND'); END IF;
  IF COALESCE(v_payment_status, -1) <> 0 THEN RETURN jsonb_build_object('success', false, 'error', 'PAYMENT_NOT_PENDING'); END IF;
  SELECT value INTO v_config FROM app_config WHERE key = 'main';

  IF COALESCE(v_payment_type, -1) = 0 THEN
    v_pkg_duration := (v_config->'pkg'->(v_pkg_id::text)->>'d')::INT;
    v_grace_days := COALESCE((v_config->'pkg'->>'grace_days')::INT, 3);
    IF v_pkg_duration IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'PKG_DURATION_NOT_FOUND'); END IF;
    SELECT b_pkg, pkg_end, COALESCE(pkg_xoff, 0)
      INTO v_old_pkg, v_old_end, v_old_xoff
      FROM users WHERE id = v_user_id;

    -- نموذج التجميع (2026-07-27): الباقة الجديدة تُضاف للرصيد، ولا يُلغى شيء مدفوع.
    -- ترقية ← سقف القديمة ينتقل للإضافي (pkg_xoff) وتصبح الجديدة الأساس.
    -- تجديد/شراء أدنى ← سقف المشترى يُضاف للإضافي والأساس يبقى الأعلى.
    -- الأيام تُضاف فوق المتبقي دائماً. عند الانتهاء يسقط الكل مع التاريخ الموحد.
    v_active := COALESCE(v_old_pkg, 0) > 0 AND v_old_end IS NOT NULL AND v_old_end > NOW();
    IF v_active THEN
      v_base := v_old_end;
      v_o_old := (v_config->'pkg'->(v_old_pkg::text)->>'o')::INT;
      v_o_new := (v_config->'pkg'->(v_pkg_id::text)->>'o')::INT;
      IF v_pkg_id > v_old_pkg THEN
        v_new_pkg := v_pkg_id;
        v_new_xoff := v_old_xoff + COALESCE(v_o_old, 0);
        v_upgraded := true;
      ELSE
        v_new_pkg := GREATEST(v_old_pkg, v_pkg_id);
        v_new_xoff := v_old_xoff + COALESCE(v_o_new, 0);
      END IF;
    ELSE
      v_base := NOW();
      v_new_pkg := v_pkg_id;
      v_new_xoff := 0;
    END IF;
    v_new_end := v_base + (v_pkg_duration || ' days')::interval;
    UPDATE payments SET sts = 1, appr_by = p_admin_id WHERE id = p_payment_id AND sts = 0;
    UPDATE users SET b_pkg = v_new_pkg, pkg_xoff = v_new_xoff, pkg_end = v_new_end,
      pkg_grace = v_new_end + (v_grace_days || ' days')::interval, ts_upd = NOW()
    WHERE id = v_user_id;
    RETURN jsonb_build_object('success', true, 'type', 'package', 'pkg', v_new_pkg,
      'until', to_char(v_new_end, 'YYYY-MM-DD'),
      'upgraded', v_upgraded, 'stacked', v_active,
      'quota', ((v_config->'pkg'->(v_new_pkg::text)->>'o')::INT + v_new_xoff));
  END IF;

  IF COALESCE(v_payment_type, -1) = 1 THEN
    v_offer := NULLIF(v_meta->>'offer_id', '')::UUID;
    v_weeks := COALESCE((v_meta->>'weeks')::INT, 0);
    IF v_offer IS NULL OR v_weeks < 1 THEN
      RETURN jsonb_build_object('success', false, 'error', 'FEATURED_META_INVALID');
    END IF;
    UPDATE offers
    SET i_fms = 1, fms_end = GREATEST(NOW(), COALESCE(fms_end, NOW())) + ((v_weeks * 7) || ' days')::interval
    WHERE id = v_offer AND i_del = 0
    RETURNING fms_end INTO v_new_end;
    IF v_new_end IS NULL THEN
      RAISE EXCEPTION 'OFFER_NOT_FOUND';
    END IF;
    UPDATE payments SET sts = 1, appr_by = p_admin_id WHERE id = p_payment_id AND sts = 0;
    RETURN jsonb_build_object('success', true, 'type', 'featured', 'offer_id', v_offer,
      'until', to_char(v_new_end, 'YYYY-MM-DD'));
  END IF;

  -- ═══════════════════════════════════════════════════════════════════
  -- tp = 2 : دفعة استشارة قانونية  (أُضيف 2026-08-14)
  -- السبب: الدالة كانت تعرف tp=0 (باقة) وtp=1 (إعلان مميز) فقط، فكل دفعة
  -- استشارة ترتد UNSUPPORTED_PAYMENT_TYPE ⇒ زر «قبول» بشاشة المدفوعات
  -- معطّل خادمياً بالكامل لهذا النوع (الدفعات القديمة اعتُمدت بـ UPDATE يدوي:
  -- appr_by = NULL دليلاً حياً على ذلك).
  -- pkg: 0 = استشارة هاتفية (500) · 1 = جلسة حضورية (2000)
  -- meta.continue_chat = معرّف محادثة سابقة ⇒ تجديد تلقائي بدل استشارة جديدة.
  -- ═══════════════════════════════════════════════════════════════════
  IF COALESCE(v_payment_type, -1) = 2 THEN
    IF COALESCE(v_meta->>'service', '') <> 'legal_consultation' THEN
      RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_META_INVALID');
    END IF;
    IF COALESCE(v_pkg_id, -1) NOT IN (0, 1) THEN
      RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_TYPE_INVALID');
    END IF;

    v_svc := CASE v_pkg_id WHEN 0 THEN 'phone' ELSE 'onsite' END;
    v_chat := NULLIF(v_meta->>'continue_chat', '')::UUID;

    UPDATE payments SET sts = 1, appr_by = p_admin_id WHERE id = p_payment_id AND sts = 0;

    -- ── مسار التجديد: دفعة متابعة محادثة سابقة ──
    IF v_chat IS NOT NULL THEN
      SELECT user_uid, chat_started_at, COALESCE(chat_duration_minutes, 15), COALESCE(renew_count, 0)
        INTO v_c_user, v_c_started, v_c_dur, v_c_renew
        FROM legal_consultations
       WHERE id = v_chat AND i_del = 0;

      IF v_c_user IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_NOT_FOUND');
      END IF;
      IF v_c_user <> v_user_id THEN
        RETURN jsonb_build_object('success', false, 'error', 'CONSULTATION_OWNER_MISMATCH');
      END IF;
      IF v_c_started IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'CHAT_NOT_STARTED');
      END IF;
      IF NOW() > v_c_started + INTERVAL '7 days' THEN
        RETURN jsonb_build_object('success', false, 'error', 'CHAT_EXPIRED_7DAYS');
      END IF;

      UPDATE legal_consultations
         SET chat_duration_minutes = v_c_dur + 15,
             renew_count           = v_c_renew + 1,
             payment_id            = COALESCE(payment_id, p_payment_id),
             payment_status        = 1,
             ts_upd                = NOW()
       WHERE id = v_chat;

      INSERT INTO consultation_chats (consultation_id, sender_id, message_type, content)
      VALUES (v_chat, v_user_id, 'system',
              '⏱️ تم تأكيد الدفع — تجديد المحادثة 15 دقيقة إضافية (التجديد رقم '
              || (v_c_renew + 1)::text || ')');

      RETURN jsonb_build_object('success', true, 'type', 'consultation_renew',
        'service', v_svc, 'consultation_id', v_chat,
        'duration_minutes', v_c_dur + 15, 'renew_count', v_c_renew + 1);
    END IF;

    -- ── مسار الاستشارة الجديدة: الدفعة جاهزة ليُرسل المستخدم طلبه للمحامي ──
    RETURN jsonb_build_object('success', true, 'type', 'consultation',
      'service', v_svc, 'pkg', v_pkg_id, 'amount', (SELECT amt FROM payments WHERE id = p_payment_id));
  END IF;

  RETURN jsonb_build_object('success', false, 'error', 'UNSUPPORTED_PAYMENT_TYPE');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END; $function$;

-- ②  trg_payment_approved — نصوص إشعار صحيحة لدفعات الاستشارة
CREATE OR REPLACE FUNCTION public.trg_payment_approved()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_title TEXT;
  v_body TEXT;
  v_pkg_name TEXT;
  v_reason TEXT;
  v_unread INT;
BEGIN
  IF NEW.sts = OLD.sts THEN RETURN NEW; END IF;

  v_pkg_name := CASE NEW.pkg
    WHEN 1 THEN 'الفضية'
    WHEN 2 THEN 'الذهبية'
    ELSE 'المجانية'
  END;

  IF NEW.sts = 1 THEN
    -- ✅ قبول: ينوّر (غير مقروء)
    v_title := '✅ تم تفعيل اشتراكك';
    IF COALESCE(NEW.tp, 0) = 1 THEN
      v_title := '⭐ تم تفعيل الإعلان المميّز';
      v_body := 'تم تفعيل الإعلان المميّز للعرض الخاص بك بنجاح' ||
        COALESCE(' — حتى ' || to_char(
          (SELECT o.fms_end AT TIME ZONE 'Asia/Damascus' FROM public.offers o
           WHERE o.id = NULLIF(NEW.meta->>'offer_id','')::uuid),
          'YYYY/MM/DD'), '') ||
        '. سيظهر العرض الخاص بك بقسم المميّزة وبأعلى النتائج.';
    ELSIF COALESCE(NEW.tp, 0) = 2 THEN
      -- ⚖️ دفعة استشارة قانونية (أُضيف 2026-08-14)
      -- قبل هذا التاريخ كان يصل للمستخدم «✅ تم تفعيل اشتراكك — الباقة المجانية»
      -- لأن الفرع الوحيد المتبقي كان فرع الباقات وpkg=0 يقابل «المجانية».
      IF NULLIF(NEW.meta->>'continue_chat', '') IS NOT NULL THEN
        v_title := '✅ تم تأكيد دفعة التجديد';
        v_body  := 'تم تجديد محادثتك القانونية 15 دقيقة إضافية — افتح المحادثة وتابع مع المحامي.';
      ELSIF COALESCE(NEW.pkg, 0) = 1 THEN
        v_title := '✅ تم تأكيد دفعة الجلسة الحضورية';
        v_body  := 'تم تأكيد دفعتك للجلسة الحضورية. ادخل لقسم الاستشارة القانونية وأرسل طلبك للمحامي.';
      ELSE
        v_title := '✅ تم تأكيد دفعة الاستشارة';
        v_body  := 'تم تأكيد دفعتك للاستشارة الهاتفية. ادخل لقسم الاستشارة القانونية وأرسل طلبك للمحامي.';
      END IF;
    ELSE
      v_body := 'تم تفعيل الباقة ' || v_pkg_name || ' بنجاح. استمتع بالمزايا الجديدة!';
    END IF;
    v_unread := 0;
  ELSIF NEW.sts = 2 THEN
    -- ❌ رفض: لا ينوّر (مقروء)
    v_title := '❌ تم رفض الدفعة';
    v_reason := COALESCE(NULLIF(BTRIM(COALESCE(NEW.meta->>'reject_reason', '')), ''), '');
    IF v_reason <> '' THEN
      v_body := 'لم تُقبل الدفعة — السبب: ' || LEFT(v_reason, 140) ||
                ' · صحّح البيانات وأعد الطلب من «سجل دفعاتي».';
    ELSE
      v_body := 'لم تُقبل الدفعة. يرجى مراجعة بيانات الدفع والمحاولة مرة أخرى.';
    END IF;
    v_unread := 1;  -- ❌ مقروء: لا ينوّر
  ELSE
    RETURN NEW;
  END IF;

  -- إدراج مباشر (بدل notify_user) للتحكم بـ i_rd
  INSERT INTO public.notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
  VALUES (NEW.uid, 3, v_title, v_body, NEW.id::text, 'payment', v_unread, 0, NOW());

  PERFORM public.send_push_notification(
    NEW.uid, v_title, v_body,
    jsonb_build_object('type', 'payment', 'id', NEW.id::text)
  );

  RETURN NEW;
END;
$function$;

-- ③  إعادة تطبيق رباعي التحصين (الدستور §7) — لا تغيير عن الوضع الحي السابق
REVOKE ALL ON FUNCTION public.approve_payment_final(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.approve_payment_final(uuid, uuid) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.approve_payment_final(uuid, uuid) TO service_role;

REVOKE ALL ON FUNCTION public.trg_payment_approved() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_payment_approved() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.trg_payment_approved() TO service_role;
