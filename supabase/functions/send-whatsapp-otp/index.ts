// ════════════════════════════════════════════════════════════════════════════
// Edge Function: send-whatsapp-otp
// يستقبل: { phone: "+963XXXXXXXXX" }
// يولّد OTP عبر generate_otp_v2 ويرسله بواتساب عبر Meta WhatsApp Cloud API
// ════════════════════════════════════════════════════════════════════════════
// متغيرات البيئة المطلوبة (تُضبط في Supabase Dashboard → Edge Functions → Secrets):
//   META_WHATSAPP_TOKEN       — Access Token دائم من Meta
//   META_PHONE_NUMBER_ID      — معرّف رقم الواتساب الرسمي
//   META_OTP_TEMPLATE_NAME    — اسم قالب OTP المعتمد من Meta (مثلاً: "otp_login")
//   META_OTP_TEMPLATE_LANG    — لغة القالب (مثلاً: "ar")
//   SUPABASE_URL              — موجود تلقائياً
//   SUPABASE_SERVICE_ROLE_KEY — موجود تلقائياً
// ════════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { phone } = await req.json();

    if (!phone || typeof phone !== "string" || !phone.startsWith("+")) {
      return json({ success: false, error: "INVALID_PHONE" }, 400);
    }

    // 1) توليد OTP عبر RPC
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: code, error: rpcErr } = await supabase.rpc(
      "generate_otp_v2",
      { p_identifier: phone, p_channel: "whatsapp" }
    );

    if (rpcErr) {
      return json(
        { success: false, error: "OTP_GENERATION_FAILED", details: rpcErr.message },
        500
      );
    }

    // 2) إرسال عبر Meta WhatsApp Cloud API
    const token = Deno.env.get("META_WHATSAPP_TOKEN");
    const phoneNumberId = Deno.env.get("META_PHONE_NUMBER_ID");
    const templateName =
      Deno.env.get("META_OTP_TEMPLATE_NAME") ?? "otp_login";
    const templateLang = Deno.env.get("META_OTP_TEMPLATE_LANG") ?? "ar";

    if (!token || !phoneNumberId) {
      // 🔒 SEC-008 (2026-08-14): نفس فخّ send-sms-otp — كان يُرجع الرمز في
      // جسم الاستجابة حين تغيب أسرار Meta. انتهاء توكن أو خطأ بيئة يحوّل
      // المسار إلى كاشف رموز للعموم. الرمز لا يغادر السيرفر الآن، والعطل
      // يُعلَن صراحةً (503) بدل التظاهر بالنجاح (§13).
      console.warn("OTP_GATEWAY_NOT_CONFIGURED (whatsapp) — code kept server-side only");
      const devEcho = (Deno.env.get("ALLOW_OTP_ECHO") ?? "") === "true";
      return json({
        success: false,
        error: "OTP_GATEWAY_NOT_CONFIGURED",
        detail: "تعذّر إرسال رمز التحقق عبر واتساب — البوابة غير مهيّأة.",
        ...(devEcho ? { devMode: true, otp: code } : {}),
      }, 503);
    }

    const waUrl = `https://graph.facebook.com/v20.0/${phoneNumberId}/messages`;
    const payload = {
      messaging_product: "whatsapp",
      to: phone.replace(/^\+/, ""),
      type: "template",
      template: {
        name: templateName,
        language: { code: templateLang },
        components: [
          {
            type: "body",
            parameters: [{ type: "text", text: String(code) }],
          },
          {
            type: "button",
            sub_type: "url",
            index: "0",
            parameters: [{ type: "text", text: String(code) }],
          },
        ],
      },
    };

    const waRes = await fetch(waUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const waJson = await waRes.json();

    if (!waRes.ok) {
      console.error("Meta API error:", waJson);
      return json(
        {
          success: false,
          error: "WHATSAPP_SEND_FAILED",
          details: waJson?.error?.message ?? "unknown",
        },
        502
      );
    }

    return json({ success: true, messageId: waJson?.messages?.[0]?.id });
  } catch (e) {
    console.error(e);
    return json({ success: false, error: "INTERNAL", details: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
