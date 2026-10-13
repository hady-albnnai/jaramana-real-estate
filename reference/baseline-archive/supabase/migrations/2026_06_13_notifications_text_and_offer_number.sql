-- ════════════════════════════════════════════════════════════════════════════
-- 1. إصلاح نصوص الإشعارات + إضافة رقم العرض
-- 2026-06-13
-- ════════════════════════════════════════════════════════════════════════════

-- ──────────────────────────────────────
-- 1. عداد العروض — رقم تسلسلي يظهر للجمهور
-- ──────────────────────────────────────
-- إنشاء sequence
CREATE SEQUENCE IF NOT EXISTS offer_number_seq START 1;

-- إضافة عمود رقم العرض
ALTER TABLE offers ADD COLUMN IF NOT EXISTS offer_number INT DEFAULT NULL;

-- تعبئة العروض الموجودة
UPDATE offers SET offer_number = nextval('offer_number_seq')
WHERE offer_number IS NULL;

-- trigger يعبّي الرقم تلقائياً عند الإنشاء
CREATE OR REPLACE FUNCTION set_offer_number()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.offer_number IS NULL THEN
    NEW.offer_number := nextval('offer_number_seq');
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_offer_number ON offers;
CREATE TRIGGER trg_set_offer_number
  BEFORE INSERT ON offers
  FOR EACH ROW EXECUTE FUNCTION set_offer_number();

-- ──────────────────────────────────────
-- 2. إصلاح نصوص الإشعارات
-- ──────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_offer_status_changed()
RETURNS TRIGGER AS $$
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

  INSERT INTO notifications (uid, typ, ttl, bdy, ref_id, ts_crt)
  VALUES (NEW.usr_id, v_type, v_title, v_body, NEW.id, NOW());

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
