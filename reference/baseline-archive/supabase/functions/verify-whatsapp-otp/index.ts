// ════════════════════════════════════════════════════════════════════════════
// Edge Function: verify-whatsapp-otp
// يستقبل: { phone: "+963XXXXXXXXX", code: "123456" }
// يتحقق عبر verify_otp_v2 و upsert_user_after_otp
// يُصدر Supabase session (access_token + refresh_token) عبر admin createUser/generateLink
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
    const { phone, code } = await req.json();

    if (!phone || !code) {
      return json({ success: false, error: "MISSING_FIELDS" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 1) التحقق من الكود
    const { data: ok, error: vErr } = await supabase.rpc("verify_otp_v2", {
      p_identifier: phone,
      p_code: code,
    });

    if (vErr || !ok) {
      return json({ success: false, error: "INVALID_OR_EXPIRED_OTP" }, 401);
    }

    // 2) إنشاء/جلب المستخدم بجدول users
    const { data: upsertRows, error: uErr } = await supabase.rpc(
      "upsert_user_after_otp",
      { p_identifier: phone, p_channel: "whatsapp" }
    );

    if (uErr) {
      return json(
        { success: false, error: "UPSERT_FAILED", details: uErr.message },
        500
      );
    }

    const row = Array.isArray(upsertRows) ? upsertRows[0] : upsertRows;
    const userId: string = row.user_id;
    const isNew: boolean = row.is_new;

    // 3) إنشاء/تحديث المستخدم بـ Supabase Auth (بإيميل وهمي مبني على رقم الهاتف)
    //    حتى يحصل على session حقيقي.
    const pseudoEmail = `wa_${phone.replace(/\D/g, "")}@whatsapp.local`;

    // محاولة إنشاء (لو موجود سنحصل على خطأ ونتجاهله)
    await supabase.auth.admin.createUser({
      email: pseudoEmail,
      phone: phone,
      email_confirm: true,
      phone_confirm: true,
      user_metadata: { app_user_id: userId, channel: "whatsapp" },
    }).catch(() => {});

    // 4) توليد magic link لاسترجاع session
    const { data: linkData, error: linkErr } =
      await supabase.auth.admin.generateLink({
        type: "magiclink",
        email: pseudoEmail,
      });

    if (linkErr || !linkData) {
      return json(
        { success: false, error: "SESSION_FAILED", details: linkErr?.message },
        500
      );
    }

    // 5) رد للعميل: token hash يقبله Flutter عبر verifyOTP type=magiclink
    return json({
      success: true,
      userId,
      isNew,
      session: {
        email: pseudoEmail,
        token_hash: linkData.properties?.hashed_token,
        action_link: linkData.properties?.action_link,
      },
    });
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
