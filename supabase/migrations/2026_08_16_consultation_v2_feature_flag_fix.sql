-- 2026-08-16 — تصحيح إنشاء features.consultationFlowV2 عندما يغيب الكائن الوسيط.
UPDATE public.app_config
SET value = jsonb_set(
  value,
  '{features}',
  COALESCE(value->'features','{}'::jsonb) ||
    CASE WHEN value#>'{features,consultationFlowV2}' IS NULL
      THEN '{"consultationFlowV2":false}'::jsonb
      ELSE '{}'::jsonb
    END,
  true
)
WHERE key='main';

DO $verify$
BEGIN
  IF (SELECT value#>>'{features,consultationFlowV2}' FROM public.app_config WHERE key='main') <> 'false' THEN
    RAISE EXCEPTION 'CONSULTATION_V2_FLAG_NOT_FALSE';
  END IF;
END;
$verify$;
