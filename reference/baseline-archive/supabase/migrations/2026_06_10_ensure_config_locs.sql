-- Ensure app_config.main has locs key for QA/config completeness.
UPDATE app_config
SET value = jsonb_set(
  value,
  '{locs}',
  COALESCE(value->'locs', '[]'::jsonb),
  true
)
WHERE key = 'main'
  AND NOT (value ? 'locs');
