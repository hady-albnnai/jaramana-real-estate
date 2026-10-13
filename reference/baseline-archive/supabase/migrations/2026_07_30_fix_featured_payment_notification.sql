-- ============================================================================
-- 🐞 إصلاح: إشعار اعتماد «الإعلان المميّز المدفوع» يقول «تم تفعيل الباقة المجانية»
-- التاريخ: 2026-07-30 — انكشف أثناء اختبار الدفعات E2E
--
-- الجذر: trg_payment_approved يفترض أن كل دفعة مقبولة = اشتراك باقة، فيبني
-- الاسم من NEW.pkg عبر CASE ينتهي بـ ELSE 'المجانية'. الإعلان الممول (tp=1)
-- يأتي بـ pkg=0 ⇒ يقع على «المجانية» ⇒ المستخدم يدفع ثمن إعلان مميّز
-- ويصله «تم تفعيل الباقة المجانية بنجاح» — رسالة خاطئة ومربكة تماماً.
--
-- الدليل الحي (2026-07-30): اعتماد دفعة tp=1 amt=950 weeks=2 أنتج:
--   [✅ تم تفعيل اشتراكك] «تم تفعيل الباقة المجانية بنجاح. استمتع بالمزايا الجديدة!»
--
-- الإصلاح: تفريع حسب tp قبل بناء النص:
--   tp=1 ⇒ نص الإعلان المميّز (مع تاريخ الانتهاء إن توفّر)
--   tp=0 ⇒ نص الباقة كما هو
-- بقية منطق التريغر (i_rd عند القبول/الرفض، البوش، سبب الرفض) يبقى حرفياً.
-- ============================================================================

DO $$
DECLARE
  v_src TEXT;
  v_new TEXT;
  v_old_block TEXT;
  v_new_block TEXT;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'trg_payment_approved'
  LIMIT 1;

  IF v_src IS NULL THEN
    RAISE EXCEPTION 'trg_payment_approved غير موجودة';
  END IF;

  -- idempotent: إن كان الإصلاح مطبّقاً لا نفعل شيئاً
  IF position('الإعلان المميّز' in v_src) > 0 THEN
    RAISE NOTICE 'مُصلَحة سابقاً — لا تغيير';
    RETURN;
  END IF;

  v_old_block := 'v_body := ''تم تفعيل الباقة '' || v_pkg_name || '' بنجاح. استمتع بالمزايا الجديدة!'';';

  v_new_block :=
    'IF COALESCE(NEW.tp, 0) = 1 THEN' || E'\n' ||
    '      v_title := ''⭐ تم تفعيل الإعلان المميّز'';' || E'\n' ||
    '      v_body := ''تم تفعيل الإعلان المميّز للعرض الخاص بك بنجاح'' ||' || E'\n' ||
    '        COALESCE('' — حتى '' || to_char(' || E'\n' ||
    '          (SELECT o.fms_end AT TIME ZONE ''Asia/Damascus'' FROM public.offers o' || E'\n' ||
    '           WHERE o.id = NULLIF(NEW.meta->>''offer_id'','''')::uuid),' || E'\n' ||
    '          ''YYYY/MM/DD''), '''') ||' || E'\n' ||
    '        ''. سيظهر العرض الخاص بك بقسم المميّزة وبأعلى النتائج.'';' || E'\n' ||
    '    ELSE' || E'\n' ||
    '      v_body := ''تم تفعيل الباقة '' || v_pkg_name || '' بنجاح. استمتع بالمزايا الجديدة!'';' || E'\n' ||
    '    END IF;';

  IF position(v_old_block in v_src) = 0 THEN
    RAISE EXCEPTION 'لم يُعثر على نمط النص المتوقع — أوقف ولا تخمّن';
  END IF;

  v_new := replace(v_src, v_old_block, v_new_block);

  IF v_new = v_src THEN
    RAISE EXCEPTION 'الاستبدال لم يُنتج تغييراً';
  END IF;

  EXECUTE v_new;
  RAISE NOTICE 'تم إصلاح trg_payment_approved';
END $$;

-- ============================================================================
-- ✅ تحققات
-- ============================================================================

-- ① الدالة تفرّع حسب tp  → المتوقع: true
SELECT position('الإعلان المميّز' in pg_get_functiondef(p.oid)) > 0 AS fixed
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'trg_payment_approved';

-- ② التحصين سليم  → المتوقع: secdef=true وsearch_path مثبّت
SELECT p.prosecdef AS secdef, array_to_string(p.proconfig, ',') AS cfg
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'trg_payment_approved';
