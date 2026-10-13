// ════════════════════════════════════════════════════════════════════════════
// Edge Function: send-push-notification
// يرسل إشعار FCM لمستخدم معيّن (لكل أجهزته المسجّلة في user_devices)
// ════════════════════════════════════════════════════════════════════════════
// يستقبل: { uid: "...", title: "...", body: "...", data?: {...} }
// يستخدم FCM HTTP v1 API + Google Service Account
// ════════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.1/mod.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-push-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface NotifyPayload {
  uid: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

// ─── الحصول على access token من Google ──────────────────────────────
async function getAccessToken(): Promise<string> {
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")!;
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")!.replace(/\\n/g, "\n");

  const pemContents = privateKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const binaryKey = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const jwt = await create(
    { alg: "RS256", typ: "JWT" },
    {
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      exp: getNumericDate(3600),
      iat: getNumericDate(0),
    },
    cryptoKey
  );

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenData = await res.json();
  if (!tokenData.access_token) {
    throw new Error("Failed to get access token: " + JSON.stringify(tokenData));
  }
  return tokenData.access_token;
}

// ─── إرسال FCM لتوكن واحد ──────────────────────────────────────────
async function sendFCM(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<{ ok: boolean; error?: string }> {
  const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;
  const payload = {
    message: {
      token,
      notification: { title, body },
      data: data || {},
      android: {
        priority: "HIGH",
        notification: {
          sound: "default",
          channel_id: "jaramana_default",
        },
      },
      apns: {
        payload: {
          aps: { sound: "default", badge: 1 },
        },
      },
    },
  };

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const errBody = await res.text();
    console.error(`❌ FCM HTTP ${res.status}: ${errBody}`);
    console.error(`Token prefix: ${token.substring(0, 25)}...`);
    return { ok: false, error: `${res.status}: ${errBody.substring(0, 300)}` };
  }
  const successBody = await res.text();
  console.log(`✅ FCM sent: ${successBody.substring(0, 150)}`);
  return { ok: true };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // 🔒 قفل داخلي (2026-07-27): المتصل الشرعي الوحيد = دالة send_push_notification
  // في قاعدة البيانات عبر pg_net وترسل x-push-secret من public.internal_config.
  // بدون القفل كان الـ edge relay مفتوح للسبام لأي حامل anon key.
  const expectedSecret = Deno.env.get("INTERNAL_PUSH_SECRET");
  if (!expectedSecret) {
    console.error("INTERNAL_PUSH_SECRET not configured");
    return json({ success: false, error: "PUSH_SECRET_NOT_CONFIGURED" }, 500);
  }
  if (req.headers.get("x-push-secret") !== expectedSecret) {
    return json({ success: false, error: "UNAUTHORIZED" }, 401);
  }

  try {
    const { uid, title, body, data } = (await req.json()) as NotifyPayload;
    if (!uid || !title || !body) {
      return json({ success: false, error: "MISSING_FIELDS" }, 400);
    }

    console.log(`📨 Sending to uid=${uid}, title="${title}"`);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1) جلب الـ tokens النشطة للمستخدم
    const { data: tokens, error: tErr } = await supabase.rpc(
      "get_user_device_tokens",
      { p_uid: uid }
    );
    if (tErr) {
      console.error("❌ get_user_device_tokens error:", tErr);
      return json({ success: false, error: "FETCH_TOKENS_FAILED" }, 500);
    }
    if (!tokens || tokens.length === 0) {
      console.log("⚠️ No active devices for user");
      return json({ success: true, sent: 0, message: "no active devices" });
    }

    console.log(`📱 Found ${tokens.length} active device(s)`);

    // 2) الحصول على access token
    const projectId = Deno.env.get("FIREBASE_PROJECT_ID");
    if (!projectId) {
      return json({
        success: true,
        devMode: true,
        message: "FIREBASE_PROJECT_ID not set",
        wouldSendTo: tokens.length,
      });
    }

    let accessToken: string;
    try {
      accessToken = await getAccessToken();
      console.log("🔑 Got Google access token");
    } catch (e) {
      console.error("❌ getAccessToken failed:", e);
      return json({
        success: false,
        error: "GOOGLE_AUTH_FAILED",
        details: String(e).substring(0, 300),
      }, 500);
    }

    // 3) الإرسال لكل توكن
    let sent = 0;
    let failed = 0;
    const errors: string[] = [];
    const invalidTokens: string[] = [];

    for (const t of tokens as Array<{ device_token: string; platform: string }>) {
      const res = await sendFCM(
        accessToken,
        projectId,
        t.device_token,
        title,
        body,
        data
      );
      if (res.ok) sent++;
      else {
        failed++;
        if (res.error) errors.push(res.error);
        if (res.error && (
          res.error.includes("404") ||
          res.error.includes("NOT_FOUND") ||
          res.error.includes("UNREGISTERED") ||
          res.error.includes("INVALID_ARGUMENT")
        )) {
          invalidTokens.push(t.device_token);
        }
      }
    }

    // 4) إلغاء التوكنز الفاسدة تلقائياً — مقيّد بـ uid حتى لا تُشطَّب
    //    سجلات مستخدمين آخرين عند أي 404 عابر من FCM (2026-07-27)
    if (invalidTokens.length > 0) {
      try {
        await supabase
          .from("user_devices")
          .update({ is_active: false })
          .eq("uid", uid)
          .in("device_token", invalidTokens);
        console.log(`🧹 Deactivated ${invalidTokens.length} invalid tokens`);
      } catch (e) {
        console.error("Failed to deactivate invalid tokens:", e);
      }
    }

    return json({
      success: true,
      sent,
      failed,
      total: tokens.length,
      ...(errors.length > 0 && { errors }),
      ...(invalidTokens.length > 0 && { cleanedUp: invalidTokens.length }),
    });
  } catch (e) {
    console.error("❌ INTERNAL:", e);
    return json({ success: false, error: "INTERNAL", details: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
