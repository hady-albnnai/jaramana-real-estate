# =============================================================================
# scripts/deploy_supabase.ps1 - Deploy Supabase from Windows (PowerShell)
#
# Steps:
#   1) Live checks (print only): offers/payments triggers + function diffs
#   2) Apply pending SQL migrations (supabase/migrations/2026_08_19_*.sql)
#   3) Delete test user data (consultations/payments/notifications/chats/...)
#   4) Deploy Edge functions: admin-dashboard + legal-actions (POST/PATCH)
#
# NOTE: This file is pure ASCII on purpose - Arabic strings break PowerShell 5.1
# encoding on non-UTF8 consoles. The Arabic test-user name is embedded as base64
# and decoded at runtime, so it always matches regardless of console codepage.
#
# Requirements: Windows 10/11 (built-in curl.exe) + PowerShell 5.1+
# No secrets stored in the repo - everything comes from env/params.
#
# Usage (from cmd or PowerShell):
#   powershell -ExecutionPolicy Bypass -File scripts\deploy_supabase.ps1 ^
#       -PAT "sbp_..." -REF "vsgkgnjtebjxyqwpuopz"
#   (add -SkipMigrations / -SkipCleanup / -SkipFunctions to skip a step)
# =============================================================================
param(
    [string]$PAT = $env:SUPABASE_PAT,
    [string]$REF = $env:SUPABASE_PROJECT_REF,
    [switch]$SkipMigrations,
    [switch]$SkipCleanup,
    [switch]$SkipFunctions
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PAT)) { Write-Host '[ERROR] SUPABASE_PAT is required'; exit 1 }
if ([string]::IsNullOrWhiteSpace($REF)) { Write-Host '[ERROR] SUPABASE_PROJECT_REF is required'; exit 1 }

$API  = "https://api.supabase.com/v1/projects/$REF"
$Root = Split-Path $PSScriptRoot -Parent

# Test user name decoded from base64 (UTF-8, matches the Arabic name exactly)
$TestUserName = [System.Text.Encoding]::UTF8.GetString(
    [System.Convert]::FromBase64String('2YfZhtin2KEg2KfZhNi52YrYs9mF2Yo='))

# -----------------------------------------------------------------------------
function Invoke-Sql {
    param([string]$Label, [string]$Sql, [switch]$Fatal)
    $body = @{ query = $Sql } | ConvertTo-Json -Compress
    $tmp  = Join-Path $env:TEMP ("sq_" + [guid]::NewGuid().ToString('N') + ".json")
    $out  = Join-Path $env:TEMP ("resp_" + [guid]::NewGuid().ToString('N') + ".json")
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))

    $code = & curl.exe -sS --max-time 180 -o $out -w "%{http_code}" -X POST "$API/database/query" `
        -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" `
        --data-binary "@$tmp" 2>$null
    Write-Host "  [$Label] HTTP $code"
    if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8; Write-Host '' }

    Remove-Item $tmp -ErrorAction SilentlyContinue
    Remove-Item $out -ErrorAction SilentlyContinue

    if ($Fatal -and $code -ne '200' -and $code -ne '201') { throw "FAILED: $Label (HTTP $code)" }
}

function Deploy-Fn {
    param([string]$Slug)
    # CORRECT endpoint (from Supabase official docs/discussions):
    #   POST /v1/projects/{ref}/functions/deploy?slug={slug}
    # It creates the function if missing, or UPDATES it if exists -
    # no need to DELETE first. (POST /functions => 500 'toString' error,
    #  POST /functions/{slug} => 404.)
    #
    # FIX 2026-08-19: metadata is sent as a FILE-BACKED form field.
    # Passing it inline via --form-string breaks on PowerShell 5.1
    # (embedded double quotes get mangled when calling native curl.exe),
    # and the API rejects the payload: "Invalid metadata JSON payload".
    $meta = @{ name = $Slug; verify_jwt = $false; entrypoint_path = 'index.ts' } |
        ConvertTo-Json -Compress
    $filePath = Join-Path $Root "supabase\functions\$Slug\index.ts"
    $metaFile = Join-Path $env:TEMP ("meta_" + [guid]::NewGuid().ToString('N') + ".json")
    $out = Join-Path $env:TEMP ("fn_" + [guid]::NewGuid().ToString('N') + ".json")
    [System.IO.File]::WriteAllText($metaFile, $meta, (New-Object System.Text.UTF8Encoding($false)))

    Write-Host "  Deploy $Slug [POST /functions/deploy?slug=]"
    $code = & curl.exe -sS --max-time 300 -o $out -w "%{http_code}" -X POST "$API/functions/deploy?slug=$Slug" `
        -H "Authorization: Bearer $PAT" `
        -F "metadata=@$metaFile;type=application/json" `
        -F "file=@$filePath;type=text/plain" 2>$null
    Write-Host "  HTTP $code"
    if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8; Write-Host '' }

    Remove-Item $metaFile -ErrorAction SilentlyContinue
    Remove-Item $out -ErrorAction SilentlyContinue

    if ($code -ne '200' -and $code -ne '201') { throw "FAILED deploy $Slug (HTTP $code)" }
}

Write-Host "Project: $REF | migrations=$(-not $SkipMigrations) cleanup=$(-not $SkipCleanup) functions=$(-not $SkipFunctions)"

# --- 1) Live checks ----------------------------------------------------------
Write-Host "===== Live checks ====="
Invoke-Sql -Label 'offers triggers' -Sql "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='offers' AND NOT t.tgisinternal;"
Invoke-Sql -Label 'payments triggers' -Sql "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='payments' AND NOT t.tgisinternal;"
Invoke-Sql -Label 'admin_review_offer_internal' -Sql "SELECT pg_get_functiondef('public.admin_review_offer_internal(uuid,uuid,boolean,text)'::regprocedure) LIKE '%30 days%' AS ttl_patched;"
Invoke-Sql -Label 'trg_consultation_payment_v2' -Sql "SELECT pg_get_functiondef('public.trg_consultation_payment_v2()'::regprocedure) LIKE '%v_ref%' AS ref_patched;"
if (-not $SkipCleanup) {
    $qname = "'" + $TestUserName.Replace("'", "''") + "'"
    Invoke-Sql -Label 'find test user' -Sql "SELECT id, nm, usr, role, sts FROM public.users WHERE nm = $qname OR usr = $qname;"
}

# --- 2) Apply pending migrations 2026_08_19/2026_08_20 -----------------------
if (-not $SkipMigrations) {
    Write-Host "===== Apply migrations 2026_08_19 + 2026_08_20 ====="
    Get-ChildItem (Join-Path $Root 'supabase\migrations') |
        Where-Object { $_.Name -like '2026_08_19_*.sql' -or $_.Name -like '2026_08_20_*.sql' } |
        Sort-Object Name |
        ForEach-Object {
            Write-Host "  >> $($_.Name)"
            $sql = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
            Invoke-Sql -Label $_.Name -Sql $sql -Fatal
        }
}

# --- 3) Cleanup test user ----------------------------------------------------
if (-not $SkipCleanup) {
    Write-Host "===== Cleanup test user ====="
    $cleanupPath = Join-Path $Root 'scripts\cleanup_test_user.sql'
    $sql = [System.IO.File]::ReadAllText($cleanupPath, [System.Text.Encoding]::UTF8)
    $sql = $sql.Replace('__TEST_USER_NAME__', $TestUserName)
    Invoke-Sql -Label 'cleanup test user' -Sql $sql -Fatal
}

# --- 4) Deploy Edge functions -------------------------------------------------
if (-not $SkipFunctions) {
    Write-Host "===== Deploy Edge functions ====="
    Deploy-Fn 'admin-dashboard'
    Deploy-Fn 'legal-actions'
    # 🩹 2026-08-20: شارة المدفوعات تحتاج أكشن mark_read_by_act في user-notifications
    Deploy-Fn 'user-notifications'
    # 🏢 2026-08-20: عنوان المكتب (update_sections) + فلو الاعتذار الموحد
    Deploy-Fn 'admin-config'
    # 🛡️ دين 1 (2026-08-20): توقيع رفع إثبات الدفع (إقفال فتحة الإغراق)
    Deploy-Fn 'user-account'
}

Write-Host '[DONE] All steps completed successfully.'
