-- ═══════════════════════════════════════════════════════════════════
-- 2026_08_14_lawyer_availability_slots.sql
-- قرار المالك: المحامي يضبط أوقاته سلفاً، والعميل لا يرى إلا ما سمح به.
-- يلغي جولة التفاوض (اقتراح/موافقة) لكل جلسة حضورية.
--
-- الأساس: نفس نمط offers.avl المُجرَّب ({"sun":["09:00-13:00"],...} أو "any")
-- مع appt_booking_config() (gap_mins=60) — لا اختراع نمط جديد.
--
-- الحقائق الحية: lawyer_profiles.avl موجود ومهيأ بالموديل لكنه '{}' ولا
-- يُستخدم في أي منطق. appointments يربط بـ bkr_id/req_uid/dt فتظهر الجلسة
-- تلقائياً بتبويب «مواعيدي» وتستفيد من التذكيرات القائمة (rmnd_24/rmnd_2).
-- ═══════════════════════════════════════════════════════════════════

-- ① حفظ أوقات المحامي (إلزامية قبل استخدام الشاشة)
CREATE OR REPLACE FUNCTION public.set_lawyer_availability_slots(
  p_lawyer_uid uuid, p_avl jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_role INT; v_day TEXT; v_slots JSONB; v_slot TEXT;
  v_valid_days TEXT[] := ARRAY['sun','mon','tue','wed','thu','fri','sat','any'];
  v_count INT := 0;
BEGIN
  SELECT role INTO v_role FROM users WHERE id = p_lawyer_uid AND i_del = 0 AND sts = 0;
  IF v_role IS NULL OR v_role <> 7 THEN
    RETURN jsonb_build_object('success', false, 'error', 'LAWYER_ROLE_REQUIRED');
  END IF;
  IF p_avl IS NULL OR jsonb_typeof(p_avl) <> 'object' THEN
    RETURN jsonb_build_object('success', false, 'error', 'AVL_OBJECT_REQUIRED');
  END IF;

  -- تحقق بنيوي: مفاتيح أيام معروفة + فترات "HH:MM-HH:MM" صحيحة ومنطقية
  FOR v_day, v_slots IN SELECT * FROM jsonb_each(p_avl) LOOP
    IF NOT (v_day = ANY(v_valid_days)) THEN
      RETURN jsonb_build_object('success', false, 'error', 'INVALID_DAY_KEY', 'key', v_day);
    END IF;
    IF jsonb_typeof(v_slots) <> 'array' THEN
      RETURN jsonb_build_object('success', false, 'error', 'SLOTS_MUST_BE_ARRAY', 'key', v_day);
    END IF;
    FOR v_slot IN SELECT jsonb_array_elements_text(v_slots) LOOP
      IF v_slot !~ '^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
        RETURN jsonb_build_object('success', false, 'error', 'INVALID_SLOT_FORMAT', 'slot', v_slot);
      END IF;
      IF split_part(v_slot,'-',1) >= split_part(v_slot,'-',2) THEN
        RETURN jsonb_build_object('success', false, 'error', 'SLOT_END_BEFORE_START', 'slot', v_slot);
      END IF;
      v_count := v_count + 1;
    END LOOP;
  END LOOP;

  IF v_count = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_SLOTS_PROVIDED');
  END IF;

  UPDATE lawyer_profiles SET avl = p_avl, updated_at = NOW() WHERE uid = p_lawyer_uid;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'LAWYER_PROFILE_NOT_FOUND');
  END IF;
  RETURN jsonb_build_object('success', true, 'avl', p_avl, 'slots_count', v_count);
END;
$function$;

REVOKE ALL ON FUNCTION public.set_lawyer_availability_slots(uuid, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.set_lawyer_availability_slots(uuid, jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_lawyer_availability_slots(uuid, jsonb) TO service_role;

-- ② السلوتات الحرة فعلاً = المتاح ناقص المحجوز (على نمط suggest_appointment_slot)
CREATE OR REPLACE FUNCTION public.get_lawyer_free_slots(
  p_lawyer_uid uuid, p_days int DEFAULT 14)
RETURNS TABLE(slot_dt timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_avl JSONB; v_cfg JSONB := public.appt_booking_config();
  v_gap INT; v_date DATE; v_day_key TEXT; v_slots JSONB; v_slot TEXT;
  v_from_m INT; v_to_m INT; v_m INT; v_cand TIMESTAMPTZ; d INT;
BEGIN
  v_gap := GREATEST(15, COALESCE((v_cfg->>'gap_mins')::INT, 60));
  SELECT lp.avl INTO v_avl FROM lawyer_profiles lp
    JOIN users u ON u.id = lp.uid
   WHERE lp.uid = p_lawyer_uid AND lp.is_active = TRUE
     AND u.role = 7 AND u.sts = 0 AND u.i_del = 0;

  IF v_avl IS NULL OR v_avl = '{}'::jsonb OR v_avl = 'null'::jsonb THEN
    RETURN; -- بلا أوقات مضبوطة ⇒ لا سلوتات (تُخفى الحضورية عن العميل)
  END IF;

  FOR d IN 0..GREATEST(0, LEAST(p_days, 30)) - 1 LOOP
    v_date := (NOW() AT TIME ZONE 'Asia/Damascus')::date + d;
    v_day_key := LOWER(to_char(v_date, 'Dy'));

    IF v_avl ? 'any' THEN
      v_slots := jsonb_build_array((v_cfg->>'any_from') || '-' || (v_cfg->>'any_to'));
    ELSE
      v_slots := v_avl -> v_day_key;
    END IF;
    IF v_slots IS NULL OR jsonb_typeof(v_slots) <> 'array' THEN CONTINUE; END IF;

    FOR v_slot IN SELECT jsonb_array_elements_text(v_slots) LOOP
      v_from_m := split_part(split_part(v_slot,'-',1), ':', 1)::INT * 60
                + split_part(split_part(v_slot,'-',1), ':', 2)::INT;
      v_to_m   := split_part(split_part(v_slot,'-',2), ':', 1)::INT * 60
                + split_part(split_part(v_slot,'-',2), ':', 2)::INT;
      v_m := v_from_m;
      WHILE v_m + v_gap <= v_to_m LOOP
        v_cand := ((v_date::text || ' ' || lpad((v_m/60)::text,2,'0') || ':' ||
                    lpad((v_m%60)::text,2,'0'))::timestamp) AT TIME ZONE 'Asia/Damascus';
        -- مستقبلي فقط + غير محجوز (sts 0 بانتظار · 1 مؤكد)
        IF v_cand > NOW() + INTERVAL '2 hours'
           AND NOT EXISTS (
             SELECT 1 FROM appointments a
              WHERE a.bkr_id = p_lawyer_uid
                AND a.sts IN (0, 1)
                AND a.dt < v_cand + make_interval(mins => v_gap)
                AND (a.dt + make_interval(mins => v_gap)) > v_cand
           )
        THEN
          slot_dt := v_cand;
          RETURN NEXT;
        END IF;
        v_m := v_m + v_gap;
      END LOOP;
    END LOOP;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_lawyer_free_slots(uuid, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_lawyer_free_slots(uuid, int) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_lawyer_free_slots(uuid, int) TO service_role;
