// Edge Function: admin-reports
// الغرض: إدارة التبليغات للإدارة خلف Edge Function للتحقق من الصلاحيات.

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

async function validateActor(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  minRole = 3,
): Promise<{ ok: true; adminUid: string; role: number } | { ok: false; response: Response }> {
  const requestedAdminUid = (body.admin_uid ?? body.adminUid ?? body.user_uid ?? body.userUid ?? body.admin_id ?? body.adminId)?.toString() ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (uid && (!requestedAdminUid || requestedAdminUid === uid)) {
      const { data: userRow, error } = await supabaseAdmin
        .from("users")
        .select("id, role, sts, i_del")
        .eq("id", uid)
        .eq("i_del", 0)
        .single();

      if (!error && userRow && userRow.sts === 0 && Number(userRow.role) >= minRole) {
        return { ok: true, adminUid: uid, role: Number(userRow.role) };
      }
    }
  }

  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
  if (!requestedAdminUid || !sessionToken) {
    return { ok: false, response: json({ success: false, error: "ADMIN_SESSION_REQUIRED" }, 401) };
  }

  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: requestedAdminUid,
    p_token: sessionToken,
    p_min_role: minRole,
  });

  if (error || data?.success !== true) {
    return {
      ok: false,
      response: json({ success: false, error: data?.error ?? error?.message ?? "INVALID_ADMIN_SESSION" }, 401),
    };
  }

  return { ok: true, adminUid: requestedAdminUid, role: Number(data.role) };
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
    // تقارير الإدارة تتطلب صلاحية 3 أو أعلى (admin/deputy)
    const actor = await validateActor(req, supabaseAdmin, body, 3);
    if (!actor.ok) return actor.response;

    const adminUid = actor.adminUid;

    if (action === "list") {
      const { data, error } = await supabaseAdmin.rpc("get_admin_reports_internal", {
        p_admin_uid: adminUid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, reports: data ?? [] });
    }

    if (action === "handle") {
      const reportId = (body.report_id ?? body.reportId)?.toString() ?? "";
      const reportAction = Number(body.report_action ?? body.reportAction ?? 0);
      const note = (body.note ?? "").toString();
      const duration = Number(body.duration ?? 0);

      if (!reportId) return json({ success: false, error: "REPORT_ID_REQUIRED" }, 400);
      
      const { data, error } = await supabaseAdmin.rpc("admin_handle_report_internal", {
        p_admin_uid: adminUid,
        p_report_id: reportId,
        p_action: reportAction,
        p_note: note,
        p_duration: duration,
      });
      
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
