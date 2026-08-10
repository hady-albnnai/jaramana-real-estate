// Edge Function: user-notifications
// الغرض: إدارة الإشعارات والإعدادات الخاصة بالمستخدم بأمان عبر JWT.

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

// دالة للتحقق من المستخدم الحالي عن طريق الـ JWT
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

    if (action === "list") {
      const { data, error } = await supabaseAdmin.rpc("get_user_notifications_internal", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, notifications: data ?? [] });
    }

    if (action === "mark_read") {
      const notificationId = (body.notification_id ?? body.notificationId)?.toString() ?? "";
      if (!notificationId) return json({ success: false, error: "NOTIFICATION_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("mark_notification_read_internal", {
        p_user_uid: uid,
        p_notification_id: notificationId,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "mark_all_read") {
      const { data, error } = await supabaseAdmin.rpc("mark_all_notifications_read_internal", {
        p_user_uid: uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "update_settings") {
      const ntfSettings = body.ntf as Record<string, unknown>;
      if (!ntfSettings) return json({ success: false, error: "NTF_SETTINGS_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("update_user_notification_settings_internal", {
        p_user_uid: uid,
        p_ntf: ntfSettings,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    // ✅ Fix for Bug #9: Add send notification action
    if (action === "send") {
      const targetUid = (body.target_uid ?? body.targetUid)?.toString() ?? "";
      const type = parseInt((body.type ?? "1").toString());
      const title = (body.title ?? "").toString();
      const notifBody = (body.body ?? "").toString();
      const refId = (body.ref_id ?? body.refId ?? "").toString();
      const actionType = (body.action_type ?? body.actionType ?? "").toString();

      if (!targetUid) return json({ success: false, error: "TARGET_UID_REQUIRED" }, 400);
      if (!title) return json({ success: false, error: "TITLE_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("notify_user", {
        p_uid: targetUid,
        p_type: type,
        p_title: title,
        p_body: notifBody,
        p_ref_id: refId,
        p_action: actionType,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, notification_id: data });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
