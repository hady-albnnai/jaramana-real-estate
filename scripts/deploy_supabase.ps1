# ══════════════════════════════════════════════════════════════════════
# scripts/deploy_supabase.ps1 — نشر Supabase تلقائياً من ويندوز (PowerShell)
#
# يقوم بـ:
#   1) تحقق حي (طباعة فقط): تريغرات offers/payments + مقارنة الدوال بالسيرفر
#   2) تطبيق تعديلات SQL المعلّقة (supabase/migrations/2026_08_19_*.sql)
#   3) حذف بيانات مستخدم الاختبار (استشارات/دفعات/إشعارات/محادثات/مواعيد)
#   4) نشر دوال Edge: admin-dashboard + legal-actions (POST/PATCH)
#
# المتطلبات: ويندوز 10/11 (curl.exe مدمج) + PowerShell 5.1 أو أحدث.
# لا يخزّن أي سر داخل الريبو — كل شيء من متغيرات البيئة/وسائط.
#
# الاستخدام (PowerShell):
#   $env:SUPABASE_PAT  = 'sbp_...'
#   $env:SUPABASE_PROJECT_REF = 'vsgkgnjtebjxyqwpuopz'
#   .\scripts\deploy_supabase.ps1 -TestUserName 'هناء العيسمي'
#   (أضف -SkipMigrations أو -SkipCleanup أو -SkipFunctions لإيقاف خطوة)
# ══════════════════════════════════════════════════════════════════════
param(
    [string]$PAT = $env:SUPABASE_PAT,
    [string]$REF = $env:SUPABASE_PROJECT_REF,
    [switch]$SkipMigrations,
    [switch]$SkipCleanup,
    [switch]$SkipFunctions,
    [string]$TestUserName = 'هناء العيسمي'
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PAT)) { Write-Host '❌ SUPABASE_PAT مطلوب (متغير بيئة أو وسيط)'; exit 1 }
if ([string]::IsNullOrWhiteSpace($REF)) { Write-Host '❌ SUPABASE_PROJECT_REF مطلوب'; exit 1 }

$API  = "https://api.supabase.com/v1/projects/$REF"
$Root = Split-Path $PSScriptRoot -Parent   # جذر الريبو (scripts/..)

# ── تنفيذ استعلام SQL على Management API وإظهار النتيجة ──
function Invoke-Sql {
    param([string]$Label, [string]$Sql, [switch]$Fatal)
    $body = @{ query = $Sql } | ConvertTo-Json -Compress
    $tmp  = Join-Path $env:TEMP ("sq_" + [guid]::NewGuid().ToString('N') + ".json")
    $out  = Join-Path $env:TEMP ("resp_" + [guid]::NewGuid().ToString('N') + ".json")
    # UTF-8 بلا BOM — ضروري للنصوص العربية
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))

    $code = & curl.exe -sS --max-time 180 -o $out -w "%{http_code}" -X POST "$API/database/query" `
        -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" `
        --data-binary "@$tmp" 2>$null
    Write-Host "── [$Label] HTTP $code"
    if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8; Write-Host '' }

    Remove-Item $tmp -ErrorAction SilentlyContinue
    Remove-Item $out -ErrorAction SilentlyContinue

    if ($Fatal -and $code -ne '200') { throw "فشل: $Label (HTTP $code)" }
}

# ── نشر دالة Edge (POST إن لم توجد / PATCH إن وُجدت) ──
function Deploy-Fn {
    param([string]$Slug)
    $exists = & curl.exe -sS -o NUL -w "%{http_code}" --max-time 60 "$API/functions/$Slug" -H "Authorization: Bearer $PAT" 2>$null
    $method = if ($exists -eq '200') { 'PATCH' } else { 'POST' }
    $meta = @{ name = $Slug; verify_jwt = $false; entrypoint_path = 'index.ts'; import_map_path = $null } |
        ConvertTo-Json -Compress
    $metaTmp = Join-Path $env:TEMP ("meta_" + [guid]::NewGuid().ToString('N') + ".json")
    [System.IO.File]::WriteAllText($metaTmp, $meta, (New-Object System.Text.UTF8Encoding($false)))
    $filePath = Join-Path $Root "supabase\functions\$Slug\index.ts"
    $out = Join-Path $env:TEMP ("fn_" + [guid]::NewGuid().ToString('N') + ".json")

    Write-Host "── $Slug [$method]"
    $code = & curl.exe -sS --max-time 300 -o $out -w "%{http_code}" -X $method "$API/functions/$Slug" `
        -H "Authorization: Bearer $PAT" `
        -F "metadata=@$metaTmp;type=application/json" `
        -F "file=@$filePath;type=text/plain" 2>$null
    Write-Host "HTTP $code"
    if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8; Write-Host '' }

    Remove-Item $metaTmp -ErrorAction SilentlyContinue
    Remove-Item $out -ErrorAction SilentlyContinue

    if ($code -ne '200' -and $code -ne '201') { throw "فشل نشر $Slug (HTTP $code)" }
}

Write-Host "▶ المشروع: $REF | migrations=$(-not $SkipMigrations) | cleanup=$(-not $SkipCleanup) | functions=$(-not $SkipFunctions)"

# ── 1) التحقق الحي (طباعة فقط) ──
Write-Host "══════════ التحقق الحي قبل التعديل ══════════"
Invoke-Sql -Label 'تريغرات offers' -Sql "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='offers' AND NOT t.tgisinternal;"
Invoke-Sql -Label 'تريغرات payments' -Sql "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='payments' AND NOT t.tgisinternal;"
Invoke-Sql -Label 'حالة admin_review_offer_internal' -Sql "SELECT pg_get_functiondef('public.admin_review_offer_internal(uuid,uuid,boolean,text)'::regprocedure) LIKE '%ونشره%' AS title_patched, pg_get_functiondef('public.admin_review_offer_internal(uuid,uuid,boolean,text)'::regprocedure) LIKE '%30 days%' AS ttl_patched;"
Invoke-Sql -Label 'حالة trg_consultation_payment_v2' -Sql "SELECT pg_get_functiondef('public.trg_consultation_payment_v2()'::regprocedure) LIKE '%v_ref%' AS ref_patched;"
if (-not $SkipCleanup -and -not [string]::IsNullOrWhiteSpace($TestUserName)) {
    Invoke-Sql -Label "مستخدم الاختبار" -Sql "SELECT id, nm, usr, role, sts FROM public.users WHERE nm ILIKE '%$TestUserName%' OR usr ILIKE '%$TestUserName%';"
}

# ── 2) تطبيق تعديلات قاعدة البيانات المعلّقة (2026_08_19) ──
if (-not $SkipMigrations) {
    Write-Host "══════════ تطبيق التعديلات 2026_08_19 ══════════"
    Get-ChildItem (Join-Path $Root 'supabase\migrations') -Filter '2026_08_19_*.sql' |
        Sort-Object Name |
        ForEach-Object {
            Write-Host "▶ $($_.Name)"
            $sql = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
            Invoke-Sql -Label $_.Name -Sql $sql -Fatal
        }
}

# ── 3) حذف بيانات مستخدم الاختبار (إن طُلب) ──
if (-not $SkipCleanup) {
    if ([string]::IsNullOrWhiteSpace($TestUserName)) { throw 'CLEANUP مفعّل بلا TEST_USER_NAME' }
    Write-Host "══════════ حذف بيانات مستخدم الاختبار: $TestUserName ══════════"
    $cleanupPath = Join-Path $Root 'scripts\cleanup_test_user.sql'
    $sql = [System.IO.File]::ReadAllText($cleanupPath, [System.Text.Encoding]::UTF8)
    $sql = $sql.Replace('__TEST_USER_NAME__', $TestUserName)
    Invoke-Sql -Label "تنظيف $TestUserName" -Sql $sql -Fatal
}

# ── 4) نشر دوال Edge ──
if (-not $SkipFunctions) {
    Write-Host "══════════ نشر دوال Edge ══════════"
    Deploy-Fn 'admin-dashboard'
    Deploy-Fn 'legal-actions'
}

Write-Host '✅ تمت العملية بنجاح'
