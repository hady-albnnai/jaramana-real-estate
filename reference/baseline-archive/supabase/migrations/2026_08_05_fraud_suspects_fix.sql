-- ============================================================================
-- 🔒 إصلاح كشف الاحتيال - خطأ 502 (Bug #32)
-- ============================================================================
--
-- المشكلة: كشف الاحتيال يعطي خطأ 502 Bad Gateway
-- السبب: VIEW fraud_suspects يستخدم security_invoker = true
--        Edge Function يستدعي RPC باستخدام service_role
--        VIEW يمنح SELECT فقط لـ authenticated
--
-- الحل: منح SELECT لـ service_role أيضاً
-- ============================================================================

-- إعادة إنشاء VIEW مع صلاحيات صحيحة
DROP VIEW IF EXISTS fraud_suspects;

CREATE VIEW fraud_suspects AS
SELECT
  device_id,
  COUNT(*) AS account_count,
  ARRAY_AGG(id) AS user_ids,
  ARRAY_AGG(nm) AS names,
  MIN(ts_crt) AS first_signup,
  MAX(ts_crt) AS last_signup
FROM users
WHERE device_id IS NOT NULL AND i_del = 0
GROUP BY device_id
HAVING COUNT(*) > 1;

-- منح الصلاحيات
ALTER VIEW fraud_suspects SET (security_invoker = true);
GRANT SELECT ON fraud_suspects TO authenticated;
GRANT SELECT ON fraud_suspects TO service_role;  -- ✅ إضافة service_role

-- تحصين الـ RPC
REVOKE ALL ON FUNCTION admin_fraud_suspects(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION admin_fraud_suspects(UUID) TO service_role;
