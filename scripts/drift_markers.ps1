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
#       -PAT "sbp_..." -REF "uiutmbujkfrpaipvfvij"
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
  @{ L='offers_photo_req_docs'; S="SELECT count(*) AS n FROM public.offers WHERE photo_req IS NOT NULL AND photo_req <> 0;" },
  @{ L='policy_urls'; S="SELECT value->'txts'->>'privacyPolicyUrl' AS privacy_url, value->'txts'->>'termsUrl' AS terms_url, value->'txts'->>'aboutUs' AS about_us, value->'txts'->>'contactPhone1' AS phone1, value->'txts'->>'contactPhone2' AS phone2, value->'txts'->>'contactWhatsApp' AS whatsapp FROM public.app_config WHERE key='main';" },
  @{ L='convert_share'; S="SELECT (SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%phone_initial%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='approve_payment_final_v3' LIMIT 1) AS v3_reverses_phone,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%reversed%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='admin_reverse_payment_v2' LIMIT 1) AS reverse_restores_phone,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%v_role < 4%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='trg_offer_approved_award_points' LIMIT 1) AS staff_points_guard,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%ADMIN_FORCE_DISABLED%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='admin_force_appointment_internal' LIMIT 1) AS force_disabled;" },
  @{ L='share_config'; S="SELECT id, lawyer_share_percent, to_char(ts_upd AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI') AS ts_upd_dam FROM public.legal_finance_config WHERE id=true;" },
  @{ L='share_samples'; S="SELECT e.lawyer_amount, e.gross_amount, e.share_percent, p.amt AS payment_amt, e.service_kind, e.status FROM public.lawyer_earnings e JOIN public.payments p ON p.id=e.payment_id ORDER BY e.ts_crt DESC LIMIT 10;" },
  @{ L='rev_null_approved'; S="SELECT count(*) AS approved_null_approved_at FROM public.payments WHERE sts=1 AND approved_at IS NULL;" },
  @{ L='rev_recent'; S="SELECT to_char(approved_at AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD') AS d, count(*) AS n, COALESCE(sum(amt) FILTER (WHERE cur=1),0) AS syp FROM public.payments WHERE sts=1 AND approved_at IS NOT NULL AND approved_at >= now()-interval '10 days' GROUP BY d ORDER BY d DESC;" },
  @{ L='otp_recent'; S="SELECT to_char(ts_crt AT TIME ZONE 'Asia/Damascus','YYYY/MM/DD HH24:MI:SS') AS ts_dam, identifier, channel, used, attempts FROM public.otp_codes ORDER BY ts_crt DESC LIMIT 15;" },
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
