#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════
# نشر Supabase تلقائياً (SQL + Edge Functions + تنظيف بيانات اختبار)
# يُشغَّل من GitHub Actions (سيرفرات GitHub تملك إنترنت كامل) أو يدوياً:
#   export SUPABASE_PROJECT_REF=vsgkgnjtebjxyqwpuopz
#   export SUPABASE_PAT='sbp_...'
#   export APPLY_MIGRATIONS=true CLEANUP=true \
#          TEST_USER_NAME='هناء العيسمي' DEPLOY_FUNCTIONS=true
#   bash scripts/deploy_supabase.sh
# لا يُخزَّن أي سر داخل الريبو — كل شيء من متغيرات البيئة.
# ══════════════════════════════════════════════════════════════════════
set -euo pipefail

REF="${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF مطلوب}"
PAT="${SUPABASE_PAT:?SUPABASE_PAT مطلوب}"
API="https://api.supabase.com/v1/projects/$REF"
APPLY_MIGRATIONS="${APPLY_MIGRATIONS:-false}"
CLEANUP="${CLEANUP:-false}"
TEST_USER_NAME="${TEST_USER_NAME:-}"
DEPLOY_FUNCTIONS="${DEPLOY_FUNCTIONS:-false}"

echo "▶ المشروع: $REF | migrations=$APPLY_MIGRATIONS | cleanup=$CLEANUP | functions=$DEPLOY_FUNCTIONS"

# ── تنفيذ استعلام SQL وإظهار النتيجة ──
run_sql() {
  local label="$1"; local sql="$2"
  local body code
  body=$(python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' <<< "$sql")
  code=$(curl -sS --max-time 180 -o /tmp/sq_resp.json -w "%{http_code}" -X POST "$API/database/query" \
    -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" --data-binary "$body")
  echo "── [$label] HTTP $code"
  cat /tmp/sq_resp.json; echo
  # 201 = نجاح أيضاً (Management API يرجع 201 على الاستعلامات/المايغريشن)
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then echo "❌ فشل: $label"; exit 1; fi
}

# ── 1) التحقق الحي قبل أي تعديل (تسجيل فقط) ──
if [ "$APPLY_MIGRATIONS" = "true" ] || [ "$CLEANUP" = "true" ]; then
  echo "══════════ التحقق الحي قبل التعديل ══════════"
  run_sql "تريغرات offers" "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='offers' AND NOT t.tgisinternal;"
  run_sql "تريغرات payments" "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='payments' AND NOT t.tgisinternal;"
  run_sql "حالة admin_review_offer_internal" "SELECT pg_get_functiondef('public.admin_review_offer_internal(uuid,uuid,boolean,text)'::regprocedure) LIKE '%ونشره%' AS title_patched, pg_get_functiondef('public.admin_review_offer_internal(uuid,uuid,boolean,text)'::regprocedure) LIKE '%30 days%' AS ttl_patched;"
  # 2026-08-19 (نسخة مصححة): التريغر الصحيح يُصلح ref_id عبر v_ref — لا يبحث
  # عن ensure_renewal_chat_session_v2 (حُذفت عمداً؛ v3 هي مصدر إنشاء الجلسة)
  run_sql "حالة trg_consultation_payment_v2" "SELECT pg_get_functiondef('public.trg_consultation_payment_v2()'::regprocedure) LIKE '%v_ref%' AS ref_patched;"
  if [ -n "$TEST_USER_NAME" ]; then
    run_sql "مستخدم الاختبار" "SELECT id, nm, usr, role, sts FROM public.users WHERE nm ILIKE '%${TEST_USER_NAME}%' OR usr ILIKE '%${TEST_USER_NAME}%';"
  fi
fi

# ── 2) تطبيق تعديلات قاعدة البيانات المعلّقة (2026_08_19) ──
if [ "$APPLY_MIGRATIONS" = "true" ]; then
  echo "══════════ تطبيق التعديلات 2026_08_19 ══════════"
  for f in supabase/migrations/2026_08_19_*.sql supabase/migrations/2026_08_20_*.sql; do
    [ -f "$f" ] || continue
    echo "▶ $f"
    run_sql "$(basename "$f")" "$(cat "$f")"
  done
fi

# ── 3) حذف بيانات مستخدم الاختبار (إن طُلب) ──
if [ "$CLEANUP" = "true" ]; then
  if [ -z "$TEST_USER_NAME" ]; then echo "❌ CLEANUP مفعّل بلا TEST_USER_NAME"; exit 1; fi
  echo "══════════ حذف بيانات مستخدم الاختبار: $TEST_USER_NAME ══════════"
  cleaned=$(sed "s/__TEST_USER_NAME__/${TEST_USER_NAME}/g" scripts/cleanup_test_user.sql)
  run_sql "تنظيف ${TEST_USER_NAME}" "$cleaned"
fi

# ── 4) نشر دوال Edge (POST /functions/deploy?slug={slug}) ──
# النقطة الصحيحة حسب وثائق Supabase الرسمية: POST /v1/projects/{ref}/functions/deploy?slug={slug}
# تنشئ الدالة إن لم توجد وتحدّثها إن وُجدت — لا حاجة لـ PATCH (كان يفشل 500 بسبب
# import_map_path:null) ولا DELETE+POST ولا POST /functions/{slug} (404).
deploy_fn() {
  local slug="$1"; local meta code
  meta=$(python3 -c 'import json; print(json.dumps({"name":"'"$slug"'","verify_jwt":false,"entrypoint_path":"index.ts"}))')
  code=$(curl -sS --max-time 300 -o /tmp/fn_resp.json -w "%{http_code}" -X POST "$API/functions/deploy?slug=$slug" \
    -H "Authorization: Bearer $PAT" \
    --form-string "metadata=$meta" \
    -F "file=@supabase/functions/$slug/index.ts;type=text/plain")
  echo "── $slug [POST /functions/deploy?slug=] HTTP $code"
  cat /tmp/fn_resp.json; echo
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then echo "❌ فشل نشر $slug"; exit 1; fi
}

if [ "$DEPLOY_FUNCTIONS" = "true" ]; then
  echo "══════════ نشر دوال Edge ══════════"
  deploy_fn admin-dashboard
  deploy_fn legal-actions
  # 🩹 2026-08-20: شارة المدفوعات (mark_read_by_act) + عنوان المكتب (update_sections)
  deploy_fn user-notifications
  deploy_fn admin-config
  # 🛡️ دين 1 (2026-08-20): توقيع رفع إثبات الدفع (إقفال فتحة الإغراق)
  deploy_fn user-account
fi


# ── 6) Drift snapshot (read-only diagnostics: schema truth) ──
drift_snap() {
  local label="$1"; local sql="$2"
  local body code
  body=$(python3 -c 'import json,sys; print(json.dumps({"query": sys.stdin.read()}))' <<< "$sql")
  code=$(curl -sS --max-time 120 -o /tmp/drift_resp.json -w "%{http_code}" -X POST "$API/database/query" \
    -H "Authorization: Bearer $PAT" -H "Content-Type: application/json" --data-binary "$body")
  if [ "$code" = "200" ] || [ "$code" = "201" ]; then
    echo "::notice title=drift-$label::$(head -c 19000 /tmp/drift_resp.json)"
  else
    echo "::notice title=drift-$label-err::HTTP $code $(head -c 300 /tmp/drift_resp.json)"
  fi
}
drift_snap tables "SELECT string_agg(table_name,',' ORDER BY table_name) FROM information_schema.tables WHERE table_schema='public';"
drift_snap columns "SELECT string_agg(table_name||': '||cols,E'\n' ORDER BY table_name) FROM (SELECT table_name,string_agg(column_name,',' ORDER BY ordinal_position) cols FROM information_schema.columns WHERE table_schema='public' AND table_name IN ('offers','users','payments','appointments','legal_consultations','consultation_intents','consultation_chats','consultation_chat_sessions','lawyer_profiles','lawyer_earnings','lawyer_time_reservations','consultation_event_outbox','consultation_credits') GROUP BY table_name) t;"
drift_snap functions-a "SELECT string_agg(proname||'('||pg_get_function_identity_arguments(oid)||')',E'\n' ORDER BY proname) FROM pg_proc WHERE pronamespace='public'::regnamespace AND prokind='f' AND proname < 'k';"
drift_snap functions-b "SELECT string_agg(proname||'('||pg_get_function_identity_arguments(oid)||')',E'\n' ORDER BY proname) FROM pg_proc WHERE pronamespace='public'::regnamespace AND prokind='f' AND proname >= 'k' AND proname < 's';"
drift_snap functions-c "SELECT string_agg(proname||'('||pg_get_function_identity_arguments(oid)||')',E'\n' ORDER BY proname) FROM pg_proc WHERE pronamespace='public'::regnamespace AND prokind='f' AND proname >= 's';"
drift_snap buckets "SELECT string_agg(id||'|pub='||public::text||'|lim='||COALESCE(file_size_limit::text,'-')||'|mime='||COALESCE(array_to_string(allowed_mime_types,','),'-'),E'\n' ORDER BY id) FROM storage.buckets;"
drift_snap proof_policies "SELECT string_agg(policyname||':'||cmd,',' ORDER BY policyname) FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname ILIKE '%proof%';"
drift_snap doc_state "SELECT (SELECT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='offers' AND column_name='doc_img_admin')) AS offers_doc_img_admin,(SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='offer_documents')) AS offer_documents_table,(SELECT count(*) FROM offers WHERE COALESCE(doc_img,'')<>'') AS offers_with_old_doc,(SELECT count(*) FROM offers WHERE COALESCE(to_jsonb(offers)->>'doc_img_admin','')<>'') AS offers_with_admin_doc;"
drift_snap doc_sample "SELECT string_agg(v,E'\n') FROM (SELECT DISTINCT left(COALESCE(doc_img,''),90) v FROM offers WHERE COALESCE(doc_img,'')<>'' LIMIT 12) t;"
drift_snap markers "SELECT (SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%LAWYER_INACTIVE_FOR_RENEWAL%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='approve_payment_final_v3' LIMIT 1) AS v3_inactive,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%CHAT_EXPIRED_7DAYS%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='approve_payment_final_v3' LIMIT 1) AS v3_7days,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%OPEN_CONSULTATION_EXISTS%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='prepare_consultation_intent_v2' LIMIT 1) AS prepare_guard,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%process_consultation_outbox_v2%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='enqueue_consultation_notification_push' LIMIT 1) AS enqueue_immediate,(SELECT CASE WHEN EXISTS(SELECT 1 FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='rebook_legal_appointment_v2') THEN 'ok' ELSE 'missing' END) AS rebook,(SELECT CASE WHEN EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='consultation_chats' AND column_name='waveform') THEN 'ok' ELSE 'missing' END) AS waveform_col,(SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='get_lawyer_appointments' LIMIT 1) AS lawyer_appts_sig,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%officeAddress%' THEN 'ok' ELSE 'missing' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='trg_consultation_payment_v2' LIMIT 1) AS onsite_rich,(SELECT CASE WHEN pg_get_functiondef(oid) LIKE '%doc_img_admin%' THEN 'with_admin_col' ELSE 'no_admin_col' END FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname='trg_offers_shield_doc_img' LIMIT 1) AS shield_uses_admin_col;"

echo "✅ تمت العملية بنجاح"
