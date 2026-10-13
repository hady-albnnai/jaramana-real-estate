-- ════════════════════════════════════════════════════════════════════════════
-- 1. تحديث المناطق الرئيسية بالـ Config
-- 2. إضافة أنواع سندات السيارة بالـ Config
-- ════════════════════════════════════════════════════════════════════════════

-- المناطق الرئيسية (المفتاح موجود — يُستبدل)
UPDATE app_config
SET value = jsonb_set(value, '{locs}',
  '["السويداء","صلخد","شهبا"]'::jsonb)
WHERE key = 'main';

-- أنواع سند ملكية السيارة (مفتاح جديد — create_if_missing = true)
UPDATE app_config
SET value = jsonb_set(value, '{carDocTp}',
  '{"0":"مواصلات نظامي","1":"حكم محكمة","2":"وارد مع تسلسل ملكية حصراً"}'::jsonb,
  true)
WHERE key = 'main';

-- أنواع النمرة (مفتاح جديد — create_if_missing = true)
UPDATE app_config
SET value = jsonb_set(value, '{plateTp}',
  '{"0":"نمرة قديمة","1":"نمرة جديدة","2":"وارد مع تسلسل ملكية حصراً"}'::jsonb,
  true)
WHERE key = 'main';
