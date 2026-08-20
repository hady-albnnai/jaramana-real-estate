# =============================================================================
# scripts/analyze_legal_appointments.ps1 - READ-ONLY diagnostics (2026-08-20)
#
# Diagnoses two owner reports:
#   1) duplicate appointments for the same person in My Appointments
#   2) lawyer "My Appointments" tab showing nothing
#
# Runs 8 read-only queries and prints each result as [A-...] lines.
# Usage (same style as deploy_supabase.ps1):
#   powershell -ExecutionPolicy Bypass -File scripts\analyze_legal_appointments.ps1 ^
#       -PAT "sbp_..." -REF "vsgkgnjtebjxyqwpuopz"
# =============================================================================
param(
    [string]$PAT = $env:SUPABASE_PAT,
    [string]$REF = $env:SUPABASE_PROJECT_REF
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($PAT)) { Write-Host '[ERROR] SUPABASE_PAT is required'; exit 1 }
if ([string]::IsNullOrWhiteSpace($REF)) { Write-Host '[ERROR] SUPABASE_PROJECT_REF is required'; exit 1 }

$API = "https://api.supabase.com/v1/projects/$REF"

$QUERIES = @(
  @{ L='lawyers'; S="SELECT u.id, u.nm, u.sts, COALESCE(lp.is_active,false) AS is_active, COALESCE(lp.active_tasks_count,0) AS tasks FROM public.users u LEFT JOIN public.lawyer_profiles lp ON lp.uid=u.id WHERE u.role=7 AND u.i_del=0 ORDER BY u.ts_crt;" },
  @{ L='legal_appts'; S="SELECT a.id, a.consultation_id, a.bkr_id, a.req_uid, a.sts, to_char(a.dt AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI') AS dt_dam, a.cnl_by, left(COALESCE(a.cnl_rsn,''),60) AS cnl_rsn, a.ts_crt FROM public.appointments a WHERE a.kind='legal' ORDER BY a.ts_crt DESC;" },
  @{ L='dup_by_consultation'; S="SELECT consultation_id, count(*) AS n, string_agg(sts::text,',' ORDER BY sts) AS sts_list FROM public.appointments WHERE kind='legal' GROUP BY consultation_id HAVING count(*)>1;" },
  @{ L='consultations'; S="SELECT c.id, c.user_uid, c.lawyer_uid, c.service_type, c.status, c.appointment_id, c.payment_id, c.parent_consultation_id, c.ts_crt FROM public.legal_consultations c WHERE c.i_del=0 ORDER BY c.ts_crt DESC;" },
  @{ L='user_legal_counts'; S="SELECT user_uid, count(*) AS n, string_agg(status::text,',' ORDER BY status) AS sts_list FROM public.legal_consultations WHERE i_del=0 GROUP BY user_uid HAVING count(*)>1;" },
  @{ L='double_payments'; S="SELECT uid, count(*) AS n, string_agg(sts::text,',' ORDER BY sts) AS sts_list FROM public.payments WHERE tp=2 GROUP BY uid, pkg HAVING count(*)>1;" },
  @{ L='neog_legal'; S="SELECT a.id, a.consultation_id, a.sts, COALESCE(jsonb_array_length(COALESCE(a.neog,'[]'::jsonb)),0) AS rounds, left(COALESCE((COALESCE(a.neog,'[]'::jsonb)->-1)::text,''),200) AS last_round FROM public.appointments a WHERE a.kind='legal' AND COALESCE(a.neog,'[]'::jsonb)<>'[]'::jsonb;" },
  @{ L='orphan_appt_refs'; S="SELECT c.id, c.appointment_id, (SELECT count(*) FROM public.appointments a WHERE a.id=c.appointment_id) AS appt_exists FROM public.legal_consultations c WHERE c.i_del=0 AND c.appointment_id IS NOT NULL;" }
)

Write-Host "Legal appointments analysis - read-only"
foreach ($q in $QUERIES) {
    $body = @{ query = $q.S } | ConvertTo-Json -Compress
    $tmp = Join-Path $env:TEMP ("al_" + [guid]::NewGuid().ToString('N') + ".json")
    $out = Join-Path $env:TEMP ("al_" + [guid]::NewGuid().ToString('N') + ".json")
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $code = & curl.exe -sS --max-time 90 -o $out -w "%{http_code}" -X POST "$API/database/query" -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" --data-binary "@$tmp" 2>$null
    $ErrorActionPreference = $prevEAP
    $resp = if (Test-Path $out) { (Get-Content $out -Raw -Encoding UTF8) } else { '""' }
    Write-Host "  [A-$($q.L)] HTTP $code $resp"
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Remove-Item $out -ErrorAction SilentlyContinue
}
Write-Host '[DONE] legal appointments analysis complete.'
