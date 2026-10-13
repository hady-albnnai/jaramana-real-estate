// Edge Function: user-requests
// الغرض: إدارة طلبات العميل عبر Service Role مع تحقق جلسة المستخدم، دون فتح RPCs مباشرة للعميل.

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
  body: Record<string, unknown> = {},
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
      return { ok: true, uid };
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

  // FALLBACK REMOVED: No longer accepting requestedUid blindly.
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

    if (!requestedUid) {
      return json({ success: false, error: "USER_UID_REQUIRED" }, 400);
    }

    const actor = await validateUser(req, supabaseAdmin, requestedUid, body);
    if (!actor.ok) return actor.response;
    const uid = actor.uid;

    if (action === "can_publish") {
      const { data, error } = await supabaseAdmin.rpc("can_publish_request_internal", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, result: data });
    }

    if (action === "list") {
      const { data, error } = await supabaseAdmin.rpc("get_user_requests_internal", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, requests: data ?? [] });
    }

    if (action === "create") {
      const requestData = body.request as Record<string, unknown>;
      if (!requestData) return json({ success: false, error: "REQUEST_DATA_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("create_request_internal", {
        p_user_uid: uid,
        p_request: requestData,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, request: Array.isArray(data) ? data[0] : data });
    }

    if (action === "update") {
      const reqId = (body.request_id ?? body.requestId)?.toString() ?? "";
      const patchData = body.patch as Record<string, unknown>;
      if (!reqId || !patchData) return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);

      const { data, error } = await supabaseAdmin.rpc("update_request_internal", {
        p_user_uid: uid,
        p_request_id: reqId,
        p_patch: patchData,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "cancel" || action === "delete") {
      const reqId = (body.request_id ?? body.requestId)?.toString() ?? "";
      const reason = (body.reason ?? "").toString();
      if (!reqId) return json({ success: false, error: "REQUEST_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("cancel_request_internal", {
        p_user_uid: uid,
        p_request_id: reqId,
        p_reason: reason,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "renew") {
      const reqId = (body.request_id ?? body.requestId)?.toString() ?? "";
      if (!reqId) return json({ success: false, error: "REQUEST_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("renew_request_internal", {
        p_user_uid: uid,
        p_request_id: reqId,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
