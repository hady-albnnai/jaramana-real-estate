-- ════════════════════════════════════════════════════════════════════════════
-- Config defaults: package prices + FX rate
-- Date: 2026-06-10
-- Purpose:
--   - move package prices to config.pkg.*.pr
--   - move USD/SYP exchange rate to config.fx.usd_syp
-- ════════════════════════════════════════════════════════════════════════════

UPDATE app_config
SET value = jsonb_set(
              jsonb_set(
                jsonb_set(
                  jsonb_set(
                    COALESCE(value, '{}'::jsonb),
                    '{pkg,0,pr}', '0'::jsonb, true
                  ),
                  '{pkg,1,pr}', '10'::jsonb, true
                ),
                '{pkg,2,pr}', '25'::jsonb, true
              ),
              '{fx,usd_syp}', '15000'::jsonb, true
            )
WHERE key = 'main';
