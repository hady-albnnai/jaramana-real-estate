-- Fix login crash: Flutter UserModel expects wk_lgn JSON array, not object.
UPDATE public.users
SET wk_lgn='[]'::jsonb,ts_upd=now()
WHERE wk_lgn IS NULL OR jsonb_typeof(wk_lgn)<>'array';
