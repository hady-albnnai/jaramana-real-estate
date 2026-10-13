// Edge Function: user-appointments
// الغرض: نقل عمليات حجز وإدارة مواعيد المستخدم والمالك والوسيط من RPC مباشر إلى Edge Function للتحقق من جلسة المستخدم.

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

// التحقق من المستخدم عبر JWT Token
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
  const sessionToken = (body?.staff_session_token ?? body?.staffSessionToken ?? body?.session_token ?? body?.sessionToken)?.toString() || bearer || authHeader.trim();
  if (sessionToken && sessionToken !== "anon_key_here" && sessionToken !== "undefined" && sessionToken !== "null") {
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

    if (action === "list_user_appointments") {
      const { data, error } = await supabaseAdmin.rpc("get_user_appointments_internal", { p_user_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);

      // 📸 دمج مواعيد التصوير المجدولة ضمن «مواعيدي» (طلب المالك 2026-07-28).
      // مهام التصوير بجدول منفصل (photography_tasks) فكانت غائبة كلياً عن الشاشة.
      // تُصاغ بشكل صف موعد (نفس مفاتيح appointments) حتى يبتلعها AppointmentModel
      // بلا أي تغيير ببنية الجدول أو بالنموذج. معرّفها هو معرّف المهمة نفسه.
      // sts: مهمة 0/1 (بانتظار/قيد التنفيذ) ⇒ 1 «مؤكد»، وغيرها ⇒ 3 «منتهي».
      let merged = (data ?? []) as Record<string, unknown>[];
      try {
        const { data: photos } = await supabaseAdmin
          .from("photography_tasks")
          .select("id, ttl, notes, sts, ts_scheduled, ts_crt, photographer_id, requested_by")
          .eq("requested_by", uid)
          .not("ts_scheduled", "is", null)
          .in("sts", [0, 1, 2, 3]);
        if (photos && photos.length > 0) {
          const asAppt = photos.map((t) => ({
            id: t.id,
            off_id: null,
            req_id: null,
            req_uid: t.requested_by,
            own_id: null,
            bkr_id: null,
            dt: t.ts_scheduled,
            dt_end: null,
            sts: Number(t.sts) <= 1 ? 1 : 3,
            cnl_by: null,
            cnl_rsn: null,
            fbk_own: 0, fbk_req: 0,
            fbk_own_dt: null, fbk_req_dt: null,
            fbk_own_dur: 0, fbk_req_dur: 0,
            admin_nt: `📸 موعد تصوير — ${t.ttl ?? ""}`,
            i_force: 0, force_by: null,
            rmnd_24: 0, rmnd_2: 0, rmnd_qtr: 0, rmnd_end: 0,
            ts_crt: t.ts_crt,
            supervisor_uid: t.photographer_id,
            neog: [],
            kind: "photography", // وسم للعميل إن أراد تمييزها لاحقاً
          }));
          merged = [...merged, ...asAppt].sort((a, b) =>
            String(a.dt ?? "").localeCompare(String(b.dt ?? ""))
          );
        }
      } catch {
        // الدمج إثراء ثانوي — فشله لا يمنع عرض المواعيد الأصلية
      }
      return json({ success: true, appointments: merged });
    }

    if (action === "list_owner_appointments") {
      const { data, error } = await supabaseAdmin.rpc("get_owner_appointments_internal", { p_owner_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, appointments: data ?? [] });
    }

    if (action === "list_broker_appointments") {
      const { data, error } = await supabaseAdmin.rpc("get_broker_appointments_internal", { p_broker_uid: uid });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, appointments: data ?? [] });
    }

    if (action === "get_booked_slots") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
      const date = (body.date ?? "").toString();

      if (!offerId || !date) {
        return json({ success: false, error: "OFFER_ID_AND_DATE_REQUIRED" }, 400);
      }

      const { data, error } = await supabaseAdmin.rpc("get_booked_slots_internal", {
        p_offer_id: offerId,
        p_date: date,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, booked_slots: data ?? [] });
    }

    if (action === "book") {
      const offerId = (body.offer_id ?? body.offerId)?.toString() ?? null;
      const dt = body.dt?.toString() ?? "";
      const brokerId = (body.broker_id ?? body.brokerId)?.toString() ?? null;
      const requestId = (body.request_id ?? body.requestId)?.toString() ?? null;

      if (!dt) return json({ success: false, error: "DATE_TIME_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("book_appointment_internal", {
        p_user_uid: uid,
        p_offer_id: offerId,
        p_dt: dt,
        p_broker_id: brokerId,
        p_request_id: requestId,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      // الدالة تعيد JSONB: نجاح {success, appointment_id, active_appointments, supervisor_uid}
      // أو فشل مُدار {success:false, error:'NO_SUPERVISOR_AVAILABLE', suggested_dt}
      if (data && typeof data === "object") {
        return json(data as Record<string, unknown>);
      }
      return json({ success: true, appointment_id: data });
    }

    if (action === "cancel") {
      const appointmentId = (body.appointment_id ?? body.appointmentId)?.toString() ?? "";
      const reason = (body.reason ?? "").toString();

      if (!appointmentId) return json({ success: false, error: "APPOINTMENT_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("cancel_appointment_internal", {
        p_requester_uid: uid,
        p_appointment_id: appointmentId,
        p_reason: reason,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "broker_handle") {
      const appointmentId = (body.appointment_id ?? body.appointmentId)?.toString() ?? "";
      const handleAction = (body.handle_action ?? body.handleAction ?? "").toString();

      if (!appointmentId || !handleAction) return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);

      const { data, error } = await supabaseAdmin.rpc("broker_handle_appointment_internal", {
        p_broker_uid: uid,
        p_appointment_id: appointmentId,
        p_action: handleAction,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "owner_respond") {
      const appointmentId = (body.appointment_id ?? body.appointmentId)?.toString() ?? "";
      const accept = body.accept === true;
      const rejectReason = body.reject_reason !== undefined ? Number(body.reject_reason) : null;
      const rejectText = body.reject_text?.toString() ?? null;
      const proposedDt = body.proposed_dt?.toString() ?? null;

      if (!appointmentId) return json({ success: false, error: "APPOINTMENT_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("owner_respond_appointment", {
        p_owner_uid: uid,
        p_appointment_id: appointmentId,
        p_accept: accept,
        p_reject_reason: rejectReason,
        p_reject_text: rejectText,
        p_proposed_dt: proposedDt,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      // الدالة تعيد JSONB (2026-07-02): نجاح {success:true}
      // أو فشل مُدار {success:false, error, suggested_dt?}
      if (data && typeof data === "object") {
        return json(data as Record<string, unknown>);
      }
      return json({ success: data === true });
    }

    if (action === "requester_counter") {
      const appointmentId = (body.appointment_id ?? body.appointmentId)?.toString() ?? "";
      const accept = body.accept === true;
      const proposedDt = body.proposed_dt?.toString() ?? null;

      if (!appointmentId) return json({ success: false, error: "APPOINTMENT_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("requester_counter_appointment", {
        p_user_uid: uid,
        p_appointment_id: appointmentId,
        p_accept: accept,
        p_proposed_dt: proposedDt,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      // الدالة تعيد JSONB (2026-07-02): نجاح {success:true}
      // أو فشل مُدار {success:false, error, suggested_dt?}
      if (data && typeof data === "object") {
        return json(data as Record<string, unknown>);
      }
      return json({ success: data === true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
