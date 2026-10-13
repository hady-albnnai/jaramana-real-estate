// Edge Function: executor-tasks
// الغرض: نقل مهام المنفذ من RPC مباشر إلى Edge Function تتحقق من جلسة الموظف.

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
  minRole = 2, // دور المنفذ أو أعلى
): Promise<{ ok: true; uid: string; role: number } | { ok: false; response: Response }> {
  const requestedUid = (body.user_uid ?? body.userUid ?? body.admin_uid ?? body.adminUid ?? body.user_id ?? body.userId)?.toString() ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (uid && (!requestedUid || requestedUid === uid)) {
      const { data: userRow, error } = await supabaseAdmin
        .from("users")
        .select("id, role, sts, i_del")
        .eq("id", uid)
        .eq("i_del", 0)
        .single();

      if (!error && userRow && userRow.sts === 0 && Number(userRow.role) >= minRole) {
        return { ok: true, uid: uid, role: Number(userRow.role) };
      }
    }
  }

  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
  if (!requestedUid || !sessionToken) {
    return { ok: false, response: json({ success: false, error: "STAFF_SESSION_REQUIRED" }, 401) };
  }

  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: requestedUid,
    p_token: sessionToken,
    p_min_role: minRole,
  });

  if (error || data?.success !== true) {
    return {
      ok: false,
      response: json({ success: false, error: data?.error ?? error?.message ?? "INVALID_STAFF_SESSION" }, 401),
    };
  }

  return { ok: true, uid: requestedUid, role: Number(data.role) };
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
    const actor = await validateActor(req, supabaseAdmin, body, 2); // دور 2 للمنفذ الميداني (أو أعلى)
    if (!actor.ok) return actor.response;

    const uid = actor.uid;

    if (action === "get_my_tasks") {
      const { data, error } = await supabaseAdmin.rpc("get_my_tasks", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, tasks: data ?? [] });
    }

    if (action === "get_postponed_tasks") {
      const { data, error } = await supabaseAdmin.rpc("get_postponed_tasks", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, tasks: data ?? [] });
    }

    if (action === "get_completed_tasks") {
      const { data, error } = await supabaseAdmin.rpc("get_completed_tasks", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, tasks: data ?? [] });
    }

    if (action === "get_task_by_appointment") {
      const appointmentId = (body.appointment_id ?? body.appointmentId)?.toString() ?? "";
      if (!appointmentId) return json({ success: false, error: "APPOINTMENT_ID_REQUIRED" }, 400);
      const { data, error } = await supabaseAdmin.rpc("get_executor_task_by_appointment", {
        p_user_uid: uid,
        p_appointment_id: appointmentId,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, tasks: data ?? [] });
    }

    if (action === "get_my_completion_requests") {
      const { data, error } = await supabaseAdmin.rpc("get_my_completion_requests", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, requests: data ?? [] });
    }

    if (action === "update_task_outcome") {
      const appointmentId = (body.appointment_id ?? body.appointmentId)?.toString() ?? "";
      const outcome = (body.outcome ?? "").toString();
      const notes = (body.notes ?? "").toString();
      const rejectionReason = body.rejection_reason?.toString() ?? null;
      const newDate = body.new_date?.toString() ?? null;

      if (!appointmentId || !outcome) return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);

      const { data, error } = await supabaseAdmin.rpc("update_task_outcome", {
        p_user_uid: uid,
        p_appointment_id: appointmentId,
        p_outcome: outcome,
        p_notes: notes,
        p_rejection_reason: rejectionReason,
        p_new_date: newDate,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "request_completion") {
      const appointmentId = (body.appointment_id ?? body.appointmentId)?.toString() ?? "";
      const notes = (body.notes ?? "").toString();
      if (!appointmentId) return json({ success: false, error: "APPOINTMENT_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("request_completion_by_appointment", {
        p_user_uid: uid,
        p_appointment_id: appointmentId,
        p_notes: notes,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    // خاصة بالإدارة أو الموظف المكتبي
    if (action === "get_pending_requests") {
      if (actor.role < 3) return json({ success: false, error: "ADMIN_REQUIRED" }, 403);
      const { data, error } = await supabaseAdmin.rpc("get_all_pending_completion_requests", { p_admin_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, requests: data ?? [] });
    }

    if (action === "process_completion_request") {
      if (actor.role < 3) return json({ success: false, error: "ADMIN_REQUIRED" }, 403);
      const requestId = (body.request_id ?? body.requestId)?.toString() ?? "";
      const decision = (body.decision ?? "").toString();
      const officeNotes = (body.office_notes ?? body.officeNotes ?? "").toString();

      if (!requestId || !decision) return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);

      const { data, error } = await supabaseAdmin.rpc("process_completion_request", {
        p_admin_uid: uid,
        p_request_id: requestId,
        p_decision: decision,
        p_office_notes: officeNotes,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
