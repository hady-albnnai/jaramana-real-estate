// Edge Function: publish-to-social
// Manual, staff-authorized publication of an approved offer to Facebook + Instagram.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { publishOfferToSocial } from "../_shared/social_publisher.ts";

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

async function validateActor(req: Request, supabaseAdmin: any, body: Record<string, unknown>) {
  const requestedUid = (body.admin_uid ?? body.adminUid)?.toString() ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && !["undefined", "null", "anon_key_here"].includes(bearer)) {
    const { data: userData } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (uid && (!requestedUid || requestedUid === uid)) {
      const { data: row } = await supabaseAdmin
        .from("users")
        .select("id,role,sts,i_del")
        .eq("id", uid)
        .eq("i_del", 0)
        .single();
      if (row && row.sts === 0 && Number(row.role) >= 3) return { ok: true, adminUid: uid };
    }
  }

  const staffToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? "";
  if (!requestedUid || !staffToken) return { ok: false };
  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: requestedUid,
    p_token: staffToken,
    p_min_role: 3,
  });
  if (!error && data?.success === true) return { ok: true, adminUid: requestedUid };
  return { ok: false };
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
    const actor = await validateActor(req, supabaseAdmin, body);
    if (!actor.ok) return json({ success: false, error: "INVALID_ADMIN_SESSION" }, 401);

    const offerId = (body.offer_id ?? body.offerId)?.toString() ?? "";
    if (!offerId) return json({ success: false, error: "OFFER_ID_REQUIRED" }, 400);

    const result = await publishOfferToSocial(supabaseAdmin, offerId);
    try {
      await supabaseAdmin.rpc("log_admin_action", {
        p_admin_uid: actor.adminUid,
        p_act: result.success ? 106 : 107,
        p_det: result.success
          ? "تم النشر الفعلي على فيسبوك وإنستغرام"
          : `فشل/تعذر النشر الاجتماعي: ${result.error ?? "UNKNOWN"}`,
        p_ref_id: offerId,
        p_ref_col: "offers",
      });
    } catch (_) {}

    // Business failures return 200 so the Flutter client receives platform details.
    return json(result as unknown as Record<string, unknown>);
  } catch (error) {
    return json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
