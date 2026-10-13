// Edge Function: broker-actions
// الغرض: تسجيل طلب الوسيط العقاري من قبل المستخدم.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function env(name: string, fallback?: string): string {
  return Deno.env.get(name) ?? (fallback ? Deno.env.get(fallback) ?? "" : "");
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function validateUser(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  requestedUid: string,
  body: Record<string, unknown> = {}
): Promise<{ ok: true; uid: string } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData, error } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (!error && uid) {
      if (requestedUid && requestedUid !== uid) {
        return { ok: false, response: json({ success: false, error: "UNAUTHORIZED_ACCESS" }, 403) };
      }
      return { ok: true, uid: uid };
    }
  }

  // 2. Try Custom Session Token validation (for custom password login)
  const sessionToken = (body?.staff_session_token ?? body?.staffSessionToken ?? body?.session_token ?? body?.sessionToken)?.toString()
    || (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
  if (sessionToken && sessionToken !== "undefined" && sessionToken !== "null" && sessionToken !== "anon_key_here") {
    const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
      p_token: sessionToken,
      p_user_uid: requestedUid,
      p_min_role: 0,
    });

    if (!error && data && data.success === true) {
      return { ok: true, uid: data.user_id };
    }
  }

  return { ok: false, response: json({ success: false, error: "AUTH_TOKEN_REQUIRED" }, 401) };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ success: false, error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const supabaseAdmin = createClient(
      env("SUPABASE_URL", "PROJECT_URL"),
      env("SUPABASE_SERVICE_ROLE_KEY", "SERVICE_ROLE_KEY"),
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const body = await req.json() as Record<string, unknown>;
    const action = (body.action ?? "").toString();
    const requestedUid = (body.user_uid ?? body.userUid)?.toString() ?? "";

    if (!requestedUid) return json({ success: false, error: "USER_UID_REQUIRED" }, 400);

    const actor = await validateUser(req, supabaseAdmin, requestedUid, body);
    if (!actor.ok) return actor.response;
    const uid = actor.uid;

    if (action === "submit_request") {
      const businessName = (body.business_name ?? body.businessName ?? "").toString();
      const category = Number(body.category ?? 0);
      const experience = (body.experience ?? "").toString();
      const about = (body.about ?? "").toString();

      if (!businessName) return json({ success: false, error: "BUSINESS_NAME_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("submit_broker_request_internal", {
        p_user_uid: uid,
        p_business_name: businessName,
        p_category: category,
        p_experience: experience,
        p_about: about,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    // ═══════════════════════════════════════════════════════════════
    // 🤝 BRK-001 (2026-08-15): مراجعة طلبات الوساطة (كانت غائبة كلياً)
    // ═══════════════════════════════════════════════════════════════
    // بلاغ المالك: الطلب كان يُفعّل الوساطة فوراً بلا مراجعة أحد.
    // الآن الطلب يبقى brk=2 (قيد المراجعة) حتى تبتّ الإدارة هنا.
    if (action === "list_pending_requests") {
      const { data, error } = await supabaseAdmin
        .rpc("get_pending_broker_requests_internal", { p_admin_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      const r = (data ?? {}) as Record<string, unknown>;
      return json({ ...r, success: r.success === true });
    }

    if (action === "review_request") {
      const targetUid = (body.target_uid ?? body.targetUid)?.toString() ?? "";
      const approve = body.approve === true;
      const reason = (body.reason ?? "").toString();
      if (!targetUid) return json({ success: false, error: "TARGET_UID_REQUIRED" }, 400);
      const { data, error } = await supabaseAdmin
        .rpc("admin_review_broker_request_internal", {
          p_admin_uid: uid,
          p_target_uid: targetUid,
          p_approve: approve,
          p_reason: reason,
        });
      if (error) return json({ success: false, error: error.message }, 400);
      const r = (data ?? {}) as Record<string, unknown>;
      return json({ ...r, success: r.success === true }, r.success === true ? 200 : 400);
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
