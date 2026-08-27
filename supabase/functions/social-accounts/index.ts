// Edge Function: social-accounts — إدارة حسابات النشر الاجتماعي من داخل التطبيق
//
// الأفعال (action):
//   list   → كل الحسابات غير المحذوفة (التوكن مقنّع: آخر 4 محارف فقط)
//   save   → إضافة حساب جديد (id فارغ) أو تعديل موجود (id موجود) + تحقق تلقائي
//   verify → إعادة التحقق من حساب موجود لدى Meta (يرجع اسم الصفحة/الحساب الحقيقي)
//   delete → حذف ناعم (i_del=1)
//
// الأمان:
//   • التحقق من الجلسة بنمط admin-config: JWT أو staff_session، بحد أدنى role≥5.
//   • access_token لا يُعاد كاملاً للعميل أبداً — فقط طوله وآخر 4 محارف.
//   • عند التعديل: إن أُرسل التوكن فارغاً يُحتفظ بالقديم (لا يُمسّ).
//   • سجل التدقيق (activity_log) بدون أي قيمة توكن: أكواد 130=حفظ، 131=تحقق، 132=حذف.
//
// الترتيب: يتطلب migration 2026_08_27_social_accounts_management.sql أولاً.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// أكواد سجل التدقيق (activity_log) — 101-107 عروض/سوشيال، 120 إعدادات نصية.
const ACT_SAVE = 130;
const ACT_VERIFY = 131;
const ACT_DELETE = 132;

const PLATFORMS = new Set(["facebook", "instagram"]);

function env(name: string, fallback?: string): string {
  return Deno.env.get(name) ?? (fallback ? Deno.env.get(fallback) ?? "" : "");
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// نفس نمط validateActor المعتمد في admin-config (JWT ثم staff session)
async function validateActor(
  req: Request,
  supabaseAdmin: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
  minRole = 5, // مدير + نائب فقط — إدارة توكنات النشر صلاحية حساسة
): Promise<{ ok: true; adminUid: string; role: number } | { ok: false; response: Response }> {
  const requestedAdminUid =
    (body.admin_uid ?? body.adminUid ?? body.user_uid ?? body.userUid ?? body.admin_id ?? body.adminId)
      ?.toString() ?? "";
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
      response: json({
        success: false,
        error: data?.error ?? error?.message ?? "INVALID_ADMIN_SESSION",
      }, 401),
    };
  }

  return { ok: true, adminUid: requestedAdminUid, role: Number(data.role) };
}

function cleanText(v: unknown, maxLen = 300): string {
  return (v ?? "").toString().replace(/[\u0000-\u001F\u007F]/g, "").trim().slice(0, maxLen);
}

/// استدعاء GET على Graph API للتحقق من الحساب وجلب اسمه الحقيقي.
async function graphGet(path: string, token: string): Promise<Record<string, unknown>> {
  const version = (Deno.env.get("META_GRAPH_API_VERSION") ?? "").trim() || "v25.0";
  const response = await fetch(`https://graph.facebook.com/${version}/${path}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const payload = await response.json().catch(() => ({})) as Record<string, unknown>;
  if (!response.ok || payload.error) {
    const graphError = payload.error as Record<string, unknown> | undefined;
    const message = String(graphError?.message ?? `META_HTTP_${response.status}`);
    const code = graphError?.code ? ` (${graphError.code})` : "";
    throw new Error(`${message}${code}`);
  }
  return payload;
}

/// التحقق من صحة (المعرف + التوكن) لدى Meta وإرجاع الاسم الحقيقي.
async function verifyAccount(
  platform: string,
  externalId: string,
  token: string,
): Promise<{ ok: true; displayName: string } | { ok: false; error: string }> {
  try {
    const fields = platform === "instagram" ? "id,username" : "id,name";
    const payload = await graphGet(
      `${encodeURIComponent(externalId)}?fields=${fields}`,
      token,
    );
    const id = String(payload.id ?? "");
    if (!id) return { ok: false, error: "META_VERIFY_EMPTY_RESPONSE" };
    const displayName = platform === "instagram"
      ? String(payload.username ?? "")
      : String(payload.name ?? "");
    return { ok: true, displayName: displayName || id };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}

/// تمثيل آمن للحساب في الردود — التوكن مقنّع دائماً.
function maskAccount(row: Record<string, unknown>): Record<string, unknown> {
  const token = String(row.access_token ?? "");
  const last4 = token.length >= 8 ? token.slice(-4) : "";
  return {
    id: row.id,
    platform: row.platform,
    name: row.name,
    accountExternalId: row.account_external_id,
    verifiedName: row.verified_name ?? "",
    tokenMasked: last4 ? `••••••••${last4}` : "",
    tokenLength: token.length,
    isActive: row.is_active === true,
    isVerified: row.is_verified === true,
    lastError: row.last_error ?? "",
    lastVerifiedAt: row.last_verified_at,
    tsCrt: row.ts_crt,
  };
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
    const actor = await validateActor(req, supabaseAdmin, body);
    if (!actor.ok) return actor.response;
    const adminUid = actor.adminUid;

    // ─── Action: list ───
    if (action === "list") {
      const { data, error } = await supabaseAdmin
        .from("social_accounts")
        .select("*")
        .eq("i_del", 0)
        .order("ts_crt", { ascending: true });
      if (error) return json({ success: false, error: error.message }, 400);
      const accounts = (data ?? []).map((row: Record<string, unknown>) => maskAccount(row));
      return json({ success: true, accounts });
    }

    // ─── Action: save (إضافة أو تعديل) ───
    if (action === "save") {
      const id = (body.id ?? "").toString().trim();
      const platform = (body.platform ?? "").toString().trim();
      const name = cleanText(body.name, 100);
      const accountExternalId = (body.account_external_id ?? body.accountExternalId ?? "")
        .toString().trim();
      const accessTokenInput = (body.access_token ?? body.accessToken ?? "")
        .toString().replace(/[\u0000-\u001F\u007F]/g, "").trim();
      const isActive = body.is_active !== false && body.isActive !== false;

      if (!PLATFORMS.has(platform)) {
        return json({ success: false, error: "INVALID_PLATFORM" }, 400);
      }
      if (name.length < 1) {
        return json({ success: false, error: "ACCOUNT_NAME_REQUIRED" }, 400);
      }
      if (!/^[A-Za-z0-9._-]{3,64}$/.test(accountExternalId)) {
        return json({ success: false, error: "INVALID_ACCOUNT_EXTERNAL_ID" }, 400);
      }

      // التعديل: التوكن الفارغ يعني «احتفظ بالقديم».
      let existing: Record<string, unknown> | null = null;
      if (id) {
        const { data: row } = await supabaseAdmin
          .from("social_accounts")
          .select("*")
          .eq("id", id)
          .eq("i_del", 0)
          .maybeSingle();
        if (!row) return json({ success: false, error: "ACCOUNT_NOT_FOUND" }, 404);
        existing = row as Record<string, unknown>;
        if (accessTokenInput.length === 0) {
          if (String(existing.access_token ?? "").length < 10) {
            return json({ success: false, error: "ACCESS_TOKEN_REQUIRED" }, 400);
          }
        }
      } else if (accessTokenInput.length < 10) {
        return json({ success: false, error: "ACCESS_TOKEN_REQUIRED" }, 400);
      }
      if (accessTokenInput && (accessTokenInput.length < 10 || accessTokenInput.length > 4096)) {
        return json({ success: false, error: "INVALID_ACCESS_TOKEN" }, 400);
      }

      const values: Record<string, unknown> = {
        platform,
        name,
        account_external_id: accountExternalId,
        is_active: isActive,
        // أي تعديل يُسقط حالة التحقق السابقة إلى أن ينجح التحقق الجديد أدناه.
        is_verified: false,
        last_error: "",
        ts_upd: new Date().toISOString(),
      };
      if (accessTokenInput) values.access_token = accessTokenInput;

      let savedRow: Record<string, unknown> | null = null;
      if (id) {
        const { data: row, error: updateErr } = await supabaseAdmin
          .from("social_accounts")
          .update(values)
          .eq("id", id)
          .eq("i_del", 0)
          .select("*")
          .single();
        if (updateErr || !row) {
          return json({ success: false, error: updateErr?.message ?? "ACCOUNT_SAVE_FAILED" }, 400);
        }
        savedRow = row as Record<string, unknown>;
      } else {
        const { data: row, error: insertErr } = await supabaseAdmin
          .from("social_accounts")
          .insert(values)
          .select("*")
          .single();
        if (insertErr || !row) {
          return json({ success: false, error: insertErr?.message ?? "ACCOUNT_SAVE_FAILED" }, 400);
        }
        savedRow = row as Record<string, unknown>;
      }

      // تحقق تلقائي فور الحفظ — يكشف التوكن الخاطئ مباشرة.
      const tokenForVerify = String(savedRow.access_token ?? "");
      const verification = await verifyAccount(platform, accountExternalId, tokenForVerify);
      if (verification.ok) {
        const { error: verifyUpdateErr } = await supabaseAdmin
          .from("social_accounts")
          .update({
            is_verified: true,
            verified_name: verification.displayName,
            last_error: "",
            last_verified_at: new Date().toISOString(),
            ts_upd: new Date().toISOString(),
          })
          .eq("id", String(savedRow.id));
        if (!verifyUpdateErr) {
          savedRow = {
            ...savedRow,
            is_verified: true,
            verified_name: verification.displayName,
            last_error: "",
          };
        }
      } else {
        await supabaseAdmin
          .from("social_accounts")
          .update({
            is_verified: false,
            verified_name: "",
            last_error: verification.error.slice(0, 1000),
            ts_upd: new Date().toISOString(),
          })
          .eq("id", String(savedRow.id));
        savedRow = { ...savedRow, is_verified: false, last_error: verification.error };
      }

      try {
        await supabaseAdmin.rpc("log_admin_action", {
          p_admin_uid: adminUid,
          p_act: ACT_SAVE,
          p_det: `حفظ حساب نشر (${platform}): ${name}${verification.ok ? ` — تحقق ناجح: ${verification.displayName}` : " — التحقق فشل"}`,
          p_ref_id: String(savedRow.id ?? ""),
          p_ref_col: "social_accounts",
        });
      } catch (_) {
        // التدقيق لا يُفشل العملية.
      }

      return json({
        success: true,
        account: maskAccount(savedRow),
        verified: verification.ok,
        verifiedName: verification.ok ? verification.displayName : "",
        verifyError: verification.ok ? undefined : verification.error,
      });
    }

    // ─── Action: verify ───
    if (action === "verify") {
      const id = (body.id ?? "").toString().trim();
      if (!id) return json({ success: false, error: "ACCOUNT_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("social_accounts")
        .select("*")
        .eq("id", id)
        .eq("i_del", 0)
        .maybeSingle();
      if (!row) return json({ success: false, error: "ACCOUNT_NOT_FOUND" }, 404);
      const account = row as Record<string, unknown>;

      const verification = await verifyAccount(
        String(account.platform),
        String(account.account_external_id),
        String(account.access_token),
      );
      const updates = verification.ok
        ? {
          is_verified: true,
          verified_name: verification.displayName,
          last_error: "",
          last_verified_at: new Date().toISOString(),
          ts_upd: new Date().toISOString(),
        }
        : {
          is_verified: false,
          verified_name: "",
          last_error: verification.error.slice(0, 1000),
          ts_upd: new Date().toISOString(),
        };
      const { error: updateErr } = await supabaseAdmin
        .from("social_accounts")
        .update(updates)
        .eq("id", id);
      if (updateErr) return json({ success: false, error: updateErr.message }, 400);

      try {
        await supabaseAdmin.rpc("log_admin_action", {
          p_admin_uid: adminUid,
          p_act: ACT_VERIFY,
          p_det: `تحقق من حساب نشر (${String(account.platform)}): ${String(account.name)}${verification.ok ? ` — ناجح: ${verification.displayName}` : " — فاشل"}`,
          p_ref_id: id,
          p_ref_col: "social_accounts",
        });
      } catch (_) {}

      return json({
        success: true,
        verified: verification.ok,
        verifiedName: verification.ok ? verification.displayName : "",
        verifyError: verification.ok ? undefined : verification.error,
        account: maskAccount({ ...account, ...updates }),
      });
    }

    // ─── Action: delete (ناعم) ───
    if (action === "delete") {
      const id = (body.id ?? "").toString().trim();
      if (!id) return json({ success: false, error: "ACCOUNT_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("social_accounts")
        .select("id,platform,name")
        .eq("id", id)
        .eq("i_del", 0)
        .maybeSingle();
      if (!row) return json({ success: false, error: "ACCOUNT_NOT_FOUND" }, 404);

      const { error: deleteErr } = await supabaseAdmin
        .from("social_accounts")
        .update({ i_del: 1, is_active: false, ts_upd: new Date().toISOString() })
        .eq("id", id);
      if (deleteErr) return json({ success: false, error: deleteErr.message }, 400);

      try {
        await supabaseAdmin.rpc("log_admin_action", {
          p_admin_uid: adminUid,
          p_act: ACT_DELETE,
          p_det: `حذف حساب نشر (${String(row.platform)}): ${String(row.name)}`,
          p_ref_id: id,
          p_ref_col: "social_accounts",
        });
      } catch (_) {}

      return json({ success: true });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }, 500);
  }
});
