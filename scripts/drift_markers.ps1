# =============================================================================
# scripts/drift_markers.ps1 - fast read-only drift probes (2026-08-20)
#
# Runs 8 small scalar queries to capture the last missing pieces for
# closing debts 2 and 5:
#   - live definition of trg_offers_shield_doc_img (does it use doc_img_admin?)
#   - definitions of the 2 live functions missing from the repo
#     (lawyer_alias_for, update_lawyer_active_tasks)
#   - offer_documents table columns + row count + orphan doc check
#   - all deployment markers (scalar version - type-safe and fast)
#
# Usage (same style as deploy_supabase.ps1):
#   powershell -ExecutionPolicy Bypass -File scripts\drift_markers.ps1 ^
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
  @{ L='shield_def'; S="SELECT COALESCE(left(pg_get_functiondef(oid),700),'missing') FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='trg_offers_shield_doc_img';" },
  @{ L='lawyer_alias_for_def'; S="SELECT COALESCE(left(pg_get_functiondef(oid),1600),'missing') FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='lawyer_alias_for';" },
  @{ L='update_lawyer_active_tasks_def'; S="SELECT COALESCE(left(pg_get_functiondef(oid),1600),'missing') FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='update_lawyer_active_tasks';" },
  @{ L='offer_documents_cols'; S="SELECT COALESCE(string_agg(column_name||':'||data_type,',' ORDER BY ordinal_position),'missing') FROM information_schema.columns WHERE table_schema='public' AND table_name='offer_documents';" },
  @{ L='offer_documents_count'; S="SELECT count(*) AS n FROM public.offer_documents;" },
  @{ L='offers_doc_orphans'; S="SELECT count(*) AS n FROM public.offers WHERE doc_tp<>0 AND COALESCE(doc_img,'')='';" },
  @{ L='offers_photo_req_docs'; S="SELECT count(*) AS n FROM public.offers WHERE COALESCE(photo_req,'')<>'';" },
  @{ L='markers'; S="SELECT (SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%LAWYER_INACTIVE_FOR_RENEWAL%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='approve_payment_final_v3' LIMIT 1) AS v3_inactive,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%CHAT_EXPIRED_7DAYS%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='approve_payment_final_v3' LIMIT 1) AS v3_7days,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%OPEN_CONSULTATION_EXISTS%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='prepare_consultation_intent_v2' LIMIT 1) AS prepare_guard,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%process_consultation_outbox_v2%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='enqueue_consultation_notification_push' LIMIT 1) AS enqueue_immediate,(SELECT CASE WHEN EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='rebook_legal_appointment_v2') THEN 'ok' ELSE 'missing' END) AS rebook,(SELECT CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='consultation_chats' AND column_name='waveform') THEN 'ok' ELSE 'missing' END) AS waveform_col,(SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='get_lawyer_appointments' LIMIT 1) AS lawyer_appts_sig,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%officeAddress%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='trg_consultation_payment_v2' LIMIT 1) AS onsite_rich,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%doc_img_admin%' THEN 'with_admin_col' ELSE 'no_admin_col' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='trg_offers_shield_doc_img' LIMIT 1) AS shield_uses_admin_col;" }
)

Write-Host "Drift markers - read-only"
foreach ($q in $QUERIES) {
    $body = @{ query = $q.S } | ConvertTo-Json -Compress
    $tmp = Join-Path $env:TEMP ("dm_" + [guid]::NewGuid().ToString('N') + ".json")
    $out = Join-Path $env:TEMP ("dm_" + [guid]::NewGuid().ToString('N') + ".json")
    [System.IO.File]::WriteAllText($tmp, $body, (New-Object System.Text.UTF8Encoding($false)))
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $code = & curl.exe -sS --max-time 90 -o $out -w "%{http_code}" -X POST "$API/database/query" -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" --data-binary "@$tmp" 2>$null
    $ErrorActionPreference = $prevEAP
    $resp = if (Test-Path $out) { (Get-Content $out -Raw -Encoding UTF8) } else { '""' }
    Write-Host "  [M-$($q.L)] HTTP $code $resp"
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Remove-Item $out -ErrorAction SilentlyContinue
}
Write-Host '[DONE] drift markers complete.'
