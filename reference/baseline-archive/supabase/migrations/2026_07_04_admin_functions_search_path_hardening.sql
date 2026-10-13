-- =====================================================================
-- Migration: 2026_07_04_admin_functions_search_path_hardening.sql
--
-- الغرض:
-- إزالة تحذير أمان Postgres المتبقي المتعلق بـ SECURITY DEFINER functions
-- التي تفتقر إلى ضبط search_path. هذا التحذير نشأ في migration سابق
-- (2026_07_02_admin_audit_logging_and_rbac_hardening.sql) حيث وُضع
-- SET search_path على الدالة الموحّدة log_admin_action فقط، وأُغفل عن
-- أربع دوال إدارية تستدعي داخليًا رموزًا غير مُؤهّلة (unqualified) مثل
-- gen_random_uuid / crypt عبر امتداد extensions، واستدعاءات auth.* و
-- public.* المُؤهّلة صراحةً.
--
-- القرار (Fix-forward، لا يُعدّل migration سابقًا):
-- لا نُعدّل ملف 2026_07_02 المُطبّق مسبقًا لتجنّب كسر checksum الترحيل
-- في supabase_migrations؛ بل نُضيف هنا ضبط search_path عبر ALTER FUNCTION
-- وهو أمر idempotent (آمن عند إعادة التشغيل). يضمن هذا أن تُعاد قراءة
-- الكتالوج بشكل آمن وأن مسار البحث محصور في: public, extensions, pg_temp.
--
-- القيمة المعتمدة لـ search_path (موافقة لأحدث اتفاقية في المستودع،
-- راجع 2026_06-15_staff_sessions_security.sql و2026_07_02):
--   SET search_path TO public, extensions, pg_temp
--
-- ملاحظة أمنية: هذه الدوال تبقى SECURITY DEFINER (ضرورية لصلاحياتها
-- الإدارية)، لكن حصر search_path يمنع هجمات schema hijacking. الصلاحيات
-- تبقى مُقيّدة إلى service_role فقط (REVOKE من PUBLIC/anon/authenticated).
-- =====================================================================

-- 1. مراجعة العروض العقارية: الرتبة 4 فما فوق
ALTER FUNCTION public.admin_review_offer_internal(UUID, UUID, BOOLEAN, TEXT)
  SET search_path TO public, extensions, pg_temp;

-- 2. اعتماد توثيق الهوية: الرتبة 4 فما فوق
ALTER FUNCTION public.admin_approve_verification_by_admin(UUID, UUID)
  SET search_path TO public, extensions, pg_temp;

-- 3. رفض توثيق الهوية: الرتبة 4 فما فوق + إلزامية السبب
ALTER FUNCTION public.admin_reject_verification_by_admin(UUID, UUID, TEXT)
  SET search_path TO public, extensions, pg_temp;

-- 4. رفض إيصال التحويل البنكي: الرتبة 5 فما فوق
ALTER FUNCTION public.admin_reject_payment_internal(UUID, UUID)
  SET search_path TO public, extensions, pg_temp;
