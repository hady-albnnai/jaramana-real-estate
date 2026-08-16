// Edge Function: admin-payments
// الغرض: نقل إدارة المدفوعات من RPC مباشر إلى Edge Function محمية بجلسة موظف.

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
  minRole = 5,
): Promise<{ ok: true; adminUid: string; role: number } | { ok: false; response: Response }> {
  const requestedAdminUid = (body.admin_uid ?? body.adminUid ?? body.user_uid ?? body.userUid ?? body.admin_id ?? body.adminId)?.toString() ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
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

  const sessionToken = (body.staff_session_token ?? body.staffSessionToken)?.toString() ?? (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");
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

// ملاحظة 2026-07-27: أُزيل notifyPaymentDecision — الإشعار الداخلي + push يتولاهما
// trigger trg_payment_approved على جدول payments (مصدر واحد للحقيقة، بلا تكرار).

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
    const actor = await validateActor(req, supabaseAdmin, body, 5);
    if (!actor.ok) return actor.response;

    const adminUid = actor.adminUid;

    if (action === "list") {
      const { data, error } = await supabaseAdmin.rpc("get_admin_payments_internal", {
        p_admin_uid: adminUid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, payments: data ?? [] });
    }

    if (action === "signed_proof_url") {
      const paymentId = (body.payment_id ?? body.paymentId)?.toString() ?? "";
      if (!paymentId) return json({ success: false, error: "PAYMENT_ID_REQUIRED" }, 400);

      // 🔒 إثباتات الدفع في bucket خاص. التطبيق يستخدم staff_session لا JWT
      // من Supabase Auth، لذلك createSignedUrl المباشر من العميل يفشل بـRLS.
      // نقرأ المسار من سجل الدفعة نفسه (لا نقبل path من العميل) ثم نوقّعه
      // بمفتاح الخدمة بعد نجاح حارس الإدارة أعلاه.
      const { data: payment, error: paymentError } = await supabaseAdmin
        .from("payments")
        .select("proof")
        .eq("id", paymentId)
        .maybeSingle();
      if (paymentError) return json({ success: false, error: paymentError.message }, 400);
      const proof = payment?.proof?.toString().trim() ?? "";
      if (!proof) return json({ success: false, error: "PAYMENT_PROOF_NOT_FOUND" }, 404);
      if (proof.startsWith("http://") || proof.startsWith("https://")) {
        return json({ success: true, signed_url: proof });
      }

      const { data: signed, error: signError } = await supabaseAdmin.storage
        .from("payment_proofs")
        .createSignedUrl(proof, 3600);
      if (signError || !signed?.signedUrl) {
        return json({ success: false, error: signError?.message ?? "SIGNED_URL_FAILED" }, 400);
      }
      return json({ success: true, signed_url: signed.signedUrl });
    }

    if (action === "approve") {
      const paymentId = (body.payment_id ?? body.paymentId)?.toString() ?? "";
      if (!paymentId) return json({ success: false, error: "PAYMENT_ID_REQUIRED" }, 400);
      const { data, error } = await supabaseAdmin.rpc("approve_payment_final_v5", {
        p_payment_id: paymentId,
        p_admin_id: adminUid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const result = data && typeof data === "object" ? data as Record<string, unknown> : { success: data === true };
      if (result.success === true && result.consultation_id) {
        try {
          const consultationId = String(result.consultation_id);
          const channel = supabaseAdmin.channel(`consultation:${consultationId}`);
          await channel.send({ type: "broadcast", event: "session_changed", payload: { changed: true } });
          await supabaseAdmin.removeChannel(channel);
        } catch { /* Push/فتح الشاشة مساران احتياطيان */ }
      }
      // الإشعار يتم من trigger الدفع المناسب تلقائياً عند تحول sts
      return json(result);
    }

    // ─── IMP-001: عكس اعتماد دفعة (2026-08-14) ───
    // لم يكن هناك أي مسار للتراجع: احتيال يُكتشف بعد الاعتماد كان يتطلّب
    // تعديل SQL يدوياً على قاعدة الإنتاج — أخطر ما يمكن طلبه من مالك التطبيق.
    // مدير فقط (role=6) + سبب إلزامي + سجل تدقيق + إشعار للمستخدم + تراجع
    // فعلي عن الأثر (الباقة تُلغى، الإعلان المميّز يُسحب).
    if (action === "reverse") {
      const paymentId = (body.payment_id ?? body.paymentId)?.toString() ?? "";
      const reason = (body.reason ?? "").toString();
      if (!paymentId) return json({ success: false, error: "PAYMENT_ID_REQUIRED" }, 400);
      if (!reason.trim()) return json({ success: false, error: "REVERSAL_REASON_REQUIRED" }, 400);
      const { data, error } = await supabaseAdmin.rpc("admin_reverse_payment_v2", {
        p_admin_uid: adminUid,
        p_payment_id: paymentId,
        p_reason: reason,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json(data && typeof data === "object" ? data as Record<string, unknown> : { success: true });
    }

    if (action === "reject") {
      const paymentId = (body.payment_id ?? body.paymentId)?.toString() ?? "";
      if (!paymentId) return json({ success: false, error: "PAYMENT_ID_REQUIRED" }, 400);
      // سبب الرفض يُخزَّن في meta ويصل للمستخدم كإشعار
      const reason = (body.reason ?? "")?.toString() ?? "";
      const { data, error } = await supabaseAdmin.rpc("admin_reject_payment_internal", {
        p_admin_uid: adminUid,
        p_payment_id: paymentId,
        p_reason: reason,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      // الإشعار يتم من trg_payment_approved تلقائياً ويقرأ السبب من meta
      return json({ success: data === true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
