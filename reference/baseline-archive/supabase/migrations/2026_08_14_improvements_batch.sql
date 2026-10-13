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
    -- باقة اشتراك: السعر من pkg.<id>.pr
    v_expected := (v_cfg->'pkg'->(v_pkg::TEXT)->>'pr')::NUMERIC;
    IF v_expected IS NULL THEN
      RAISE EXCEPTION 'PACKAGE_PRICE_NOT_FOUND';
    END IF;
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
$function$;
-- ============================================================================
-- IMP-001 — عكس قبول دفعة (لم يكن له أي مسار)
-- ============================================================================
-- الفجوة: بعد اعتماد الدفعة لا توجد أي طريقة لعكسها من التطبيق. احتيال
-- يُكتشف بعد ساعة = تدخّل SQL يدوي على قاعدة الإنتاج، وهو أخطر ما يمكن أن
-- يُطلب من مالك غير مبرمج.
-- التصميم: مدير فقط (role=6) + سبب إلزامي + سجل تدقيق + إشعار للمستخدم +
-- تراجع فعلي عن الأثر (الباقة أو الإعلان المميّز).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.admin_reverse_payment(
  p_admin_uid  uuid,
  p_payment_id uuid,
  p_reason     text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_role    INT;
  v_pay     payments%ROWTYPE;
  v_offer   UUID;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;

  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL THEN
    RAISE EXCEPTION 'ADMIN_NOT_FOUND_OR_INACTIVE';
  END IF;
  -- المدير وحده — العكس أخطر من الاعتماد نفسه
  IF v_role <> 6 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_REVERSE';
  END IF;

  IF COALESCE(trim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'REVERSAL_REASON_REQUIRED';
  END IF;

  SELECT * INTO v_pay FROM payments WHERE id = p_payment_id;
  IF v_pay.id IS NULL THEN
    RAISE EXCEPTION 'PAYMENT_NOT_FOUND';
  END IF;
  IF v_pay.sts <> 1 THEN
    RAISE EXCEPTION 'PAYMENT_NOT_APPROVED';
  END IF;

  -- التراجع عن الأثر حسب نوع الدفعة
  IF v_pay.tp = 0 THEN
    -- باقة: إعادة المستخدم للمجانية. لا نحاول استرجاع الحالة السابقة بدقة
    -- (نموذج التجميع يجعلها غير قابلة للاشتقاق)، والمدير يُعيد المنح يدوياً.
    UPDATE users
    SET b_pkg = 0, pkg_end = NULL, pkg_xoff = 0, ts_upd = NOW()
    WHERE id = v_pay.uid;
  ELSIF v_pay.tp = 1 THEN
    v_offer := NULLIF(v_pay.meta->>'offer_id','')::UUID;
    IF v_offer IS NOT NULL THEN
      UPDATE offers SET i_fms = 0, fms_end = NULL WHERE id = v_offer;
    END IF;
  END IF;
  -- tp=2 (استشارة): لا تراجع تلقائي — الاستشارة قد تكون بدأت فعلاً،
  -- والإدارة تتصرّف يدوياً (منح رصيد أو إعادة مبلغ) حسب قرار المالك.

  UPDATE payments
  SET sts = 3,
      meta = COALESCE(meta,'{}'::jsonb) || jsonb_build_object(
        'reversed_by', p_admin_uid,
        'reversed_at', NOW(),
        'reversal_reason', trim(p_reason),
        'prev_sts', 1
      )
  WHERE id = p_payment_id;

  INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
  VALUES (
    v_pay.uid, 2,
    'تم التراجع عن اعتماد دفعة',
    'تمّ التراجع عن اعتماد دفعتك — السبب: ' || trim(p_reason) ||
    '. يرجى التواصل مع المكتب.',
    p_payment_id::TEXT, 'payment_reversed', 0, 0, NOW()
  );

  PERFORM public.log_admin_action(
    p_admin_uid, 121,
    'عكس اعتماد دفعة (' || v_pay.amt::TEXT || ') — ' || trim(p_reason),
    p_payment_id::TEXT, 'payments'
  );

  RETURN jsonb_build_object('success', true, 'payment_id', p_payment_id, 'tp', v_pay.tp);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_reverse_payment(uuid, uuid, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_reverse_payment(uuid, uuid, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reverse_payment(uuid, uuid, text) TO service_role;
-- IMP-001 متمّم: توسيع قيد حالات الدفعة ليشمل «معكوسة».
-- 0 معلّقة · 1 مقبولة · 2 مرفوضة · 3 معكوسة (جديد 2026-08-14)
ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_sts_check;
ALTER TABLE public.payments ADD CONSTRAINT payments_sts_check
  CHECK (sts >= 0 AND sts <= 3);
COMMENT ON CONSTRAINT payments_sts_check ON public.payments IS
  '0 معلّقة · 1 مقبولة · 2 مرفوضة · 3 معكوسة (عكس اعتماد بقرار مدير)';
-- ============================================================================
-- IMP-002 — نسخ احتياطية للإعدادات + سجل تدقيق يحفظ القيمة القديمة
-- ============================================================================
-- الفجوة: app_config فيه صفّان فقط (main, fcm) ولا نسخة احتياطية إطلاقاً.
-- خطأ واحد في محرّر الإعدادات (سعر خاطئ، نص ممسوح، قناة معطّلة) = **لا رجعة**.
-- وسجل التدقيق يسجّل «config sections: legalPrice» فقط — بلا القيمة القديمة
-- ولا الجديدة، فحتى معرفة ما تغيّر مستحيلة.
-- الحل: جدول تاريخ + trigger يلتقط كل تغيير تلقائياً + دالة استرجاع.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_config_history (
  id          BIGSERIAL PRIMARY KEY,
  config_key  TEXT        NOT NULL,
  old_value   JSONB       NOT NULL,
  new_value   JSONB,
  changed_by  UUID,
  ts_crt      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cfg_hist_key_ts
  ON public.app_config_history (config_key, ts_crt DESC);

ALTER TABLE public.app_config_history ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_config_history FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.app_config_history TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.app_config_history_id_seq TO service_role;

-- ── Trigger: التقاط كل تغيير على app_config ──
CREATE OR REPLACE FUNCTION public.trg_app_config_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
BEGIN
  IF OLD.value IS DISTINCT FROM NEW.value THEN
    INSERT INTO public.app_config_history (config_key, old_value, new_value, changed_by)
    VALUES (OLD.key, OLD.value, NEW.value, auth.uid());

    -- الاحتفاظ بآخر 50 نسخة لكل مفتاح — يمنع تضخّم الجدول بلا حدود
    DELETE FROM public.app_config_history
    WHERE id IN (
      SELECT id FROM public.app_config_history
      WHERE config_key = OLD.key
      ORDER BY ts_crt DESC
      OFFSET 50
    );
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_app_config_history ON public.app_config;
CREATE TRIGGER trg_app_config_history
  AFTER UPDATE ON public.app_config
  FOR EACH ROW EXECUTE FUNCTION public.trg_app_config_history();

-- ── قائمة النسخ (بلا الحمولة الكاملة — للعرض بالواجهة) ──
CREATE OR REPLACE FUNCTION public.admin_list_config_history(
  p_admin_uid uuid,
  p_key       text DEFAULT 'main',
  p_limit     int  DEFAULT 20
)
RETURNS TABLE (id bigint, ts_crt timestamptz, changed_by uuid, changed_sections text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE v_role INT;
BEGIN
  SELECT role INTO v_role FROM users WHERE users.id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role < 5 OR v_role > 6 THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  RETURN QUERY
  SELECT h.id, h.ts_crt, h.changed_by,
         (SELECT string_agg(k, ', ' ORDER BY k)
          FROM jsonb_object_keys(COALESCE(h.new_value,'{}'::jsonb)) k
          WHERE h.old_value->k IS DISTINCT FROM h.new_value->k) AS changed_sections
  FROM public.app_config_history h
  WHERE h.config_key = p_key
  ORDER BY h.ts_crt DESC
  LIMIT GREATEST(1, LEAST(p_limit, 50));
END;
$fn$;

-- ── الاسترجاع: مدير فقط ──
CREATE OR REPLACE FUNCTION public.admin_restore_config(
  p_admin_uid uuid,
  p_history_id bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_role INT;
  v_row  public.app_config_history%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND auth.uid() <> p_admin_uid THEN
    RAISE EXCEPTION 'AUTH_UID_MISMATCH';
  END IF;
  SELECT role INTO v_role FROM users WHERE id = p_admin_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role <> 6 THEN
    RAISE EXCEPTION 'ONLY_MANAGER_CAN_RESTORE';
  END IF;

  SELECT * INTO v_row FROM public.app_config_history WHERE id = p_history_id;
  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'HISTORY_ENTRY_NOT_FOUND';
  END IF;

  -- الاسترجاع نفسه تغييرٌ يُلتقط بالـtrigger، فيبقى الحاضر قابلاً للعودة إليه
  UPDATE public.app_config SET value = v_row.old_value WHERE key = v_row.config_key;

  PERFORM public.log_admin_action(
    p_admin_uid, 122,
    'استرجاع إعدادات من نسخة ' || v_row.ts_crt::TEXT,
    v_row.config_key, 'app_config'
  );

  RETURN jsonb_build_object('success', true, 'restored_from', v_row.ts_crt);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_list_config_history(uuid, text, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_list_config_history(uuid, text, int) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_config_history(uuid, text, int) TO service_role;

REVOKE ALL ON FUNCTION public.admin_restore_config(uuid, bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admin_restore_config(uuid, bigint) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_restore_config(uuid, bigint) TO service_role;

REVOKE ALL ON FUNCTION public.trg_app_config_history() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.trg_app_config_history() FROM anon, authenticated;
-- ============================================================================
-- IMP-003 — صيانة يومية للمواعيد (لم تكن موجودة بين 9 مهام cron)
-- ============================================================================
-- الفجوة: موعد بحالة «بانتظار» (0) أو «مؤكد» (1) ومرّ تاريخه يبقى معلّقاً
-- **للأبد**. لا شيء يغلقه ولا ينبّه أحداً. يشوّش قوائم الإدارة والوسيط
-- ويضخّم العدّادات — نفس العلة التي عالجناها للاستشارات القانونية.
-- القاعدة: بعد مرور 24 ساعة على وقت الموعد بلا حسم ⇒ يُلغى آلياً بسبب واضح.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.appointments_daily_maintenance()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public','extensions','pg_temp'
AS $fn$
DECLARE
  v_closed INT := 0;
  v_rec    RECORD;
BEGIN
  FOR v_rec IN
    SELECT id, own_id, req_uid, bkr_id, dt
    FROM public.appointments
    WHERE sts IN (0, 1)
      AND dt < NOW() - INTERVAL '24 hours'
  LOOP
    UPDATE public.appointments
    SET sts = 3,
        cnl_rsn = 'إغلاق تلقائي: مضى الموعد بلا تأكيد الحضور'
    WHERE id = v_rec.id;

    v_closed := v_closed + 1;

    -- إشعار الطرفين — الصمت هنا يترك المستخدم يظن موعده قائماً
    IF v_rec.req_uid IS NOT NULL THEN
      INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
      VALUES (v_rec.req_uid, 3, '⏰ أُغلق موعد منتهٍ',
              'تم إغلاق موعد المعاينة تلقائياً لمرور وقته بلا تأكيد. يمكنك حجز موعد جديد.',
              v_rec.id::TEXT, 'appointment_expired', 0, 0, NOW());
    END IF;
    IF v_rec.own_id IS NOT NULL AND v_rec.own_id <> COALESCE(v_rec.req_uid, '00000000-0000-0000-0000-000000000000'::uuid) THEN
      INSERT INTO notifications (uid, tp, ttl, bdy, ref_id, act, i_rd, i_del, ts_crt)
      VALUES (v_rec.own_id, 3, '⏰ أُغلق موعد منتهٍ',
              'تم إغلاق موعد معاينة على عقارك تلقائياً لمرور وقته بلا تأكيد.',
              v_rec.id::TEXT, 'appointment_expired', 0, 0, NOW());
    END IF;
  END LOOP;

  RETURN jsonb_build_object('success', true, 'closed', v_closed, 'ts', NOW());
END;
$fn$;

REVOKE ALL ON FUNCTION public.appointments_daily_maintenance() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.appointments_daily_maintenance() FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.appointments_daily_maintenance() TO service_role;

SELECT cron.unschedule('daily-appointments-maintenance')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-appointments-maintenance');

SELECT cron.schedule('daily-appointments-maintenance', '40 3 * * *',
  $$SELECT public.appointments_daily_maintenance();$$);
