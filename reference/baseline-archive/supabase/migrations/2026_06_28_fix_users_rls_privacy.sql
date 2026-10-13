-- =============================================
-- HOTFIX: إغلاق تسريب بيانات المستخدمين (LOGIC_SPEC §5.2)
-- التاريخ: 2026-06-28
-- =============================================

-- 1. حذف السياسة المفتوحة الخطرة (qual = true)
DROP POLICY IF EXISTS "Users can read own row only" ON public.users;
DROP POLICY IF EXISTS "Allow read via security definer" ON public.users;
DROP POLICY IF EXISTS "users_select_own" ON public.users;

-- 2. إنشاء سياسة آمنة صارمة (المالك فقط)
CREATE POLICY "users_select_own_only" 
ON public.users 
FOR SELECT 
TO authenticated 
USING (auth.uid() = id);

-- ملاحظة: service_role يبقى يرى كل شيء (افتراضي)
-- الـ admin Edge Functions تستخدم service_role داخلياً

-- 3. التأكد من تفعيل RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;