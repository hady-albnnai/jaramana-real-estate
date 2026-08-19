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
  if [ "$code" != "200" ]; then echo "❌ فشل: $label"; exit 1; fi
}

# ── 1) التحقق الحي قبل أي تعديل (تسجيل فقط) ──
if [ "$APPLY_MIGRATIONS" = "true" ] || [ "$CLEANUP" = "true" ]; then
  echo "══════════ التحقق الحي قبل التعديل ══════════"
  run_sql "تريغرات offers" "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='offers' AND NOT t.tgisinternal;"
  run_sql "تريغرات payments" "SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid WHERE c.relname='payments' AND NOT t.tgisinternal;"
  run_sql "حالة admin_review_offer_internal" "SELECT pg_get_functiondef('public.admin_review_offer_internal(uuid,uuid,boolean,text)'::regprocedure) LIKE '%ونشره%' AS title_patched, pg_get_functiondef('public.admin_review_offer_internal(uuid,uuid,boolean,text)'::regprocedure) LIKE '%30 days%' AS ttl_patched;"
  run_sql "حالة trg_consultation_payment_v2" "SELECT pg_get_functiondef('public.trg_consultation_payment_v2()'::regprocedure) LIKE '%ensure_renewal_chat_session_v2%' AS renewal_patched;"
  if [ -n "$TEST_USER_NAME" ]; then
    run_sql "مستخدم الاختبار" "SELECT id, nm, usr, role, sts FROM public.users WHERE nm ILIKE '%${TEST_USER_NAME}%' OR usr ILIKE '%${TEST_USER_NAME}%';"
  fi
fi

# ── 2) تطبيق تعديلات قاعدة البيانات المعلّقة (2026_08_19) ──
if [ "$APPLY_MIGRATIONS" = "true" ]; then
  echo "══════════ تطبيق التعديلات 2026_08_19 ══════════"
  for f in supabase/migrations/2026_08_19_*.sql; do
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

# ── 4) نشر دوال Edge (POST إن لم توجد / PATCH إن وُجدت) ──
deploy_fn() {
  local slug="$1"; local exists method meta code
  exists=$(curl -sS --max-time 60 -o /dev/null -w "%{http_code}" "$API/functions/$slug" -H "Authorization: Bearer $PAT")
  method="POST"; [ "$exists" = "200" ] && method="PATCH"
  meta=$(python3 -c 'import json; print(json.dumps({"name":"'"$slug"'","verify_jwt":false,"entrypoint_path":"index.ts","import_map_path":null}))')
  code=$(curl -sS --max-time 300 -o /tmp/fn_resp.json -w "%{http_code}" -X "$method" "$API/functions/$slug" \
    -H "Authorization: Bearer $PAT" \
    -F "metadata=$meta;type=application/json" \
    -F "file=@supabase/functions/$slug/index.ts;type=text/plain")
  echo "── $slug [$method] HTTP $code"
  cat /tmp/fn_resp.json; echo
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then echo "❌ فشل نشر $slug"; exit 1; fi
}

if [ "$DEPLOY_FUNCTIONS" = "true" ]; then
  echo "══════════ نشر دوال Edge ══════════"
  deploy_fn admin-dashboard
  deploy_fn legal-actions
fi

echo "✅ تمت العملية بنجاح"
