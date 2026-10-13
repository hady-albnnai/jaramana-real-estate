-- ══════════════════════════════════════════════════════════════════════
-- Migration: Database Linter Security Hardening
-- Date: 2026-06-17
-- Purpose:
--   Fix Supabase database linter findings addressed manually on production:
--   - security_definer_view on users_public
--   - function_search_path_mutable for public functions
--   - permissive RLS policies on otp_codes and user_devices
--   - public bucket broad listing policies on public buckets
--   - unsafe direct EXECUTE grants on legacy OTP and staff/wipe RPCs
--
-- Notes:
--   This file mirrors applied production fixes so the repository reference
--   matches the live server state.
-- ══════════════════════════════════════════════════════════════════════

-- 1) users_public view must run with invoker privileges.
ALTER VIEW public.users_public SET (security_invoker = true);

-- 2) OTP table: OTP rows must be created by Edge Functions/service_role only.
DROP POLICY IF EXISTS "Authenticated can generate OTP" ON public.otp_codes;
DROP POLICY IF EXISTS "otp_codes_service_role_only_insert" ON public.otp_codes;
CREATE POLICY "otp_codes_service_role_only_insert"
ON public.otp_codes
FOR INSERT
TO service_role
WITH CHECK (true);

-- 3) user_devices: restrict direct table access to own devices or service_role.
DROP POLICY IF EXISTS "Users manage own devices" ON public.user_devices;
DROP POLICY IF EXISTS "user_devices_select_own_or_service" ON public.user_devices;
DROP POLICY IF EXISTS "user_devices_insert_own_or_service" ON public.user_devices;
DROP POLICY IF EXISTS "user_devices_update_own_or_service" ON public.user_devices;
DROP POLICY IF EXISTS "user_devices_delete_own_or_service" ON public.user_devices;

CREATE POLICY "user_devices_select_own_or_service"
ON public.user_devices
FOR SELECT
TO authenticated, service_role
USING (uid = auth.uid() OR auth.role() = 'service_role');

CREATE POLICY "user_devices_insert_own_or_service"
ON public.user_devices
FOR INSERT
TO authenticated, service_role
WITH CHECK (uid = auth.uid() OR auth.role() = 'service_role');

CREATE POLICY "user_devices_update_own_or_service"
ON public.user_devices
FOR UPDATE
TO authenticated, service_role
USING (uid = auth.uid() OR auth.role() = 'service_role')
WITH CHECK (uid = auth.uid() OR auth.role() = 'service_role');

CREATE POLICY "user_devices_delete_own_or_service"
ON public.user_devices
FOR DELETE
TO authenticated, service_role
USING (uid = auth.uid() OR auth.role() = 'service_role');

-- 4) Public buckets do not need broad SELECT policies for public URL access.
--    Removing broad SELECT prevents bucket listing while public object URLs keep working.
DROP POLICY IF EXISTS "config_assets_public_read" ON storage.objects;
DROP POLICY IF EXISTS "offer_images_public_read" ON storage.objects;

-- 5) Lock legacy/direct OTP RPCs. SMS must flow through send-sms-otp/verify-sms-otp Edge Functions.
REVOKE ALL ON FUNCTION public.generate_otp(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_otp(text) FROM anon;
REVOKE ALL ON FUNCTION public.generate_otp(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.generate_otp(text) TO service_role;

REVOKE ALL ON FUNCTION public.verify_otp(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_otp(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.verify_otp(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.verify_otp(text, text) TO service_role;

REVOKE ALL ON FUNCTION public.create_user_from_phone(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_user_from_phone(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.create_user_from_phone(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.create_user_from_phone(text, text) TO service_role;

-- v2 OTP/upsert functions were already locked; keep the desired state here.
REVOKE ALL ON FUNCTION public.generate_otp_v2(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.generate_otp_v2(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.generate_otp_v2(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.generate_otp_v2(text, text) TO service_role;

REVOKE ALL ON FUNCTION public.verify_otp_v2(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_otp_v2(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.verify_otp_v2(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.verify_otp_v2(text, text) TO service_role;

REVOKE ALL ON FUNCTION public.upsert_user_after_otp(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.upsert_user_after_otp(text, text) FROM anon;
REVOKE ALL ON FUNCTION public.upsert_user_after_otp(text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.upsert_user_after_otp(text, text) TO service_role;

-- 6) Staff creation RPCs are Edge Function/service_role only.
REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer) TO service_role;

REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_staff_user(uuid, text, text, text, text, text, integer, text, text, text) TO service_role;

-- 7) Wipe/test-data RPC must never be callable directly by client roles.
REVOKE ALL ON FUNCTION public.admin_wipe_test_data(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_wipe_test_data(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_wipe_test_data(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_wipe_test_data(uuid) TO service_role;


-- 9) Points RPCs: direct client-side point grants are unsafe because callers can pass uid/event/points.
--    Point awards must be moved to verified server-side triggers/Edge Functions.
REVOKE ALL ON FUNCTION public.add_points(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.add_points(uuid, integer) FROM anon;
REVOKE ALL ON FUNCTION public.add_points(uuid, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.add_points(uuid, integer) TO service_role;

REVOKE ALL ON FUNCTION public.award_points_safe(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.award_points_safe(uuid, text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.award_points_safe(uuid, text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.award_points_safe(uuid, text, integer) TO service_role;


-- 10) Notification RPCs: direct client-side notification/push creation is unsafe.
--     Notifications must be generated by trusted server-side events or Edge Functions.
REVOKE ALL ON FUNCTION public.notify_user(uuid, integer, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_user(uuid, integer, text, text, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.notify_user(uuid, integer, text, text, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.notify_user(uuid, integer, text, text, text, text) TO service_role;

REVOKE ALL ON FUNCTION public.send_push_notification(uuid, text, text, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_push_notification(uuid, text, text, jsonb) FROM anon;
REVOKE ALL ON FUNCTION public.send_push_notification(uuid, text, text, jsonb) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.send_push_notification(uuid, text, text, jsonb) TO service_role;


-- 11) Internal trigger/helper/legacy helper RPCs locked after linter review.
REVOKE ALL ON FUNCTION public.trg_appointment_created() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_appointment_created() FROM anon;
REVOKE ALL ON FUNCTION public.trg_appointment_created() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trg_appointment_created() TO service_role;

REVOKE ALL ON FUNCTION public.trg_appointment_status_changed() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_appointment_status_changed() FROM anon;
REVOKE ALL ON FUNCTION public.trg_appointment_status_changed() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trg_appointment_status_changed() TO service_role;

REVOKE ALL ON FUNCTION public.trg_deal_completed() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_deal_completed() FROM anon;
REVOKE ALL ON FUNCTION public.trg_deal_completed() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trg_deal_completed() TO service_role;

REVOKE ALL ON FUNCTION public.trg_offer_published_match_requests() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_offer_published_match_requests() FROM anon;
REVOKE ALL ON FUNCTION public.trg_offer_published_match_requests() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offer_published_match_requests() TO service_role;

REVOKE ALL ON FUNCTION public.trg_offer_status_changed() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_offer_status_changed() FROM anon;
REVOKE ALL ON FUNCTION public.trg_offer_status_changed() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trg_offer_status_changed() TO service_role;

REVOKE ALL ON FUNCTION public.trg_payment_approved() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_payment_approved() FROM anon;
REVOKE ALL ON FUNCTION public.trg_payment_approved() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trg_payment_approved() TO service_role;

REVOKE ALL ON FUNCTION public.trg_rating_bonus() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.trg_rating_bonus() FROM anon;
REVOKE ALL ON FUNCTION public.trg_rating_bonus() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.trg_rating_bonus() TO service_role;

REVOKE ALL ON FUNCTION public.check_offer_safe_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_offer_safe_update() FROM anon;
REVOKE ALL ON FUNCTION public.check_offer_safe_update() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_offer_safe_update() TO service_role;

REVOKE ALL ON FUNCTION public.check_user_safe_insert() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_user_safe_insert() FROM anon;
REVOKE ALL ON FUNCTION public.check_user_safe_insert() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_user_safe_insert() TO service_role;

REVOKE ALL ON FUNCTION public.check_user_safe_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_user_safe_update() FROM anon;
REVOKE ALL ON FUNCTION public.check_user_safe_update() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_user_safe_update() TO service_role;

REVOKE ALL ON FUNCTION public.check_rating_valid() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_rating_valid() FROM anon;
REVOKE ALL ON FUNCTION public.check_rating_valid() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_rating_valid() TO service_role;

REVOKE ALL ON FUNCTION public.expire_offer_boosts() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_offer_boosts() FROM anon;
REVOKE ALL ON FUNCTION public.expire_offer_boosts() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.expire_offer_boosts() TO service_role;

REVOKE ALL ON FUNCTION public.expire_packages() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.expire_packages() FROM anon;
REVOKE ALL ON FUNCTION public.expire_packages() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.expire_packages() TO service_role;

REVOKE ALL ON FUNCTION public.accounts_on_same_device(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.accounts_on_same_device(text) FROM anon;
REVOKE ALL ON FUNCTION public.accounts_on_same_device(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.accounts_on_same_device(text) TO service_role;

REVOKE ALL ON FUNCTION public.get_user_by_email(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_by_email(text) FROM anon;
REVOKE ALL ON FUNCTION public.get_user_by_email(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_by_email(text) TO service_role;

REVOKE ALL ON FUNCTION public.get_user_by_phone(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_user_by_phone(text) FROM anon;
REVOKE ALL ON FUNCTION public.get_user_by_phone(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_by_phone(text) TO service_role;

REVOKE ALL ON FUNCTION public.calculate_commission(numeric, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.calculate_commission(numeric, numeric) FROM anon;
REVOKE ALL ON FUNCTION public.calculate_commission(numeric, numeric) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_commission(numeric, numeric) TO service_role;

REVOKE ALL ON FUNCTION public.get_pending_offers_count() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_pending_offers_count() FROM anon;
REVOKE ALL ON FUNCTION public.get_pending_offers_count() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_pending_offers_count() TO service_role;

REVOKE ALL ON FUNCTION public.send_appointment_reminders() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_appointment_reminders() FROM anon;
REVOKE ALL ON FUNCTION public.send_appointment_reminders() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.send_appointment_reminders() TO service_role;

REVOKE ALL ON FUNCTION public.send_renewal_reminders() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.send_renewal_reminders() FROM anon;
REVOKE ALL ON FUNCTION public.send_renewal_reminders() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.send_renewal_reminders() TO service_role;

REVOKE ALL ON FUNCTION public.admin_get_id_signed_path(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_get_id_signed_path(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.admin_get_id_signed_path(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_id_signed_path(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.apply_referral(uuid, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_referral(uuid, text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.apply_referral(uuid, text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.apply_referral(uuid, text, integer) TO service_role;

REVOKE ALL ON FUNCTION public.get_available_supervisor(timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_available_supervisor(timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.get_available_supervisor(timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.get_available_supervisor(timestamptz) TO service_role;

REVOKE ALL ON FUNCTION public.update_user_badge(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_user_badge(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.update_user_badge(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.update_user_badge(uuid) TO service_role;

REVOKE ALL ON FUNCTION public.register_weekly_login(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.register_weekly_login(uuid, integer) FROM anon;
REVOKE ALL ON FUNCTION public.register_weekly_login(uuid, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.register_weekly_login(uuid, integer) TO service_role;

-- 8) Set fixed search_path on all known public functions to satisfy linter 0011.
--    ALTER FUNCTION does not change function bodies; it only sets execution config.
ALTER FUNCTION public.expire_offer_boosts() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_device_tokens(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_broker_offers_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.verify_otp(text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_by_phone(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.calculate_commission(numeric, numeric) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.send_appointment_reminders() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_pending_offers_count() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.generate_otp(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.expire_offers() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.soft_delete(text, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_by_email(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_user_stats_on_offer() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_user_stats_on_request() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_user_stats_on_appointment() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_user_stats_on_deal() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.register_weekly_login(uuid, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.notify_user(uuid, integer, text, text, text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.send_push_notification(uuid, text, text, jsonb) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.trg_deal_completed() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.trg_payment_approved() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.trg_offer_published_match_requests() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_wipe_test_data(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.award_points_safe(uuid, text, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.trg_rating_bonus() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.add_points(uuid, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_user_badge(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.check_user_safe_update() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.check_offer_safe_update() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.check_rating_valid() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.check_user_safe_insert() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.check_offer_duplicate(text, numeric, jsonb, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.accounts_on_same_device(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_broker_appointments_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_broker_deals_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.apply_referral(uuid, text, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.register_device(text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_get_id_signed_path(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.normalize_sy_phone(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.create_user_from_phone(text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.submit_photography_task_internal(uuid, uuid, jsonb, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.request_verification_by_uid(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_appointments_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_owner_appointments_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_offer_by_id_internal(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_offers_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_requests_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_payments_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_notifications_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.soft_delete_request_internal(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.create_report_internal(uuid, jsonb) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.cancel_appointment_internal(uuid, uuid, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.broker_handle_appointment_internal(uuid, uuid, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.mark_notification_read_internal(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.mark_all_notifications_read_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.create_rating_internal(uuid, uuid, integer, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_user_notification_settings_internal(uuid, jsonb) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.submit_broker_request_internal(uuid, text, integer, text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.increment_offer_views_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.owner_respond_appointment(uuid, uuid, boolean, integer, text, timestamptz) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.requester_counter_appointment(uuid, uuid, boolean, timestamptz) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.trg_appointment_created() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.trg_appointment_status_changed() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.register_daily_streak_internal(uuid, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.purchase_offer_boost(uuid, uuid, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.create_payment_internal(uuid, jsonb) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.expire_packages() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.send_renewal_reminders() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_my_tasks(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_postponed_tasks(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_completed_tasks(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_task_outcome(uuid, uuid, text, text, text, timestamptz) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_all_pending_completion_requests(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_admin_appointments_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_admin_pending_offers_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_admin_offers_internal(uuid, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_admin_deals_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_admin_payments_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_update_user_permissions_by_admin(uuid, uuid, jsonb) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_admin_reports_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_admin_requests_internal(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_review_offer_internal(uuid, uuid, boolean, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_update_appointment_status_internal(uuid, uuid, integer, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_reject_payment_internal(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_available_supervisor(timestamptz) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.create_photography_task_internal(uuid, uuid, uuid, text, timestamptz) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.update_photography_task_status_internal(uuid, uuid, integer, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.attach_photography_media_to_offer_internal(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.approve_payment_final(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.book_appointment_internal(uuid, uuid, timestamptz, uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.create_deal_internal(uuid, jsonb) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.complete_deal_internal(uuid, uuid, numeric, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_force_appointment_internal(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.change_password_internal(uuid, text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_handle_report_internal(uuid, uuid, integer, text, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.mark_social_published_internal(uuid, uuid, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.check_username_available(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.set_offer_number() SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.process_completion_request(uuid, uuid, text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.request_completion_by_appointment(uuid, uuid, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.reset_password_with_otp(uuid, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.get_user_full_by_id(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.app_assert_password(text, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.app_assert_phone(text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.app_assert_price(numeric, boolean) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.app_assert_text_len(text, text, integer, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.app_assert_username(text, boolean) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.app_clean_text(text, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_fraud_suspects(uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_set_offer_priority_internal(uuid, uuid, text, integer) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.upsert_user_after_otp(text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.verify_otp_v2(text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.generate_otp_v2(text, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_approve_verification_by_admin(uuid, uuid) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.admin_reject_verification_by_admin(uuid, uuid, text) SET search_path = public, extensions, pg_temp;
ALTER FUNCTION public.trg_offer_status_changed() SET search_path = public, extensions, pg_temp;
