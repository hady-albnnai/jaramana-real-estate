// Edge Function: get-staff-id-images
// الغرض: إرجاع روابط مؤقتة لصور هوية الموظف للمدير/نائب المدير فقط.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

function parseImagePaths(value: unknown): string[] {
  if (typeof value !== "string" || !value.trim()) return [];
  const trimmed = value.trim();
  if (trimmed.startsWith("http")) return [trimmed];
  if (trimmed.startsWith("[")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
      }
    } catch (_) {
      // fallback below
    }
  }
  return [trimmed];
}

async function validateActor(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  minRole = 5,
): Promise<{ ok: true; adminUid: string; role: number } | { ok: false; response: Response }> {
  const requestedAdminUid = (body.admin_uid ?? body.adminUid)?.toString() ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer) {
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

  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? "";
  if (!requestedAdminUid || !sessionToken) {
    return { ok: false, response: json({ success: false, error: "ADMIN_SESSION_REQUIRED" }, 401) };
  }

  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: requestedAdminUid,
    p_token: sessionToken,
    p_min_role: minRole,
  });

  if (error || data?.success !== true) {
    return { ok: false, response: json({ success: false, error: data?.error ?? error?.message ?? "INVALID_ADMIN_SESSION" }, 401) };
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

    const body = await req.json();
    const action = (body.action ?? "").toString();
    
    // دعم جلب signed URL مباشر لمسار صورة في ids_private
    // يُستخدم من شاشة مراجعة التوثيق (minRole = 4)
    if (action === "get_signed_url") {
      const actor2 = await validateActor(req, supabaseAdmin, body, 4);
      if (!actor2.ok) return actor2.response;
      
      const path = (body.path ?? "").toString();
      if (!path) return json({ success: false, error: "PATH_REQUIRED" }, 400);
      
      // لا نسمح بجلب URLs خارجية عبر هذا endpoint
      if (path.startsWith("http")) {
        return json({ success: true, signed_url: path });
      }
      
      const { data: signed, error: signError } = await supabaseAdmin.storage
        .from("ids_private")
        .createSignedUrl(path, 300);
      if (signError) return json({ success: false, error: `SIGN_FAILED: ${signError.message}` }, 400);
      if (signed?.signedUrl) {
        return json({ success: true, signed_url: signed.signedUrl });
      }
      return json({ success: false, error: "NO_SIGNED_URL" }, 400);
    }

    // الدالة الأصلية: جلب كل صور هوية موظف/مستخدم
    const actor = await validateActor(req, supabaseAdmin, body, 5);
    if (!actor.ok) return actor.response;

    const targetUid = (body.target_uid ?? body.targetUid)?.toString() ?? "";
    if (!targetUid) return json({ success: false, error: "TARGET_UID_REQUIRED" }, 400);

    const { data: target, error } = await supabaseAdmin
      .from("users")
      .select("id, role, img, i_del")
      .eq("id", targetUid)
      .eq("i_del", 0)
      .single();

    if (error || !target) return json({ success: false, error: "USER_NOT_FOUND" }, 404);

    // نائب المدير لا يطلع على هوية مدير/نائب آخر. المدير يرى الجميع.
    if (actor.role < 6 && Number(target.role) >= 5 && targetUid !== actor.adminUid) {
      return json({ success: false, error: "FORBIDDEN_TARGET_ROLE" }, 403);
    }

    const paths = parseImagePaths(target.img);
    const urls: string[] = [];

    for (const path of paths) {
      if (path.startsWith("http")) {
        urls.push(path);
        continue;
      }
      const { data: signed, error: signError } = await supabaseAdmin.storage
        .from("ids_private")
        .createSignedUrl(path, 300);
      if (signError) return json({ success: false, error: `SIGN_FAILED: ${signError.message}` }, 400);
      if (signed?.signedUrl) urls.push(signed.signedUrl);
    }

    return json({ success: true, urls, count: urls.length });
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
