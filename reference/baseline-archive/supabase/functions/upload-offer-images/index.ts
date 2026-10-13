// Edge Function: upload-offer-images
// الغرض: رفع صور العروض بأمان عبر service_role، بدون الاعتماد على auth.uid() في RLS.
// يدعم: staff_session_token (الموظفون) + JWT auth (المستخدمون العاديون).
// المخرج: قائمة روابط public URL للصور المرفوعة.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-staff-session-token",
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

// التحقق من حامل staff_session_token (موظف أو مستخدم عادي بدخول مخصص).
// ملاحظة: نوافق أي حامل جلسة صالحة (min_role 0) — التصنيف يتم لاحقاً:
// دور >= 2 → موظف (يرفع لأي مجلد)؛ إلا → مستخدم عادي (مجلده فقط).
async function validateStaff(
  supabaseAdmin: ReturnType<typeof createClient>,
  adminUid: string,
  staffToken: string,
): Promise<{ ok: true; uid: string; role: number } | { ok: false; response: Response }> {
  if (!adminUid || !staffToken) {
    return { ok: false, response: json({ success: false, error: "ADMIN_UID_AND_TOKEN_REQUIRED" }, 401) };
  }

  const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
    p_user_uid: adminUid,
    p_token: staffToken,
    p_min_role: 0,
  });

  if (error || data?.success !== true) {
    return { ok: false, response: json({ success: false, error: data?.error ?? error?.message ?? "INVALID_STAFF_SESSION" }, 401) };
  }

  return { ok: true, uid: adminUid, role: Number(data.role) };
}

// التحقق من المستخدم العادي عبر JWT
async function validateUser(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
): Promise<{ ok: true; uid: string } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (!bearer || bearer === "undefined" || bearer === "null" || bearer === "anon_key_here") {
    return { ok: false, response: json({ success: false, error: "AUTH_TOKEN_REQUIRED" }, 401) };
  }

  const { data: userData, error } = await supabaseAdmin.auth.getUser(bearer);
  const uid = userData?.user?.id;

  if (error || !uid) {
    return { ok: false, response: json({ success: false, error: "INVALID_AUTH_TOKEN" }, 401) };
  }

  return { ok: true, uid };
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

    const staffToken = req.headers.get("x-staff-session-token");
    let actorUid = "";
    let isStaff = false;

    const form = await req.formData();
    const adminUid = form.get("admin_uid")?.toString() ?? "";

    if (staffToken) {
      const staff = await validateStaff(supabaseAdmin, adminUid, staffToken);
      if (staff.ok) {
        actorUid = staff.uid;
        // الموظف فقط (role >= 2) يرفع لأي مجلد — المستخدم العادي يبقى مقيداً بمجلده
        isStaff = staff.role >= 2;
      } else {
        // تراجع إلى JWT: توكن موظف منتهي/تالف لا يجب أن يحجب جلسة إيميل صالحة
        const user = await validateUser(req, supabaseAdmin);
        if (!user.ok) return staff.response; // نعيد خطأ الجلسة الأصلي أوضح من AUTH_TOKEN_REQUIRED
        actorUid = user.uid;
      }
    } else {
      const user = await validateUser(req, supabaseAdmin);
      if (!user.ok) return user.response;
      actorUid = user.uid;
    }

    const files = form.getAll("files") as File[];
    const userId = form.get("user_id")?.toString() ?? actorUid;
    const offerId = form.get("offer_id")?.toString() ?? "draft";
    const folder = form.get("folder")?.toString() ?? "offers";

    if (!files.length) {
      return json({ success: false, error: "NO_FILES" }, 400);
    }

    // التحقق: الموظف يرفع لأي مجلد، المستخدم العادي فقط لمجلده
    if (!isStaff && userId !== actorUid) {
      return json({ success: false, error: "UNAUTHORIZED_FOLDER" }, 403);
    }

    const urls: string[] = [];

    for (const file of files) {
      const fileName = `${Date.now()}_${file.name}`;
      const fullPath = `${folder}/${userId}/${offerId}/${fileName}`;

      const arrayBuffer = await file.arrayBuffer();
      const bytes = new Uint8Array(arrayBuffer);

      // ملاحظة: uploadBinary غير موجودة في عميل supabase-js للـ Deno
      // (موجودة فقط في عميل Dart) — نستخدم upload القياسية مثل باقي دوال المشروع
      const { error: uploadError } = await supabaseAdmin.storage
        .from("offer_images")
        .upload(fullPath, bytes, {
          contentType: file.type || "image/jpeg",
          cacheControl: "3600",
          upsert: true,
        });

      if (uploadError) {
        return json({ success: false, error: `UPLOAD_FAILED: ${uploadError.message}` }, 400);
      }

      const { data: publicUrlData } = supabaseAdmin.storage
        .from("offer_images")
        .getPublicUrl(fullPath);

      urls.push(publicUrlData.publicUrl);
    }

    return json({ success: true, urls, count: urls.length });
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
