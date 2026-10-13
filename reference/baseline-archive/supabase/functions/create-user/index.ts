// Edge Function: create-user
// الغرض: إنشاء موظف داخلي من قبل الإدارة وفق منطق عقارات السويداء (users.usr/pwd)

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function env(name: string, fallback?: string): string {
  return Deno.env.get(name) ?? (fallback ? Deno.env.get(fallback) ?? "" : "");
}

function randomPassword(length = 12): string {
  const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#%&*";
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (byte) => chars[byte % chars.length]).join("");
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
    const adminUid = actor.adminUid;
    const fullName = body.full_name ?? body.fullName;
    const phone = body.phone;
    const email = body.email ?? "";
    const username = body.username ?? "";
    const address = (body.address ?? "").toString();
    const sid = (body.sid ?? "").toString();
    const role = Number(body.role);
    if (address.trim().length < 3) {
      return json({ success: false, error: "ADDRESS_REQUIRED" }, 400);
    }
    if (sid.trim().length < 3) {
      return json({ success: false, error: "SID_REQUIRED" }, 400);
    }
    const password = typeof body.password === "string" && body.password.length >= 8
      ? body.password
      : randomPassword();
    const rawIdImages = Array.isArray(body.id_images_base64)
      ? body.id_images_base64
      : (typeof body.id_image_base64 === "string" && body.id_image_base64 ? [body.id_image_base64] : []);
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

    // ننشئ الموظف أولاً بدون مسار صورة، ثم نرفع صورة الهوية عبر service_role
    // إلى مجلد UID الموظف نفسه، وبعدها نحدّث users.img بالمسار الخاص.
    const { data, error } = await supabaseAdmin.rpc("admin_create_staff_user", {
      p_admin_uid: adminUid,
      p_full_name: fullName,
      p_phone: phone,
      p_email: email,
      p_username: username,
      p_password: password,
      p_role: role,
      p_address: address,
      p_sid: sid,
      p_img: "",
    });

    if (error) return json({ success: false, error: error.message }, 400);
    if (data?.success !== true || !data?.user_id) {
      return json({ success: false, error: data?.error ?? "CREATE_USER_FAILED" }, 400);
    }

    const idImagePaths: string[] = [];
    if (idImageBytesList.length > 0) {
      const contentType = safeImageContentType(body.id_image_content_type);
      const ext = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";

      for (let index = 0; index < idImageBytesList.length; index++) {
        const idImagePath = `${data.user_id}/staff_id_${Date.now()}_${index + 1}.${ext}`;
        const { error: uploadError } = await supabaseAdmin.storage
          .from("ids_private")
          .upload(idImagePath, idImageBytesList[index], {
            contentType,
            cacheControl: "3600",
            upsert: true,
          });

        if (uploadError) {
          await supabaseAdmin
            .from("users")
            .update({ i_del: 1, sts: 1, ban_rsn: "ID_UPLOAD_FAILED", ts_upd: new Date().toISOString() })
            .eq("id", data.user_id);
          return json({ success: false, error: `ID_UPLOAD_FAILED: ${uploadError.message}`, user_id: data.user_id }, 400);
        }
        idImagePaths.push(idImagePath);
      }

      const storedImg = idImagePaths.length === 1 ? idImagePaths[0] : JSON.stringify(idImagePaths);
      const { error: updateImageError } = await supabaseAdmin
        .from("users")
        .update({ img: storedImg, vrf: 2, ts_upd: new Date().toISOString() })
        .eq("id", data.user_id);

      if (updateImageError) {
        await supabaseAdmin
          .from("users")
          .update({ i_del: 1, sts: 1, ban_rsn: "ID_IMAGE_SAVE_FAILED", ts_upd: new Date().toISOString() })
          .eq("id", data.user_id);
        return json({ success: false, error: `ID_IMAGE_SAVE_FAILED: ${updateImageError.message}`, user_id: data.user_id }, 400);
      }
    }

    return json({
      success: true,
      user_id: data.user_id,
      new_password: password,
      id_image_paths: idImagePaths,
      id_image_path: idImagePaths[0] ?? "",
    });
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
