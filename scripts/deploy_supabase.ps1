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
    # PATCH on an existing function sometimes fails with HTTP 500
    # ("Cannot read 'toString' of undefined") - likely caused by
    # import_map_path:null in the metadata. Reliable fix: DELETE then POST.
    $exists = & curl.exe -sS -o NUL -w "%{http_code}" --max-time 60 "$API/functions/$Slug" -H "Authorization: Bearer $PAT" 2>$null
    if ($exists -eq '200') {
        Write-Host "  Delete $Slug (re-create cleanly)"
        $del = & curl.exe -sS -o NUL -w "%{http_code}" --max-time 60 -X DELETE "$API/functions/$Slug" -H "Authorization: Bearer $PAT" 2>$null
        Write-Host "  DELETE HTTP $del"
        if ($del -ne '200' -and $del -ne '204') { throw "FAILED delete $Slug (HTTP $del)" }
        Start-Sleep -Seconds 2
    }
    # Without import_map_path - its null value was breaking the management API
    $meta = @{ name = $Slug; verify_jwt = $false; entrypoint_path = 'index.ts' } |
        ConvertTo-Json -Compress
    $metaTmp = Join-Path $env:TEMP ("meta_" + [guid]::NewGuid().ToString('N') + ".json")
    [System.IO.File]::WriteAllText($metaTmp, $meta, (New-Object System.Text.UTF8Encoding($false)))
    $filePath = Join-Path $Root "supabase\functions\$Slug\index.ts"
    $out = Join-Path $env:TEMP ("fn_" + [guid]::NewGuid().ToString('N') + ".json")

    Write-Host "  Create $Slug [POST]"
    # IMPORTANT: create endpoint is /functions (no slug) - slug is only for
    # GET/PATCH/DELETE. POST to /functions/<slug> returns 404.
    $code = & curl.exe -sS --max-time 300 -o $out -w "%{http_code}" -X POST "$API/functions" `
        -H "Authorization: Bearer $PAT" `
        -F "metadata=@$metaTmp;type=application/json" `
        -F "file=@$filePath;type=text/plain" 2>$null
    Write-Host "  HTTP $code"
    if (Test-Path $out) { Get-Content $out -Raw -Encoding UTF8; Write-Host '' }

    Remove-Item $metaTmp -ErrorAction SilentlyContinue
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

# --- 2) Apply pending migrations 2026_08_19 ----------------------------------
if (-not $SkipMigrations) {
    Write-Host "===== Apply migrations 2026_08_19 ====="
    Get-ChildItem (Join-Path $Root 'supabase\migrations') -Filter '2026_08_19_*.sql' |
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
}

Write-Host '[DONE] All steps completed successfully.'
