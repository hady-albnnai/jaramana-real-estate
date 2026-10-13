// Edge Function: update-staff-id-images
// الغرض: تحديث صور هوية موظف داخلي موجود من قبل المدير/نائب المدير عبر service_role فقط.

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

function base64ToUint8Array(base64: string): Uint8Array {
  const clean = base64.includes(",") ? base64.split(",").pop() ?? "" : base64;
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function safeImageContentType(value: unknown): string {
  const contentType = typeof value === "string" ? value.toLowerCase() : "image/jpeg";
  return ["image/jpeg", "image/jpg", "image/png", "image/webp"].includes(contentType)
    ? (contentType === "image/jpg" ? "image/jpeg" : contentType)
    : "image/jpeg";
}

function parseImagePaths(value: unknown): string[] {
  if (typeof value !== "string" || !value.trim()) return [];
  const trimmed = value.trim();
  if (trimmed.startsWith("http")) return [];
  if (trimmed.startsWith("[")) {
    try {
      const parsed = JSON.parse(trimmed);
      if (Array.isArray(parsed)) {
        return parsed.filter((item): item is string => typeof item === "string" && item.trim().length > 0 && !item.startsWith("http"));
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

    const body = await req.json();
    const actor = await validateActor(req, supabaseAdmin, body, 5);
    if (!actor.ok) return actor.response;

    const targetUid = (body.target_uid ?? body.targetUid)?.toString() ?? "";
    if (!targetUid) return json({ success: false, error: "TARGET_UID_REQUIRED" }, 400);

    const rawIdImages = Array.isArray(body.id_images_base64)
      ? body.id_images_base64
      : [];
    const idImageBytesList = rawIdImages
      .filter((item): item is string => typeof item === "string" && item.length > 0)
      .slice(0, 2)
      .map(base64ToUint8Array);

    if (idImageBytesList.length < 2) {
      return json({ success: false, error: "ID_IMAGES_REQUIRED_MIN_2" }, 400);
    }
    if (idImageBytesList.some((bytes) => bytes.length > 8 * 1024 * 1024)) {
      return json({ success: false, error: "ID_IMAGE_TOO_LARGE" }, 413);
    }

    const { data: target, error: targetError } = await supabaseAdmin
      .from("users")
      .select("id, role, img, i_del, sts")
      .eq("id", targetUid)
      .eq("i_del", 0)
      .single();

    if (targetError || !target) return json({ success: false, error: "USER_NOT_FOUND" }, 404);
    if (Number(target.role) < 2) return json({ success: false, error: "TARGET_NOT_STAFF" }, 400);

    // نائب المدير لا يحدّث هوية الإدارة العليا أو الأدوار القانونية ذات الرقم الأعلى. المدير يرى الجميع.
    if (actor.role < 6 && Number(target.role) >= 5 && targetUid !== actor.adminUid) {
      return json({ success: false, error: "FORBIDDEN_TARGET_ROLE" }, 403);
    }

    const contentType = safeImageContentType(body.id_image_content_type);
    const ext = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
    const idImagePaths: string[] = [];
    const stamp = Date.now();

    for (let index = 0; index < idImageBytesList.length; index++) {
      const idImagePath = `${targetUid}/staff_id_${stamp}_${index + 1}.${ext}`;
      const { error: uploadError } = await supabaseAdmin.storage
        .from("ids_private")
        .upload(idImagePath, idImageBytesList[index], {
          contentType,
          cacheControl: "3600",
          upsert: true,
        });

      if (uploadError) {
        return json({ success: false, error: `ID_UPLOAD_FAILED: ${uploadError.message}` }, 400);
      }
      idImagePaths.push(idImagePath);
    }

    const storedImg = JSON.stringify(idImagePaths);
    const { error: updateError } = await supabaseAdmin
      .from("users")
      .update({ img: storedImg, vrf: 2, ts_upd: new Date().toISOString() })
      .eq("id", targetUid);

    if (updateError) {
      return json({ success: false, error: `ID_IMAGE_SAVE_FAILED: ${updateError.message}` }, 400);
    }

    const oldPaths = parseImagePaths(target.img);
    if (oldPaths.length > 0) {
      await supabaseAdmin.storage.from("ids_private").remove(oldPaths);
    }

    return json({
      success: true,
      user_id: targetUid,
      id_image_paths: idImagePaths,
      count: idImagePaths.length,
    });
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
