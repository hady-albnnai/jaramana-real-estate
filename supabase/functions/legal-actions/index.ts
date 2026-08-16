// Edge Function: legal-actions
// الغرض: نقطة الوصول الآمنة لعمليات القسم القانوني وتعقيب المعاملات ومسارات المحامين والمعقبين.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SupabaseAdmin = ReturnType<typeof createClient>;

function env(name: string, fallback?: string): string {
  return Deno.env.get(name) ?? (fallback ? Deno.env.get(fallback) ?? "" : "");
}

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// 📄 اسم الوثيقة العربي من الـchecklist بدل المفتاح البرمجي (2026-08-14).
/// كانت الإشعارات تعرض `"tabo"` و`"kharita"` — رموز لا يفهمها المحامي ولا
/// المعقّب، رغم أن `title` العربي مخزَّن في نفس البند.
function itemTitleFromChecklist(checklist: unknown, itemKey: string): string {
  try {
    const arr = Array.isArray(checklist) ? checklist : [];
    for (const it of arr) {
      const o = it as Record<string, unknown>;
      if (String(o?.key ?? "") === itemKey) {
        const t = String(o?.title ?? "").trim();
        if (t) return t;
      }
    }
  } catch { /* تجاهل */ }
  return itemKey; // سقوط آمن
}

/// ⚖️ أسعار الاستشارة ومدتها من app_config.main.legalPrice (أُضيف 2026-08-14).
/// المصدر الوحيد للحقيقة — الواجهة تعرض والسيرفر يفرض من نفس المكان.
/// القيم الافتراضية تطابق الأسعار التاريخية حتى لو غاب المفتاح.
async function getLegalPrices(
  supabaseAdmin: ReturnType<typeof createClient>,
): Promise<{ phone: number; onsite: number; renew: number; durationMins: number }> {
  const fallback = { phone: 500, onsite: 2000, renew: 500, durationMins: 15 };
  try {
    const { data } = await supabaseAdmin
      .from("app_config").select("value").eq("key", "main").maybeSingle();
    const cfg = (data?.value as Record<string, unknown>)?.legalPrice;
    if (!cfg || typeof cfg !== "object") return fallback;
    const c = cfg as Record<string, unknown>;
    const num = (v: unknown, d: number) => {
      const n = Number(v);
      return Number.isFinite(n) && n >= 0 ? n : d;
    };
    return {
      phone: num(c.phone, fallback.phone),
      onsite: num(c.onsite, fallback.onsite),
      renew: num(c.renew, fallback.renew),
      durationMins: Math.max(1, num(c.durationMins, fallback.durationMins)),
    };
  } catch {
    return fallback;
  }
}

function base64ToUint8Array(base64: string): Uint8Array {
  const clean = base64.includes(",") ? base64.split(",").pop() ?? "" : base64;
  const binary = atob(clean);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function readM4aDurationSeconds(bytes: Uint8Array): number | null {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const typeAt = (offset: number) => String.fromCharCode(
    bytes[offset + 4], bytes[offset + 5], bytes[offset + 6], bytes[offset + 7],
  );
  const scan = (start: number, end: number): number | null => {
    let offset = start;
    while (offset + 8 <= end) {
      let size = view.getUint32(offset, false);
      const type = typeAt(offset);
      let header = 8;
      if (size === 1) {
        if (offset + 16 > end) return null;
        const large = view.getBigUint64(offset + 8, false);
        if (large > BigInt(Number.MAX_SAFE_INTEGER)) return null;
        size = Number(large);
        header = 16;
      } else if (size === 0) {
        size = end - offset;
      }
      if (size < header || offset + size > end) return null;
      if (type === "mvhd") {
        const content = offset + header;
        const version = bytes[content];
        const timescaleOffset = content + (version === 1 ? 20 : 12);
        const durationOffset = content + (version === 1 ? 24 : 16);
        if (durationOffset + (version === 1 ? 8 : 4) > offset + size) return null;
        const timescale = view.getUint32(timescaleOffset, false);
        if (!timescale) return null;
        const duration = version === 1
          ? Number(view.getBigUint64(durationOffset, false))
          : view.getUint32(durationOffset, false);
        return duration / timescale;
      }
      if (["moov", "trak", "mdia"].includes(type)) {
        const nested = scan(offset + header, offset + size);
        if (nested != null) return nested;
      }
      offset += size;
    }
    return null;
  };
  try { return scan(0, bytes.length); } catch { return null; }
}

function safeImageContentType(value: unknown): string {
  const contentType = typeof value === "string" ? value.toLowerCase() : "image/jpeg";
  return ["image/jpeg", "image/jpg", "image/png", "image/webp"].includes(contentType)
    ? (contentType === "image/jpg" ? "image/jpeg" : contentType)
    : "image/jpeg";
}

function detectImageContentType(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 8 &&
    bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e &&
    bytes[3] === 0x47 && bytes[4] === 0x0d && bytes[5] === 0x0a &&
    bytes[6] === 0x1a && bytes[7] === 0x0a
  ) return "image/png";
  if (
    bytes.length >= 12 &&
    String.fromCharCode(...bytes.slice(0, 4)) === "RIFF" &&
    String.fromCharCode(...bytes.slice(8, 12)) === "WEBP"
  ) return "image/webp";
  if (
    bytes.length >= 3 &&
    bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
  ) return "image/jpeg";
  return null;
}

function safeStorageName(value: string): string {
  return value.replace(/[^a-zA-Z0-9_.-]/g, "_").slice(0, 80) || "item";
}

async function signExpeditingTaskAttachments(
  supabaseAdmin: SupabaseAdmin,
  tasks: unknown,
): Promise<unknown[]> {
  const list = Array.isArray(tasks) ? tasks : [];
  const result: unknown[] = [];
  for (const rawTask of list) {
    const task = rawTask && typeof rawTask === "object" ? { ...(rawTask as Record<string, unknown>) } : rawTask;
    if (!task || typeof task !== "object") {
      result.push(task);
      continue;
    }
    const record = task as Record<string, unknown>;
    const checklist = Array.isArray(record.checklist) ? record.checklist : [];
    record.checklist = await Promise.all(checklist.map(async (rawItem) => {
      const item = rawItem && typeof rawItem === "object" ? { ...(rawItem as Record<string, unknown>) } : rawItem;
      if (!item || typeof item !== "object") return item;
      const itemRecord = item as Record<string, unknown>;
      const path = (itemRecord.attachment_url ?? "").toString();
      if (path && !path.startsWith("http")) {
        const { data } = await supabaseAdmin.storage
          .from("expediting_docs")
          .createSignedUrl(path, 3600);
        if (data?.signedUrl) itemRecord.attachment_signed_url = data.signedUrl;
      }
      return itemRecord;
    }));
    result.push(record);
  }
  return result;
}

async function getUserRole(
  supabaseAdmin: SupabaseAdmin,
  uid: string,
): Promise<number | null> {
  const { data, error } = await supabaseAdmin
    .from("users")
    .select("role, sts, i_del")
    .eq("id", uid)
    .eq("i_del", 0)
    .single();

  if (error || !data || Number(data.sts) !== 0) return null;
  return Number(data.role);
}

function canManageLawyerProfiles(role: number): boolean {
  // الإدارة العليا فقط: نائب مدير ومدير. لا يدخل lawyer=7 أو expediter=8 في صلاحيات الإدارة.
  return role === 5 || role === 6;
}

function isLawyer(role: number): boolean {
  return role === 7;
}

function isExpediter(role: number): boolean {
  return role === 8;
}

async function validateUser(
  req: Request,
  supabaseAdmin: SupabaseAdmin,
  requestedUid: string,
  body: Record<string, unknown> = {},
): Promise<{ ok: true; uid: string; role: number } | { ok: false; response: Response }> {
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";

  if (bearer && bearer !== "undefined" && bearer !== "null" && bearer !== "anon_key_here") {
    const { data: userData, error } = await supabaseAdmin.auth.getUser(bearer);
    const uid = userData?.user?.id;
    if (!error && uid) {
      if (requestedUid && requestedUid !== uid) {
        return { ok: false, response: json({ success: false, error: "UNAUTHORIZED_ACCESS" }, 403) };
      }
      const role = await getUserRole(supabaseAdmin, uid);
      if (role == null) {
        return { ok: false, response: json({ success: false, error: "USER_INACTIVE" }, 401) };
      }
      return { ok: true, uid, role };
    }
  }

  const sessionToken = (body?.staff_session_token ?? body?.staffSessionToken ?? body?.session_token ?? body?.sessionToken)?.toString()
    || (authHeader && !authHeader.startsWith("Bearer ") ? authHeader.trim() : "");

  if (sessionToken && sessionToken !== "anon_key_here" && sessionToken !== "undefined" && sessionToken !== "null") {
    const { data, error } = await supabaseAdmin.rpc("validate_staff_session", {
      p_token: sessionToken,
      p_user_uid: requestedUid,
      p_min_role: 0,
    });

    if (!error && data && data.success === true) {
      return { ok: true, uid: data.user_id, role: Number(data.role) };
    }
  }

  return { ok: false, response: json({ success: false, error: "AUTH_TOKEN_REQUIRED" }, 401) };
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
    const requestedUid = (body.user_uid ?? body.userUid ?? body.admin_uid ?? body.adminUid)?.toString() ?? "";

    if (!requestedUid) return json({ success: false, error: "USER_UID_REQUIRED" }, 400);

    const actor = await validateUser(req, supabaseAdmin, requestedUid, body);
    if (!actor.ok) return actor.response;
    const uid = actor.uid;
    const role = actor.role;

    // ─── المحامين النشطين (إخفاء واتساب عن المستخدم العادي) ───
    if (action === "get_active_lawyers") {
      const { data, error } = await supabaseAdmin.rpc("get_active_lawyers");
      if (error) return json({ success: false, error: error.message }, 400);
      const lawyers = (data ?? []) as Record<string, unknown>[];
      // 🔒 2026-08-14: كان يحجب الواتساب والعنوان فقط ويترك **الاسم الحقيقي
      // والهاتف** — أي أن هوية المحامي تتسرّب للمستخدم رغم قرار الإخفاء.
      // الآن: المستخدم العادي يرى اللقب والتخصص والانشغال فقط.
      const hidePrivate = !isLawyer(role) && !canManageLawyerProfiles(role);
      const safeLawyers = hidePrivate
        ? await Promise.all(lawyers.map(async (l) => {
            const { data: alias } = await supabaseAdmin
              .rpc("lawyer_alias_for", { p_lawyer_uid: l.uid });
            return {
              uid: l.uid,
              alias: (alias as string | null) ?? "محامي المكتب",
              specialization: l.specialization,
              active_tasks_count: l.active_tasks_count,
              avl: l.avl,
            };
          }))
        : lawyers;
      return json({ success: true, lawyers: safeLawyers });
    }

    if (action === "admin_upsert_lawyer") {
      const targetUid = (body.target_uid ?? body.targetUid)?.toString() ?? "";
      const whatsapp = (body.whatsapp_phone ?? body.whatsappPhone)?.toString() ?? "";
      const address = (body.office_address ?? body.officeAddress ?? "").toString();
      const spec = (body.specialization ?? "عقارات وسيارات").toString();
      const avl = body.avl ?? {};

      if (!targetUid || !whatsapp) return json({ success: false, error: "MISSING_REQUIRED_FIELDS" }, 400);
      if (targetUid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      if (targetUid === uid && !isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      const { data, error } = await supabaseAdmin.rpc("admin_upsert_lawyer_profile", {
        p_admin_uid: uid,
        p_target_uid: targetUid,
        p_whatsapp: whatsapp,
        p_address: address,
        p_spec: spec,
        p_avl: avl,
      });

      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: data === true });
    }

    if (action === "update_checklist_item") {
      if (!isLawyer(role) && !isExpediter(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const itemKey = (body.item_key ?? body.itemKey)?.toString() ?? "";
      const status = Number(body.status ?? 0);
      const inputValue = (body.input_value ?? body.inputValue ?? "").toString();
      let attachmentUrl = (body.attachment_url ?? body.attachmentUrl ?? "").toString();
      const attachmentBase64 = (body.attachment_base64 ?? body.attachmentBase64 ?? "").toString();
      const notes = (body.notes ?? "").toString();

      if (!taskId || !itemKey) return json({ success: false, error: "TASK_ID_AND_ITEM_KEY_REQUIRED" }, 400);

      const { data: taskRow, error: taskError } = await supabaseAdmin
        .from("expediting_tasks")
        .select("id, lawyer_uid, expediter_uid")
        .eq("id", taskId)
        .single();
      if (taskError || !taskRow) return json({ success: false, error: "TASK_NOT_FOUND" }, 404);
      if (taskRow.lawyer_uid !== uid && taskRow.expediter_uid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      if (attachmentBase64) {
        const contentType = safeImageContentType(body.attachment_content_type ?? body.attachmentContentType);
        const ext = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
        const bytes = base64ToUint8Array(attachmentBase64);
        if (bytes.length > 8 * 1024 * 1024) return json({ success: false, error: "ATTACHMENT_TOO_LARGE" }, 413);
        const path = `${taskId}/${safeStorageName(itemKey)}_${Date.now()}.${ext}`;
        const { error: uploadError } = await supabaseAdmin.storage
          .from("expediting_docs")
          .upload(path, bytes, { contentType, cacheControl: "3600", upsert: true });
        if (uploadError) return json({ success: false, error: `ATTACHMENT_UPLOAD_FAILED: ${uploadError.message}` }, 400);
        attachmentUrl = path;
      }

      const { data: updateResult, error } = await supabaseAdmin.rpc("update_expediting_checklist_item", {
        p_actor_uid: uid,
        p_task_id: taskId,
        p_item_key: itemKey,
        p_status: status,
        p_input_value: inputValue,
        p_attachment_url: attachmentUrl,
        p_notes: notes,
      });

      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المحامي عند تحديث بند (إذا المعقّب هو من حدّث)
      if (isExpediter(role)) {
        const { data: taskRow } = await supabaseAdmin
          .from("expediting_tasks")
          .select("lawyer_uid, target_property_num, checklist")
          .eq("id", taskId)
          .maybeSingle();
        const lawyerToNotify = taskRow?.lawyer_uid?.toString() ?? "";
        const itemTitle = itemTitleFromChecklist(taskRow?.checklist, itemKey);
        if (lawyerToNotify) {
          const statusLabels: Record<number, string> = { 0: "مطلوب", 1: "قيد الاستخراج", 2: "تم الاستخراج ✅", 3: "عائق إداري ⚠️" };
          const sLabel = statusLabels[status] ?? "تحديث";
          const ref = taskRow?.target_property_num ? ` (${taskRow.target_property_num})` : "";
          await supabaseAdmin.from("notifications").insert({
            uid: lawyerToNotify, tp: 2, ttl: "📋 تحديث على مهمة تعقيب",
            bdy: `المعقّب حدّث «${itemTitle}» → ${sLabel}${ref}` +
              (notes ? ` — ${String(notes).slice(0, 120)}` : ""),
            ref_id: taskId, act: "expediting_item_updated", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
          });
          try {
            await supabaseAdmin.rpc("send_push_notification", {
              p_uid: lawyerToNotify, p_title: "📋 تحديث مهمة تعقيب",
              p_body: `${itemTitle} → ${sLabel}`,
              p_data: { act: "expediting_item_updated", ref_id: taskId },
            });
          } catch { /* non-critical */ }
        }
      }

      return json(updateResult as Record<string, unknown>);
    }

    if (action === "get_lawyer_profile") {
      if (!isLawyer(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const { data, error } = await supabaseAdmin.rpc("get_lawyer_profile", {
        p_lawyer_uid: uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, profile: data });
    }

    if (action === "get_available_expediters") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      const { data, error } = await supabaseAdmin.rpc("get_available_expediters");
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, expediters: data ?? [] });
    }

    // ─── إنشاء مهمة تعقيب (محامي + إدارة + فحص تكرار) ───
    if (action === "create_expediting_task") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      const expediterUid = (body.expediter_uid ?? body.expediterUid)?.toString() ?? "";
      const itemType = Number(body.item_type ?? body.itemType ?? 0);
      const propNum = (body.target_property_num ?? "").toString();
      const zone = (body.target_zone ?? "").toString();
      const notes = (body.lawyer_notes ?? body.notes ?? "").toString();
      const checklist = body.checklist ?? [];

      if (!expediterUid) return json({ success: false, error: "EXPEDITER_UID_REQUIRED" }, 400);

      // 🔒 فحص التكرار: نفس المعقّب + نفس رقم العقار + مهمة نشطة
      if (propNum) {
        const { data: dupes } = await supabaseAdmin
          .from("expediting_tasks")
          .select("id")
          .eq("expediter_uid", expediterUid)
          .eq("target_property_num", propNum)
          .in("status", [0, 1])
          .limit(1);
        if (dupes && dupes.length > 0) {
          return json({ success: false, error: "DUPLICATE_TASK_EXISTS", message: "يوجد مهمة نشطة لنفس المعقّب ونفس الرقم" }, 409);
        }
      }

      // المحامي = المستخدم الحالي (محامي) أو محامي مُحدد (إدارة) أو أول محامي متاح
      let lawyerUid = isLawyer(role) ? uid : ((body.lawyer_uid ?? body.lawyerUid)?.toString() ?? "");
      if (!lawyerUid && canManageLawyerProfiles(role)) {
        // الإدارة ما حددت محامي → أسند لأول محامي متاح (role=7 فقط)
        const { data: firstLawyer } = await supabaseAdmin
          .from("lawyer_profiles")
          .select("uid, users!inner(role)")
          .eq("is_active", true)
          .eq("users.role", 7)
          .limit(1);
        lawyerUid = firstLawyer?.[0]?.uid?.toString() ?? "";
        if (!lawyerUid) {
          return json({ success: false, error: "NO_ACTIVE_LAWYERS", message: "لا يوجد محامون نشطون" }, 400);
        }
      }
      if (!lawyerUid) lawyerUid = uid;

      const { data, error } = await supabaseAdmin.rpc("create_expediting_task_internal", {
        p_lawyer_uid: lawyerUid,
        p_expediter_uid: expediterUid,
        p_item_type: itemType,
        p_target_property_num: propNum,
        p_target_zone: zone,
        p_lawyer_notes: notes,
        p_checklist: checklist,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المعقّب بمهمة تعقيب جديدة
      const taskResult = data as Record<string, unknown>;
      const newTaskId = taskResult?.task_id?.toString() ?? "";
      if (newTaskId) {
        const itemLabel = itemType === 0 ? "عقار" : "سيارة";
        const refLabel = propNum ? ` — ${propNum}` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: expediterUid, tp: 2, ttl: "🏃 مهمة تعقيب جديدة",
          bdy: `كلّفك المحامي بمهمة استخراج ثبوتيات ${itemLabel}${refLabel} — ${zone || ""} (${(checklist as unknown[]).length} وثائق)`,
          ref_id: newTaskId, act: "expediting_task_assigned", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: expediterUid, p_title: "🏃 مهمة تعقيب جديدة",
            p_body: `${itemLabel}${refLabel} — ${(checklist as unknown[]).length} وثائق`,
            p_data: { act: "expediting_task_assigned", ref_id: newTaskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    if (action === "complete_expediting_task") {
      if (!isExpediter(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const notes = (body.expediter_notes ?? body.notes ?? "").toString();
      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("complete_expediting_task_internal", {
        p_expediter_uid: uid,
        p_task_id: taskId,
        p_notes: notes,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المحامي بأن المهمة اكتملت وبانتظار المراجعة
      const { data: taskRow } = await supabaseAdmin
        .from("expediting_tasks")
        .select("lawyer_uid, target_property_num, target_zone")
        .eq("id", taskId)
        .maybeSingle();
      const lawyerToNotify = taskRow?.lawyer_uid?.toString() ?? "";
      if (lawyerToNotify) {
        const ref = taskRow?.target_property_num ? ` — ${taskRow.target_property_num}` : "";
        const zoneTxt = taskRow?.target_zone ? ` (${taskRow.target_zone})` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: lawyerToNotify, tp: 2, ttl: "✅ مهمة تعقيب مكتملة — بانتظار المراجعة",
          bdy: `أنهى المعقّب مهمة الاستخراج${ref}${zoneTxt} — راجع الوثائق واعتمد المهمة أو اطلب إعادة.`,
          ref_id: taskId, act: "expediting_task_completed", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: lawyerToNotify, p_title: "✅ مهمة تعقيب مكتملة",
            p_body: `بانتظار مراجعتك${ref}`,
            p_data: { act: "expediting_task_completed", ref_id: taskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    if (action === "request_checklist_revision") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      const itemKey = (body.item_key ?? body.itemKey)?.toString() ?? "";
      const revisionNotes = (body.revision_notes ?? body.revisionNotes ?? body.notes ?? "").toString();
      if (!taskId || !itemKey) return json({ success: false, error: "TASK_ID_AND_ITEM_KEY_REQUIRED" }, 400);

      // الإدارة: نستخدم lawyer_uid الحقيقي للمهمة
      let effectiveLawyerUid = uid;
      if (canManageLawyerProfiles(role) && !isLawyer(role)) {
        const { data: taskRow } = await supabaseAdmin
          .from("expediting_tasks").select("lawyer_uid").eq("id", taskId).maybeSingle();
        effectiveLawyerUid = taskRow?.lawyer_uid?.toString() ?? uid;
      }

      const { data, error } = await supabaseAdmin.rpc("request_expediting_item_revision_internal", {
        p_lawyer_uid: effectiveLawyerUid,
        p_task_id: taskId,
        p_item_key: itemKey,
        p_revision_notes: revisionNotes,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المعقّب بطلب إعادة وثيقة
      const { data: taskRow } = await supabaseAdmin
        .from("expediting_tasks")
        .select("expediter_uid, target_property_num, checklist")
        .eq("id", taskId)
        .maybeSingle();
      const expediterToNotify = taskRow?.expediter_uid?.toString() ?? "";
      const revItemTitle = itemTitleFromChecklist(taskRow?.checklist, itemKey);
      if (expediterToNotify) {
        const ref = taskRow?.target_property_num ? ` (${taskRow.target_property_num})` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: expediterToNotify, tp: 2, ttl: "🔄 طلب إعادة وثيقة",
          bdy: `المحامي طلب إعادة «${revItemTitle}»${ref} — السبب: ${revisionNotes || "يرجى المراجعة"}`,
          ref_id: taskId, act: "expediting_revision_requested", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: expediterToNotify, p_title: "🔄 طلب إعادة وثيقة",
            p_body: `${itemKey} — ${revisionNotes?.slice(0, 60) || "يرجى المراجعة"}`,
            p_data: { act: "expediting_revision_requested", ref_id: taskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    if (action === "approve_expediting_task") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const taskId = (body.task_id ?? body.taskId)?.toString() ?? "";
      if (!taskId) return json({ success: false, error: "TASK_ID_REQUIRED" }, 400);

      // الإدارة: نستخدم lawyer_uid الحقيقي للمهمة (مش uid الأدمن)
      let effectiveLawyerUid = uid;
      if (canManageLawyerProfiles(role) && !isLawyer(role)) {
        const { data: taskRow } = await supabaseAdmin
          .from("expediting_tasks").select("lawyer_uid").eq("id", taskId).maybeSingle();
        effectiveLawyerUid = taskRow?.lawyer_uid?.toString() ?? uid;
      }

      const { data, error } = await supabaseAdmin.rpc("approve_expediting_task_internal", {
        p_lawyer_uid: effectiveLawyerUid,
        p_task_id: taskId,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      // 🔔 إشعار المعقّب باعتماد المهمة
      const { data: taskRow2 } = await supabaseAdmin
        .from("expediting_tasks")
        .select("expediter_uid, target_property_num, target_zone")
        .eq("id", taskId)
        .maybeSingle();
      const expediterToNotify2 = taskRow2?.expediter_uid?.toString() ?? "";
      if (expediterToNotify2) {
        const ref = taskRow2?.target_property_num ? ` — ${taskRow2.target_property_num}` : "";
        const zoneTxt = taskRow2?.target_zone ? ` (${taskRow2.target_zone})` : "";
        await supabaseAdmin.from("notifications").insert({
          uid: expediterToNotify2, tp: 2, ttl: "🎉 تم اعتماد مهمة التعقيب",
          bdy: `اعتمد المحامي مهمة الاستخراج${ref}${zoneTxt} — أحسنت!`,
          ref_id: taskId, act: "expediting_task_approved", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: expediterToNotify2, p_title: "🎉 تم اعتماد مهمتك",
            p_body: `مهمة الاستخراج${ref} — معتمدة`,
            p_data: { act: "expediting_task_approved", ref_id: taskId },
          });
        } catch { /* non-critical */ }
      }

      return json(data as Record<string, unknown>);
    }

    // ─── مهام التعقيب (محامي + إدارة) ───
    if (action === "get_lawyer_expediting_tasks") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      // الإدارة تشوف كل المهام، المحامي يشوف مهامه فقط
      const lawyerFilter = isLawyer(role) ? uid : ((body.lawyer_uid ?? body.lawyerUid)?.toString() ?? "");
      if (canManageLawyerProfiles(role) && !lawyerFilter) {
        // جلب كل المهام للإدارة
        const { data, error } = await supabaseAdmin
          .from("expediting_tasks")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(100);
        if (error) return json({ success: false, error: error.message }, 400);
        const signedTasks = await signExpeditingTaskAttachments(supabaseAdmin, data ?? []);
        return json({ success: true, tasks: signedTasks });
      }
      const { data, error } = await supabaseAdmin.rpc("get_lawyer_expediting_tasks", {
        p_lawyer_uid: lawyerFilter || uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const signedTasks = await signExpeditingTaskAttachments(supabaseAdmin, data ?? []);
      return json({ success: true, tasks: signedTasks });
    }

    if (action === "get_lawyer_appointments") {
      if (!isLawyer(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const { data, error } = await supabaseAdmin.rpc("get_lawyer_appointments", {
        p_lawyer_uid: uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, appointments: data ?? [] });
    }

    if (action === "get_my_expediting_tasks") {
      if (!isExpediter(role)) return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      const { data, error } = await supabaseAdmin.rpc("get_my_expediting_tasks", {
        p_expediter_uid: uid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const signedTasks = await signExpeditingTaskAttachments(supabaseAdmin, data ?? []);
      return json({ success: true, tasks: signedTasks });
    }

    // ─── رفع مستند استشارة عبر مفتاح الخدمة ───
    // الرفع المباشر من التطبيق يفشل لأن توثيقه staff_session لا Supabase Auth.
    // المسار يُبنى من uid المتحقق منه أعلاه ولا يقبله السيرفر من العميل.
    if (action === "upload_consultation_attachment") {
      const attachmentBase64 = (body.attachment_base64 ?? "").toString();
      if (!attachmentBase64) {
        return json({ success: false, error: "ATTACHMENT_REQUIRED" }, 400);
      }
      let bytes: Uint8Array;
      try {
        bytes = base64ToUint8Array(attachmentBase64);
      } catch {
        return json({ success: false, error: "INVALID_ATTACHMENT" }, 400);
      }
      if (bytes.length === 0) {
        return json({ success: false, error: "INVALID_ATTACHMENT" }, 400);
      }
      if (bytes.length > 8 * 1024 * 1024) {
        return json({ success: false, error: "ATTACHMENT_TOO_LARGE" }, 413);
      }
      // نوع الملف يُكتشف من البايتات نفسها، لا من اسم الملف أو ترويسة العميل.
      const contentType = detectImageContentType(bytes);
      if (!contentType) {
        return json({ success: false, error: "INVALID_IMAGE_CONTENT" }, 400);
      }
      const ext = contentType === "image/png"
        ? "png"
        : contentType === "image/webp"
        ? "webp"
        : "jpg";
      const path = `${uid}/${crypto.randomUUID()}.${ext}`;
      const { error: uploadError } = await supabaseAdmin.storage
        .from("consultation_files")
        .upload(path, bytes, {
          contentType,
          cacheControl: "3600",
          upsert: false,
        });
      if (uploadError) {
        return json({ success: false, error: "ATTACHMENT_UPLOAD_FAILED" }, 400);
      }
      return json({ success: true, path });
    }

    // تنظيف رفع غير مكتمل فقط. لا يُحذف أي ملف مرتبط باستشارة محفوظة.
    if (action === "discard_consultation_attachments") {
      const requestedPaths = Array.isArray(body.paths)
        ? body.paths.map(String).slice(0, 5)
        : [];
      const ownPaths = requestedPaths.filter((path) =>
        path.startsWith(`${uid}/`) && !path.includes("..")
      );
      const removable: string[] = [];
      for (const path of ownPaths) {
        const { data: linked } = await supabaseAdmin
          .from("legal_consultations")
          .select("id")
          .contains("attachments", [path])
          .limit(1);
        if (!linked || linked.length === 0) removable.push(path);
      }
      if (removable.length > 0) {
        const { error: removeError } = await supabaseAdmin.storage
          .from("consultation_files")
          .remove(removable);
        if (removeError) {
          return json({ success: false, error: "ATTACHMENT_CLEANUP_FAILED" }, 400);
        }
      }
      return json({ success: true, removed: removable.length });
    }

    // ─── حجز استشارة قانونية (من المستخدم العادي) ───
    if (action === "book_consultation") {
      const serviceType = Number(body.service_type ?? 0);
      const subject = (body.subject ?? "").toString().trim();
      const price = Number(body.price ?? 0);
      const requestedAttachments = Array.isArray(body.attachments)
        ? body.attachments.map(String)
        : [];
      if (requestedAttachments.length > 5) {
        return json({ success: false, error: "TOO_MANY_ATTACHMENTS" }, 400);
      }
      const attachments = requestedAttachments.filter((path) =>
        path.startsWith(`${uid}/`) && !path.includes("..")
      );
      if (attachments.length !== requestedAttachments.length) {
        return json({ success: false, error: "INVALID_ATTACHMENT_PATH" }, 403);
      }
      const requestedSlot = (body.slot ?? "").toString(); // حضورية: موعد مختار مسبقاً
      if (!subject) return json({ success: false, error: "SUBJECT_REQUIRED" }, 400);
      if (serviceType < 0 || serviceType > 1) return json({ success: false, error: "INVALID_SERVICE_TYPE" }, 400);
      // 🏢 الحضورية = موعد + دفع فقط (لا محادثة) ⇒ الموعد إلزامي قبل الحجز.
      // كانت تُنشأ بلا أي موعد فتبقى معلّقة في الفراغ بعد الدفع.
      if (serviceType === 1 && !requestedSlot) {
        return json({ success: false, error: "SLOT_REQUIRED_FOR_ONSITE" }, 400);
      }

      // الأسعار الرسمية تُقرأ من app_config.main.legalPrice (قابلة لتعديل الإدارة).
      // 2026-08-14: كانت ثابتة { 0: 500, 1: 2000 } بالكود ⇒ تعديل السعر مستحيل.
      // ⚠️ التحقق يبقى خادمياً إلزاماً: العميل يرسل السعر ونقارنه بقيمة الإعدادات،
      // وإلا صار بإمكان أي مستخدم دفع 1 ل.س بدل السعر الحقيقي.
      const legalCfg = await getLegalPrices(supabaseAdmin);
      const expectedPrice = serviceType === 1 ? legalCfg.onsite : legalCfg.phone;
      if (price !== expectedPrice) return json({ success: false, error: "INVALID_PRICE", expected: expectedPrice }, 400);

      // الدفعة أو الرصيد يُتحقق منه ويُحجز ذرياً داخل RPC؛ الواجهة ليست مصدراً للثقة.
      // لا حد أقصى للمحادثات — المستخدم يقدر يحجز استشارات جديدة بحرية.

      const { data, error } = await supabaseAdmin.rpc("create_legal_consultation_internal", {
        p_user_uid: uid,
        p_service_type: serviceType,
        p_subject: subject,
        p_price: price,
      });
      if (error) return json({ success: false, error: error.message }, 400);

      const consultation = Array.isArray(data) ? data[0] : data;
      const consultId = consultation?.id?.toString() ?? "";

      // ربط الدفعة أو استهلاك رصيد الاستشارة أصبح ذرياً داخل
      // create_legal_consultation_internal؛ لا توجد نافذة لإنشاء طلب مجاني
      // أو لاستهلاك الدفعة نفسها مرتين.

      // تحديد lawyer_alias (محامي المكتب الأول/الثاني/الثالث)
      const lawyerUid = consultation?.lawyer_uid?.toString() ?? "";
      let lawyerAlias = "محامي المكتب";
      if (lawyerUid) {
        const { data: aliasInit } = await supabaseAdmin
          .rpc("lawyer_alias_for", { p_lawyer_uid: lawyerUid });
        lawyerAlias = (aliasInit as string | null) ?? "محامي المكتب";
        // حفظ alias و attachments
        await supabaseAdmin.from("legal_consultations").update({
          lawyer_alias: lawyerAlias,
          attachments: attachments.length > 0 ? attachments : undefined,
        }).eq("id", consultId);
      } else if (attachments.length > 0) {
        await supabaseAdmin.from("legal_consultations").update({
          attachments,
        }).eq("id", consultId);
      }

      // 🔔 إشعار المحامي المُسند (إن وُجد)
      if (lawyerUid) {
        const serviceNames = ["استشارة هاتفية", "جلسة مكتبية"];
        const sName = serviceNames[serviceType] ?? "استشارة قانونية";
        const { data: userData } = await supabaseAdmin
          .from("users").select("nm").eq("id", uid).maybeSingle();
        const clientName = userData?.nm?.toString() ?? "عميل";
        await supabaseAdmin.from("notifications").insert({
          uid: lawyerUid, tp: 1, ttl: "⚖️ حجز استشارة قانونية جديد",
          bdy: `${clientName} حجز ${sName} — الموضوع: ${subject.slice(0, 100)}`,
          ref_id: consultId, act: "legal_consultation_new", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: lawyerUid, p_title: "⚖️ استشارة قانونية جديدة",
            p_body: `${clientName} — ${sName}`,
            p_data: { act: "legal_consultation_new", ref_id: consultId },
          });
        } catch { /* push failure is non-critical */ }
      }

      // 🔔 إشعار الإدارة (role >= 5)
      const { data: admins } = await supabaseAdmin
        .from("users").select("id").gte("role", 5).eq("sts", 0).eq("i_del", 0);
      if (admins && admins.length > 0) {
        const { data: userData } = await supabaseAdmin
          .from("users").select("nm").eq("id", uid).maybeSingle();
        const clientName = userData?.nm?.toString() ?? "عميل";
        await supabaseAdmin.from("notifications").insert(
          admins.map((a: Record<string, unknown>) => ({
            uid: a.id, tp: 1, ttl: "⚖️ طلب استشارة قانونية",
            bdy: `${clientName} حجز استشارة قانونية — بانتظار التأكيد`,
            ref_id: consultId, act: "legal_consultation_admin", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
          }))
        );
        // Push للإدارة
        for (const admin of admins) {
          try {
            await supabaseAdmin.rpc("send_push_notification", {
              p_uid: admin.id, p_title: "⚖️ طلب استشارة جديد",
              p_body: "بانتظار تأكيد المحامي",
              p_data: { act: "legal_consultation_admin", ref_id: consultId },
            });
          } catch {}
        }
      }

      // 🏢 الجلسة الحضورية: إنشاء الموعد فعلياً في appointments (2026-08-14).
      // قبل اليوم لم تكن تُنشأ إطلاقاً ⇒ العميل يدفع 2000 ولا أحد يعرف متى
      // يلتقيان، وتبويب «مواعيدي» يبقى فارغاً. الربط بـbkr_id/req_uid/dt
      // يجعلها تظهر تلقائياً وتستفيد من التذكيرات القائمة (rmnd_24/rmnd_2).
      let apptId: string | null = null;
      if (serviceType === 1 && lawyerUid && requestedSlot) {
        // تحقق أن السلوت ما زال ضمن أوقات المحامي وغير محجوز
        const { data: freeSlots } = await supabaseAdmin
          .rpc("get_lawyer_free_slots", { p_lawyer_uid: lawyerUid, p_days: 30 });
        const wanted = new Date(requestedSlot).getTime();
        const isFree = ((freeSlots ?? []) as Record<string, unknown>[])
          .some((r) => new Date(String(r.slot_dt)).getTime() === wanted);
        if (!isFree) {
          // نظافة: نحذف الاستشارة المنشأة لئلا تبقى يتيمة بلا موعد
          await supabaseAdmin.from("legal_consultations").delete().eq("id", consultId);
          return json({ success: false, error: "SLOT_NO_LONGER_AVAILABLE" }, 409);
        }
        const { data: appt, error: apptErr } = await supabaseAdmin
          .from("appointments")
          .insert({
            bkr_id: lawyerUid, req_uid: uid, dt: requestedSlot,
            sts: 0, ts_crt: new Date().toISOString(),
            executor_notes: subject.slice(0, 200),
          })
          .select("id").single();
        if (apptErr) {
          await supabaseAdmin.from("legal_consultations").delete().eq("id", consultId);
          await supabaseAdmin.from("consultation_credits").update({
            consumed: false, consumed_at: null, consultation_id: null,
          }).eq("consultation_id", consultId);
          return json({ success: false, error: apptErr.message }, 400);
        }
        apptId = appt?.id?.toString() ?? null;
        await supabaseAdmin.from("legal_consultations")
          .update({ appointment_id: apptId, requested_slot: requestedSlot })
          .eq("id", consultId);
      }

      // 📊 تحديث active_tasks_count للمحامي المُسند
      if (lawyerUid) {
        await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: lawyerUid });
      }

      const creditUsed = !consultation?.payment_id;
      return json({
        success: true, consultation_id: consultId,
        lawyer_assigned: !!lawyerUid, appointment_id: apptId,
        credit_used: creditUsed,
      });
    }

    // ─── قائمة استشاراتي (للمستخدم العادي) ───
    if (action === "list_my_consultations") {
      // 🔒 2026-08-14: كان select("*") يسرّب lawyer_uid للمستخدم، وبه يمكن
      // الاستعلام عن هوية المحامي — نقيض قرار إخفاء بياناته. الأعمدة محددة
      // الآن، والمحامي يُعرف بـlawyer_alias فقط («محامي المكتب الأول»).
      const { data, error } = await supabaseAdmin
        .from("legal_consultations")
        .select(
          "id, service_type, subject, price, status, notes, attachments, lawyer_alias, " +
          "chat_started_at, chat_duration_minutes, renew_count, rating, rating_comment, " +
          "converted_to_onsite, onsite_discount, payment_id, payment_status, " +
          "reject_reason_code, reject_note, reassign_count, expires_at, ts_crt, ts_upd",
        )
        .eq("user_uid", uid)
        .eq("i_del", 0)
        .order("ts_crt", { ascending: false });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, consultations: data ?? [] });
    }

    // ─── استشارات المحامي (محامي: خاصة به — إدارة: الكل) ───
    if (action === "get_lawyer_consultations") {
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      let query = supabaseAdmin
        .from("legal_consultations")
        .select("*, client_nm:users!user_uid(nm)")
        .eq("i_del", 0)
        .order("ts_crt", { ascending: false });
      // المحامي يشوف استشاراته فقط، الإدارة تشوف الكل
      if (isLawyer(role) && !canManageLawyerProfiles(role)) {
        query = query.eq("lawyer_uid", uid);
      }
      const { data, error } = await query;
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, consultations: data ?? [] });
    }

    // ─── تحديث حالة الاستشارة (محامي/أدمن/المستخدم يلغي) ───
    // ─── 🔀 رفض المحامي المُوجَّه بالسبب (أُضيف 2026-08-14) ───
    // قرار المالك: «سبب الرفض هو من يحدد الإجراء التالي».
    // need_info    → الحالة 5: المستخدم يستكمل ثم ترجع 0 لنفس المحامي (بلا دفع جديد)
    // unavailable  → إعادة إسناد تلقائية لمحامٍ آخر (متاح + الأقل انشغالاً + الأقدم)
    // out_of_scope → مثل unavailable مع تسجيل السبب
    // illegal      → الحالة 4 نهائية + إخطار الإدارة للبتّ بالاسترداد
    // حماية الحلقة: لا تُسند لمن رفض (rejected_by)، وبعد 3 محاولات تُصعَّد للإدارة.
    if (action === "reject_consultation") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const reasonCode = (body.reason_code ?? "").toString();
      const reasonNote = (body.reason_note ?? "").toString().trim().slice(0, 400);
      const VALID = ["need_info", "unavailable", "out_of_scope", "illegal"];
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      if (!VALID.includes(reasonCode)) return json({ success: false, error: "INVALID_REASON_CODE" }, 400);
      // السبب النصي إلزامي لما يحتاج توضيحاً للمستخدم
      if ((reasonCode === "need_info" || reasonCode === "illegal") && reasonNote.length < 5) {
        return json({ success: false, error: "REASON_NOTE_REQUIRED" }, 400);
      }

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, service_type, subject, status, reassign_count, rejected_by")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      const isAssignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      if (!isAssignedLawyer && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_ASSIGNED_LAWYER" }, 403);
      }
      if (Number(row.status) !== 0) {
        return json({ success: false, error: "ONLY_PENDING_CAN_BE_REJECTED" }, 409);
      }

      const userUid = row.user_uid?.toString() ?? "";
      const sName = Number(row.service_type) === 1 ? "الجلسة الحضورية" : "الاستشارة الهاتفية";
      const notifyUser = async (ttl: string, bdy: string, act: string) => {
        if (!userUid) return;
        await supabaseAdmin.from("notifications").insert({
          uid: userUid, tp: 1, ttl, bdy, ref_id: consultId, act,
          i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: userUid, p_title: ttl, p_body: bdy, p_data: { act, ref_id: consultId },
          });
        } catch { /* push ثانوي */ }
      };
      const notifyAdmins = async (ttl: string, bdy: string) => {
        const { data: admins } = await supabaseAdmin
          .from("users").select("id").gte("role", 5).eq("sts", 0).eq("i_del", 0);
        if (!admins?.length) return;
        await supabaseAdmin.from("notifications").insert(
          admins.map((a: Record<string, unknown>) => ({
            uid: a.id, tp: 1, ttl, bdy, ref_id: consultId,
            act: "legal_consultation_escalated", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
          })),
        );
      };

      // ── ① نقص تفاصيل/مستندات → الحالة 5 (نفس المحامي محتفظ بالسياق) ──
      if (reasonCode === "need_info") {
        await supabaseAdmin.from("legal_consultations").update({
          status: 5, reject_reason_code: reasonCode, reject_note: reasonNote, ts_upd: new Date().toISOString(),
        }).eq("id", consultId);
        await notifyUser("📄 المحامي يحتاج تفاصيل إضافية",
          `${sName}: ${reasonNote.slice(0, 120)} — افتح الطلب واستكمل البيانات (لا حاجة لدفع جديد).`,
          "legal_consultation_need_info");
        return json({ success: true, outcome: "need_info", status: 5 });
      }

      // ── ② مخالف/غير قانوني → **الاستشارة تمت** (قرار المالك 2026-08-14) ──
      // الرأي القانوني «عملك مخالف» خدمةٌ مكتملة لا فشلاً: المحامي بذل جهداً
      // مهنياً وأصدر رأياً، فلا استرداد، ويستحق أجره، والعميل يستطيع التقييم.
      if (reasonCode === "illegal") {
        await supabaseAdmin.from("legal_consultations").update({
          status: 2, // مكتملة
          reject_reason_code: reasonCode, reject_note: reasonNote,
          ts_upd: new Date().toISOString(),
        }).eq("id", consultId);
        if (row.lawyer_uid) {
          await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: row.lawyer_uid });
        }
        await notifyUser("⚖️ اكتملت استشارتك — رأي المحامي",
          `${sName}: ${reasonNote.slice(0, 150)}\n\nهذا هو الرأي القانوني لطلبك، ويُعدّ الاستشارة منجزة.`,
          "legal_consultation_completed");
        return json({ success: true, outcome: "completed_illegal", status: 2 });
      }

      // ── ③ غير متوفر / خارج الاختصاص → إعادة إسناد تلقائية ──
      const rejectedBy: string[] = Array.isArray(row.rejected_by)
        ? (row.rejected_by as string[]).map(String) : [];
      if (row.lawyer_uid && !rejectedBy.includes(String(row.lawyer_uid))) {
        rejectedBy.push(String(row.lawyer_uid));
      }
      const reassignCount = Number(row.reassign_count ?? 0) + 1;
      const MAX_REASSIGN = 3;

      let nextLawyer: string | null = null;
      if (reassignCount <= MAX_REASSIGN) {
        const { data: picked } = await supabaseAdmin
          .rpc("pick_next_lawyer", { p_exclude: rejectedBy });
        nextLawyer = picked ? String(picked) : null;
      }

      // لا بديل (أو تجاوزنا السقف) ⇒ تبقى معلّقة بلا محامي وتُصعَّد للإدارة
      if (!nextLawyer) {
        await supabaseAdmin.from("legal_consultations").update({
          lawyer_uid: null, lawyer_alias: null, status: 0,
          reject_reason_code: reasonCode, reject_note: reasonNote,
          reassign_count: reassignCount, rejected_by: rejectedBy,
          ts_upd: new Date().toISOString(),
        }).eq("id", consultId);
        if (row.lawyer_uid) {
          await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: row.lawyer_uid });
        }
        await notifyUser("⏳ نبحث لك عن محامٍ متاح",
          `${sName}: جميع المحامين مشغولون حالياً — الإدارة تتابع طلبك وسنخطرك فور توفر محامٍ.`,
          "legal_consultation_escalated");
        await notifyAdmins("🚨 استشارة بلا محامٍ متاح",
          `تعذّر إسناد استشارة بعد ${reassignCount} محاولة — يلزم تدخل يدوي.`);
        return json({ success: true, outcome: "escalated_to_admin", reassign_count: reassignCount });
      }

      // إسناد للمحامي التالي مع تحديث الاسم المستعار
      // اللقب من دالة مركزية (ترتيب ثابت لكل محامٍ) — الحساب القديم بـcount
      // كان يعطي محاميَين مختلفين نفس اللقب فيهدم وظيفة الإخفاء.
      const { data: aliasData } = await supabaseAdmin
        .rpc("lawyer_alias_for", { p_lawyer_uid: nextLawyer });
      const newAlias = (aliasData as string | null) ?? "محامي المكتب";

      await supabaseAdmin.from("legal_consultations").update({
        lawyer_uid: nextLawyer, lawyer_alias: newAlias, status: 0,
        reject_reason_code: reasonCode, reject_note: reasonNote,
        reassign_count: reassignCount, rejected_by: rejectedBy,
        ts_upd: new Date().toISOString(),
      }).eq("id", consultId);

      if (row.lawyer_uid) {
        await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: row.lawyer_uid });
      }
      await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: nextLawyer });

      // إشعار المحامي الجديد
      await supabaseAdmin.from("notifications").insert({
        uid: nextLawyer, tp: 1, ttl: "⚖️ استشارة مُحوَّلة إليك",
        bdy: `${sName} — الموضوع: ${(row.subject ?? "").toString().slice(0, 100)}`,
        ref_id: consultId, act: "legal_consultation_new", i_rd: 0, i_del: 0,
        ts_crt: new Date().toISOString(),
      });
      try {
        await supabaseAdmin.rpc("send_push_notification", {
          p_uid: nextLawyer, p_title: "⚖️ استشارة مُحوَّلة إليك", p_body: sName,
          p_data: { act: "legal_consultation_new", ref_id: consultId },
        });
      } catch { /* push ثانوي */ }

      await notifyUser("🔄 تم تحويل طلبك لمحامٍ آخر",
        `${sName}: المحامي السابق غير متاح — طلبك الآن مع ${newAlias} ولا حاجة لأي دفع إضافي.`,
        "legal_consultation_reassigned");

      return json({
        success: true, outcome: "reassigned",
        reassign_count: reassignCount, lawyer_alias: newAlias,
      });
    }

    // ─── 🔁 المستخدم يستكمل البيانات الناقصة (الحالة 5 → 0) ───
    if (action === "resubmit_consultation") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const newSubject = (body.subject ?? "").toString().trim();
      const extraAtts = Array.isArray(body.attachments) ? body.attachments.map(String) : [];
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      if (newSubject.length < 10) return json({ success: false, error: "SUBJECT_TOO_SHORT" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, lawyer_alias, service_type, status, attachments")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);
      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (Number(row.status) !== 5) return json({ success: false, error: "NOT_AWAITING_INFO" }, 409);

      const merged = [
        ...((row.attachments as string[] | null) ?? []),
        ...extraAtts,
      ].slice(0, 10);

      await supabaseAdmin.from("legal_consultations").update({
        subject: newSubject, attachments: merged, status: 0,
        reject_reason_code: null, reject_note: null, ts_upd: new Date().toISOString(),
      }).eq("id", consultId);

      // إشعار نفس المحامي (يحتفظ بسياق القضية)
      if (row.lawyer_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: row.lawyer_uid, tp: 1, ttl: "📄 العميل استكمل البيانات المطلوبة",
          bdy: `${newSubject.slice(0, 100)}`, ref_id: consultId,
          act: "legal_consultation_resubmitted", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: row.lawyer_uid, p_title: "📄 بيانات مستكملة",
            p_body: "العميل أرسل التفاصيل المطلوبة",
            p_data: { act: "legal_consultation_resubmitted", ref_id: consultId },
          });
        } catch { /* push ثانوي */ }
      }
      return json({ success: true, status: 0 });
    }

    // ─── 👔 أفعال الإدارة على الاستشارات (أُضيفت 2026-08-14) ───
    // الفجوة: بعد رفض كل المحامين تبقى الاستشارة يتيمة للأبد — لا شاشة إدارة
    // ولا إسناد يدوي. قرار المالك: الإدارة تتواصل خارج التطبيق ثم تُسند،
    // أو تمنح «رصيد استشارة» (المبلغ يبقى بالخزينة والعميل لا يدفع ثانيةً).

    // قائمة كل الاستشارات للإدارة (مع فلتر «بلا محامٍ»)
    if (action === "admin_list_consultations") {
      if (!canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      const onlyOrphan = body.only_orphan === true;
      let q = supabaseAdmin
        .from("legal_consultations")
        .select("*, client:users!user_uid(nm, ph)")
        .eq("i_del", 0)
        .order("ts_crt", { ascending: false })
        .limit(200);
      if (onlyOrphan) q = q.is("lawyer_uid", null).eq("status", 0);
      const { data, error } = await q;
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, consultations: data ?? [] });
    }

    // إسناد يدوي لمحامٍ محدد (بعد تنسيق الإدارة الخارجي)
    if (action === "admin_assign_consultation") {
      if (!canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      const consultId = (body.consultation_id ?? "").toString();
      const lawyerUid = (body.lawyer_uid ?? "").toString();
      if (!consultId || !lawyerUid) {
        return json({ success: false, error: "CONSULTATION_AND_LAWYER_REQUIRED" }, 400);
      }
      const { data, error } = await supabaseAdmin.rpc("admin_assign_consultation", {
        p_admin_uid: uid, p_consultation_id: consultId, p_lawyer_uid: lawyerUid,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const res = (data ?? {}) as Record<string, unknown>;
      if (res.success === true) {
        const { data: c } = await supabaseAdmin.from("legal_consultations")
          .select("user_uid, service_type, subject").eq("id", consultId).maybeSingle();
        const sType = Number(c?.service_type) === 1 ? "الجلسة الحضورية" : "الاستشارة الهاتفية";
        if (c?.user_uid) {
          await supabaseAdmin.from("notifications").insert({
            uid: c.user_uid, tp: 1, ttl: "⚖️ أُسند طلبك لمحامٍ",
            bdy: `${sType}: تم إسناد طلبك إلى ${res.lawyer_alias ?? "محامي المكتب"} وسيباشر بدراسته.`,
            ref_id: consultId, act: "legal_consultation_reassigned",
            i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
          });
          try {
            await supabaseAdmin.rpc("send_push_notification", {
              p_uid: c.user_uid, p_title: "⚖️ أُسند طلبك لمحامٍ", p_body: sType,
              p_data: { act: "legal_consultation_reassigned", ref_id: consultId },
            });
          } catch { /* push ثانوي */ }
        }
        await supabaseAdmin.from("notifications").insert({
          uid: lawyerUid, tp: 1, ttl: "⚖️ استشارة أسندتها الإدارة إليك",
          bdy: `${sType} — ${String(c?.subject ?? "").slice(0, 90)}`,
          ref_id: consultId, act: "legal_consultation_new",
          i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
      }
      return json(res);
    }

    // منح رصيد استشارة (بدل الاسترداد النقدي)
    if (action === "admin_grant_credit") {
      if (!canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      const targetUser = (body.user_uid_target ?? "").toString();
      const sType = Number(body.service_type ?? 0);
      const reason = (body.reason ?? "").toString().trim();
      const srcConsult = (body.source_consultation_id ?? "").toString();
      if (!targetUser) return json({ success: false, error: "TARGET_USER_REQUIRED" }, 400);
      if (reason.length < 5) return json({ success: false, error: "REASON_REQUIRED" }, 400);

      const { data, error } = await supabaseAdmin.rpc("admin_grant_consultation_credit", {
        p_admin_uid: uid, p_user_uid: targetUser, p_service_type: sType,
        p_reason: reason, p_source_consultation: srcConsult || null,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      const res = (data ?? {}) as Record<string, unknown>;
      if (res.success === true) {
        const label = sType === 1 ? "جلسة حضورية" : "استشارة هاتفية";
        await supabaseAdmin.from("notifications").insert({
          uid: targetUser, tp: 1, ttl: "🎁 لديك رصيد استشارة",
          bdy: `مُنحت رصيد ${label} مجاناً (${res.amount} ل.س). ادخل لقسم الاستشارة واطلبها بلا دفع. السبب: ${reason.slice(0, 100)}`,
          ref_id: String(res.credit_id ?? ""), act: "consultation_credit_granted",
          i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: targetUser, p_title: "🎁 لديك رصيد استشارة مجانية", p_body: label,
            p_data: { act: "consultation_credit_granted" },
          });
        } catch { /* push ثانوي */ }
      }
      return json(res);
    }

    // رصيد المستخدم المتاح (تعرضه شاشة الاستشارة بدل زر الدفع)
    if (action === "my_consultation_credits") {
      const { data, error } = await supabaseAdmin
        .from("consultation_credits")
        .select("id, service_type, amount, reason, ts_crt")
        .eq("user_uid", uid).eq("consumed", false)
        .order("ts_crt", { ascending: true });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, credits: data ?? [] });
    }

    // ─── 📎 روابط موقّعة لمستندات الاستشارة (أُضيف 2026-08-14) ───
    // كانت المرفقات تُعرض للمحامي كعدد فقط («📎 3 مستند مرفق») بلا أي وسيلة
    // لفتحها — لا في اللوحة ولا في المحادثة — فيقرر قبول القضية بلا رؤية
    // سند الملكية. الـbucket خاص (public=false) فيلزم رابط موقّع.
    if (action === "get_consultation_files") {
      const consultId = (body.consultation_id ?? "").toString();
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, attachments")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // 🔒 صاحب الاستشارة أو المحامي المُسند أو الإدارة فقط
      const isOwner = row.user_uid === uid;
      const isAssigned = row.lawyer_uid === uid;
      if (!isOwner && !isAssigned && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      const paths = ((row.attachments as string[] | null) ?? []).filter(Boolean);
      const files: Record<string, string>[] = [];
      for (const p of paths) {
        const { data: signed } = await supabaseAdmin.storage
          .from("consultation_files").createSignedUrl(p, 3600);
        if (signed?.signedUrl) {
          files.push({
            path: p,
            url: signed.signedUrl,
            name: p.split("/").pop() ?? p,
          });
        }
      }
      return json({ success: true, files });
    }

    // ─── 🗓️ المحامي يضبط أوقاته المتاحة (إلزامي قبل استخدام الشاشة) ───
    // قرار المالك 2026-08-14: المحامي يفتح أوقاته سلفاً والعميل لا يرى غيرها،
    // فتُلغى جولة التفاوض (اقتراح/موافقة) لكل جلسة حضورية.
    if (action === "set_availability_slots") {
      const targetUid = (body.target_uid ?? uid)?.toString() ?? "";
      const avl = body.avl;
      if (targetUid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      if (!isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      if (!avl || typeof avl !== "object" || Array.isArray(avl)) {
        return json({ success: false, error: "AVL_OBJECT_REQUIRED" }, 400);
      }
      const { data, error } = await supabaseAdmin
        .rpc("set_lawyer_availability_slots", { p_lawyer_uid: targetUid, p_avl: avl });
      if (error) return json({ success: false, error: error.message }, 400);
      return json((data ?? { success: false }) as Record<string, unknown>);
    }

    // ─── 🕐 السلوتات الحرة لمحامٍ (للعميل قبل حجز الجلسة الحضورية) ───
    if (action === "get_free_slots") {
      const lawyerUid = (body.lawyer_uid ?? "").toString();
      const days = Math.min(30, Math.max(1, Number(body.days ?? 14)));

      // بلا تحديد محامٍ: نأخذ التالي بالدور (متاح ← الأقل انشغالاً ← الأقدم)
      let target = lawyerUid;
      if (!target) {
        const { data: picked } = await supabaseAdmin.rpc("pick_next_lawyer", { p_exclude: [] });
        target = picked ? String(picked) : "";
      }
      if (!target) return json({ success: true, slots: [], lawyer_uid: null });

      const { data, error } = await supabaseAdmin
        .rpc("get_lawyer_free_slots", { p_lawyer_uid: target, p_days: days });
      if (error) return json({ success: false, error: error.message }, 400);
      const slots = ((data ?? []) as Record<string, unknown>[])
        .map((r) => String(r.slot_dt ?? r));
      // 🔒 لا تُعاد هوية المحامي للعميل — اللقب فقط
      const { data: alias } = await supabaseAdmin
        .rpc("lawyer_alias_for", { p_lawyer_uid: target });
      return json({ success: true, slots, lawyer_alias: alias ?? "محامي المكتب" });
    }

    // ─── 📅 المحامي يتصرف بموعد جلسة حضورية ───
    if (action === "lawyer_appointment_action") {
      const apptId = (body.appointment_id ?? "").toString();
      const act = (body.appt_action ?? "").toString(); // confirm | complete | cancel
      const reason = (body.reason ?? "").toString().trim().slice(0, 300);
      if (!apptId) return json({ success: false, error: "APPOINTMENT_ID_REQUIRED" }, 400);
      if (!["confirm", "complete", "cancel"].includes(act)) {
        return json({ success: false, error: "INVALID_APPT_ACTION" }, 400);
      }
      if (act === "cancel" && reason.length < 5) {
        return json({ success: false, error: "CANCEL_REASON_REQUIRED" }, 400);
      }

      const { data: appt } = await supabaseAdmin
        .from("appointments").select("id, bkr_id, req_uid, dt, sts")
        .eq("id", apptId).maybeSingle();
      if (!appt) return json({ success: false, error: "APPOINTMENT_NOT_FOUND" }, 404);
      if (appt.bkr_id !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_YOUR_APPOINTMENT" }, 403);
      }

      const cur = Number(appt.sts ?? 0);
      const next = act === "confirm" ? 1 : act === "complete" ? 2 : 3;
      const allowed: Record<number, number[]> = { 0: [1, 3], 1: [2, 3], 2: [], 3: [] };
      if (!(allowed[cur] ?? []).includes(next)) {
        return json({ success: false, error: "INVALID_APPT_TRANSITION", from: cur, to: next }, 409);
      }

      const upd: Record<string, unknown> = { sts: next };
      if (act === "cancel") { upd.cnl_by = uid; upd.cnl_rsn = reason; }
      if (act === "complete") { upd.completion_date = new Date().toISOString(); }
      const { error: upErr } = await supabaseAdmin
        .from("appointments").update(upd).eq("id", apptId);
      if (upErr) return json({ success: false, error: upErr.message }, 400);

      // مزامنة حالة الاستشارة المرتبطة (مكتملة/ملغاة)
      if (next === 2 || next === 3) {
        await supabaseAdmin.from("legal_consultations")
          .update({ status: next === 2 ? 2 : 3, ts_upd: new Date().toISOString() })
          .eq("appointment_id", apptId).eq("i_del", 0);
        if (appt.bkr_id) {
          await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: appt.bkr_id });
        }
      }

      const titles: Record<string, string> = {
        confirm: "✅ تأكيد موعد جلستك",
        complete: "🎉 تمت جلستك القانونية",
        cancel: "⚠️ أُلغي موعد جلستك",
      };
      const when = new Date(String(appt.dt)).toLocaleString("ar", {
        timeZone: "Asia/Damascus", dateStyle: "full", timeStyle: "short",
      });
      const bodies: Record<string, string> = {
        confirm: `تم تأكيد موعدك: ${when} — نراك في المكتب.`,
        complete: "شكراً لك — يسعدنا تقييمك للجلسة.",
        cancel: `أُلغي موعد ${when}. السبب: ${reason} — يمكنك اختيار موعد آخر.`,
      };
      if (appt.req_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: appt.req_uid, tp: 1, ttl: titles[act], bdy: bodies[act],
          ref_id: apptId, act: "legal_appointment_update",
          i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: appt.req_uid, p_title: titles[act], p_body: bodies[act],
            p_data: { act: "legal_appointment_update", ref_id: apptId },
          });
        } catch { /* push ثانوي */ }
      }
      return json({ success: true, appointment_status: next });
    }

    // ─── 🟢 المحامي يبدّل حالة توفره (أُضيف 2026-08-14) ───
    // الفجوة: is_active كان يُقرأ بمكانين ولا كاتب له إطلاقاً ⇒ مجمّد على true.
    if (action === "set_lawyer_availability") {
      const available = body.available === true;
      const targetUid = (body.target_uid ?? uid)?.toString() ?? "";
      if (targetUid !== uid && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }
      if (targetUid === uid && !isLawyer(role) && !canManageLawyerProfiles(role)) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      const { error: upErr } = await supabaseAdmin
        .from("lawyer_profiles")
        .update({ is_active: available, updated_at: new Date().toISOString() })
        .eq("uid", targetUid);
      if (upErr) return json({ success: false, error: upErr.message }, 400);

      // 🔄 عودة المحامي لـ«متاح» ⇒ التقاط تلقائي للطلبات اليتيمة (قرار المالك):
      // الطلبات التي رفضها الجميع كانت تبقى عالقة للأبد بلا محامٍ.
      let claimed: Record<string, unknown>[] = [];
      if (available) {
        const { data: got } = await supabaseAdmin
          .rpc("claim_orphan_consultations", { p_lawyer_uid: targetUid });
        claimed = (got ?? []) as Record<string, unknown>[];
        for (const c of claimed) {
          const cid = String(c.consultation_id);
          const sType = Number(c.service_type) === 1 ? "الجلسة الحضورية" : "الاستشارة الهاتفية";
          // إشعار العميل: انتهى الانتظار
          if (c.user_uid) {
            await supabaseAdmin.from("notifications").insert({
              uid: c.user_uid, tp: 1, ttl: "🎉 وجدنا لك محامياً متاحاً",
              bdy: `${sType}: أُسند طلبك لمحامٍ متاح وسيباشر بدراسته — بلا أي رسوم إضافية.`,
              ref_id: cid, act: "legal_consultation_reassigned",
              i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
            });
            try {
              await supabaseAdmin.rpc("send_push_notification", {
                p_uid: c.user_uid, p_title: "🎉 وجدنا لك محامياً متاحاً", p_body: sType,
                p_data: { act: "legal_consultation_reassigned", ref_id: cid },
              });
            } catch { /* push ثانوي */ }
          }
          // إشعار المحامي بما التُقط له
          await supabaseAdmin.from("notifications").insert({
            uid: targetUid, tp: 1, ttl: "⚖️ استشارة مُسندة إليك",
            bdy: `${sType} — ${String(c.subject ?? "").slice(0, 90)}`,
            ref_id: cid, act: "legal_consultation_new",
            i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
          });
        }
      }

      // الطلبات المعلّقة التي لم تبدأ بعد — تُعرض على المحامي لتحويلها
      const { count: pending } = await supabaseAdmin
        .from("legal_consultations").select("*", { count: "exact", head: true })
        .eq("lawyer_uid", targetUid).eq("status", 0).eq("i_del", 0);

      return json({
        success: true, available,
        pending_count: pending ?? 0,
        claimed_count: claimed.length,
      });
    }

    if (action === "update_consultation_status") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const newStatus = Number(body.status ?? 0);
      const updateNotes = (body.notes ?? "").toString();
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row, error: fetchErr } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, service_type, subject, status, chat_started_at, chat_duration_minutes")
        .eq("id", consultId)
        .eq("i_del", 0)
        .maybeSingle();
      if (fetchErr || !row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      const currentStatus = Number(row.status ?? 0);
      const isOwner = row.user_uid === uid;
      const isAssignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      const isAdmin = canManageLawyerProfiles(role);

      // 🔒 الصلاحيات:
      // - المستخدم: يقدر يلغي استشارته فقط (status=0 → 3)
      // - المحامي المُسند: يؤكد/يتمم/يرفض/يلغي
      // - الإدارة: كل شي
      if (isOwner && !isAssignedLawyer && !isAdmin) {
        // المستخدم العادي — يسمح فقط بالإلغاء (0 → 3)
        // 2026-08-14: يُسمح بالإلغاء من 0 أو 5 (بانتظار استكمال بياناته)
        if (![0, 5].includes(currentStatus) || newStatus !== 3) {
          return json({ success: false, error: "USER_CAN_ONLY_CANCEL_PENDING" }, 403);
        }
      } else if (!isAssignedLawyer && !isAdmin) {
        return json({ success: false, error: "NOT_AUTHORIZED" }, 403);
      }

      // 🔒 حماية انتقالات الحالة — منع تغيير حالة مكتملة/ملغاة/مرفوضة
      // 2026-08-14: أُضيفت الحالة 5 = بانتظار استكمال بيانات المستخدم.
      // مسارها: 5 → 0 عبر resubmit_consultation · أو 5 → 3 إلغاء المستخدم.
      const allowedTransitions: Record<number, number[]> = {
        0: [1, 3, 4, 5], // بانتظار → مؤكد / ملغي / مرفوض / بانتظار بيانات
        1: [2, 3],       // مؤكد → مكتمل / ملغي
        2: [],            // مكتمل → لا شيء (نهائية)
        3: [],            // ملغي → لا شيء (نهائية)
        4: [],            // مرفوض → لا شيء (نهائية)
        5: [0, 3],        // بانتظار بيانات → عاد للمحامي / ملغي
      };
      // الاستشارة الهاتفية لا تُنجز قبل بدء المحادثة ونهاية مدتها الحالية.
      if (newStatus === 2 && Number(row.service_type) === 0) {
        if (!row.chat_started_at) {
          return json({ success: false, error: "CHAT_NOT_STARTED" }, 409);
        }
        const endAt = new Date(row.chat_started_at).getTime() +
          (Number(row.chat_duration_minutes) || 15) * 60 * 1000;
        if (Date.now() < endAt) {
          return json({
            success: false,
            error: "CHAT_TIME_NOT_FINISHED",
            remaining_seconds: Math.ceil((endAt - Date.now()) / 1000),
          }, 409);
        }
      }

      const allowed = allowedTransitions[currentStatus] ?? [];
      if (!allowed.includes(newStatus)) {
        const statusNames: Record<number, string> = { 0: "بانتظار", 1: "مؤكدة", 2: "مكتملة", 3: "ملغاة", 4: "مرفوضة", 5: "بانتظار استكمال بيانات" };
        return json({
          success: false,
          error: `INVALID_STATUS_TRANSITION`,
          message: `لا يمكن تغيير الاستشارة من "${statusNames[currentStatus] ?? currentStatus}" إلى "${statusNames[newStatus] ?? newStatus}"`,
        }, 409);
      }

      const { data: updatedRows, error: updErr } = await supabaseAdmin
        .from("legal_consultations")
        .update({ status: newStatus, notes: updateNotes || undefined, ts_upd: new Date().toISOString() })
        .eq("id", consultId)
        .eq("status", currentStatus)
        .select("id");
      if (updErr) return json({ success: false, error: updErr.message }, 400);
      if (!updatedRows || updatedRows.length !== 1) {
        return json({ success: false, error: "CONSULTATION_CONCURRENTLY_UPDATED" }, 409);
      }

      // 🔔 إشعار المستخدم بتحديث الحالة
      const statusLabels: Record<number, string> = { 1: "تم تأكيد", 2: "تم إتمام", 3: "تم إلغاء", 4: "تم رفض" };
      const label = statusLabels[newStatus] ?? "تم تحديث";
      const serviceNames = ["استشارة هاتفية", "جلسة مكتبية", "باقة توثيق شامل"];
      const sName = serviceNames[Number(row.service_type)] ?? "استشارة قانونية";
      const userUid = row.user_uid?.toString() ?? "";

      // 📊 تحديث active_tasks_count عند انتقال لحالة نهائية (2,3,4)
      if ([2, 3, 4].includes(newStatus) && [0, 1, 5].includes(currentStatus)) {
        const lawyerToUpdate = row.lawyer_uid?.toString() ?? "";
        if (lawyerToUpdate) {
          await supabaseAdmin.rpc("update_lawyer_active_tasks", { p_lawyer_uid: lawyerToUpdate });
        }
      }

      if (userUid) {
        await supabaseAdmin.from("notifications").insert({
          uid: userUid, tp: 1, ttl: `⚖️ ${label} الاستشارة القانونية`,
          bdy: `${label} ${sName} — ${row.subject?.toString().slice(0, 80) ?? ""}${updateNotes ? " — " + updateNotes : ""}`,
          ref_id: consultId, act: "legal_consultation_update", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: userUid, p_title: `⚖️ ${label} استشارتك القانونية`,
            p_body: sName,
            p_data: { act: "legal_consultation_update", ref_id: consultId },
          });
        } catch { /* push failure is non-critical */ }
      }

      return json({ success: true });
    }

    // ─── فتح المحادثة (المحامي يضغط "بدء المحادثة") ───
    if (action === "start_chat") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, status, chat_started_at, service_type")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // 🏢 الحضورية = موعد + دفع فقط، بلا محادثة إطلاقاً (قرار المالك 2026-08-14)
      if (Number(row.service_type) === 1) {
        return json({ success: false, error: "ONSITE_HAS_NO_CHAT" }, 400);
      }

      // فقط المحامي المُسند أو الإدارة المخوّلة يفتح المحادثة.
      const assignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      const managingAdmin = canManageLawyerProfiles(role);
      if (!assignedLawyer && !managingAdmin) {
        return json({ success: false, error: "NOT_ASSIGNED_LAWYER" }, 403);
      }
      if (Number(row.status) !== 1) return json({ success: false, error: "CONSULTATION_NOT_CONFIRMED" }, 400);
      if (row.chat_started_at) return json({ success: false, error: "CHAT_ALREADY_STARTED" }, 400);

      const now = new Date().toISOString();
      // 2026-08-14: المدة تُثبَّت من الإعدادات لحظة الفتح (كان الجدول يعتمد
      // على default=15 فلا يتبع تعديل الإدارة).
      const startCfg = await getLegalPrices(supabaseAdmin);
      const startMins = startCfg.durationMins;
      const { data: startedRows, error: startErr } = await supabaseAdmin
        .from("legal_consultations")
        .update({ chat_started_at: now, status: 1, chat_duration_minutes: startMins })
        .eq("id", consultId)
        .eq("status", 1)
        .is("chat_started_at", null)
        .select("id");
      if (startErr) return json({ success: false, error: startErr.message }, 400);
      if (!startedRows || startedRows.length !== 1) {
        return json({ success: false, error: "CHAT_ALREADY_STARTED" }, 409);
      }

      // رسالة system
      await supabaseAdmin.from("consultation_chats").insert({
        consultation_id: consultId, sender_id: uid,
        message_type: "system", content: `بدأت المحادثة — لديك ${startMins} دقيقة للاستشارة`,
      });

      // إشعار الطالب
      if (row.user_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: row.user_uid, tp: 1, ttl: "💬 المحامي فتح المحادثة",
          bdy: `يمكنك الآن بدء الاستشارة القانونية — لديك ${startMins} دقيقة`,
          ref_id: consultId, act: "chat_started", i_rd: 0, i_del: 0, ts_crt: now,
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: row.user_uid, p_title: "💬 المحادثة مفتوحة",
            p_body: "ابدأ استشارتك القانونية الآن",
            p_data: { act: "chat_started", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, chat_started_at: now });
    }

    // ─── رفع صورة داخل المحادثة عبر مفتاح الخدمة ───
    if (action === "upload_chat_image") {
      const consultId = (body.consultation_id ?? "").toString();
      const encoded = (body.file_base64 ?? "").toString();
      if (!consultId || !encoded) return json({ success: false, error: "FILE_REQUIRED" }, 400);
      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("user_uid, lawyer_uid, chat_started_at, chat_duration_minutes, status")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);
      const participant = row.user_uid === uid || (isLawyer(role) && row.lawyer_uid === uid);
      if (!participant) return json({ success: false, error: "NOT_PARTICIPANT" }, 403);
      if (!row.chat_started_at || Number(row.status) !== 1) {
        return json({ success: false, error: "CHAT_NOT_OPEN" }, 409);
      }
      const endAt = new Date(row.chat_started_at).getTime() +
        (Number(row.chat_duration_minutes) || 15) * 60 * 1000;
      if (Date.now() >= endAt) return json({ success: false, error: "CHAT_TIME_EXPIRED" }, 409);
      let bytes: Uint8Array;
      try { bytes = base64ToUint8Array(encoded); }
      catch { return json({ success: false, error: "INVALID_IMAGE_CONTENT" }, 400); }
      if (bytes.length === 0 || bytes.length > 8 * 1024 * 1024) {
        return json({ success: false, error: "INVALID_IMAGE_SIZE" }, 400);
      }
      const contentType = detectImageContentType(bytes);
      if (!contentType) return json({ success: false, error: "INVALID_IMAGE_CONTENT" }, 400);
      const ext = contentType === "image/png" ? "png" : contentType === "image/webp" ? "webp" : "jpg";
      const path = `${uid}/chat/${consultId}/${crypto.randomUUID()}.${ext}`;
      const { error } = await supabaseAdmin.storage.from("consultation_files")
        .upload(path, bytes, { contentType, cacheControl: "3600", upsert: false });
      if (error) return json({ success: false, error: "CHAT_IMAGE_UPLOAD_FAILED" }, 400);
      return json({ success: true, path });
    }

    // ─── رفع رسالة صوتية داخل المحادثة ───
    if (action === "upload_chat_voice") {
      const consultId = (body.consultation_id ?? "").toString();
      const encoded = (body.file_base64 ?? "").toString();
      const duration = Number(body.duration_seconds ?? 0);
      if (!consultId || !encoded || duration < 1 || duration > 60) {
        return json({ success: false, error: "INVALID_VOICE_MESSAGE" }, 400);
      }
      const { data: row } = await supabaseAdmin.from("legal_consultations")
        .select("user_uid, lawyer_uid, chat_started_at, chat_duration_minutes, status")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);
      const participant = row.user_uid === uid || (isLawyer(role) && row.lawyer_uid === uid);
      if (!participant) return json({ success: false, error: "NOT_PARTICIPANT" }, 403);
      if (!row.chat_started_at || Number(row.status) !== 1) return json({ success: false, error: "CHAT_NOT_OPEN" }, 409);
      const endAt = new Date(row.chat_started_at).getTime() + (Number(row.chat_duration_minutes) || 15) * 60000;
      if (Date.now() >= endAt) return json({ success: false, error: "CHAT_TIME_EXPIRED" }, 409);
      let bytes: Uint8Array;
      try { bytes = base64ToUint8Array(encoded); } catch { return json({ success: false, error: "INVALID_AUDIO_CONTENT" }, 400); }
      if (bytes.length < 12 || bytes.length > 8 * 1024 * 1024) return json({ success: false, error: "INVALID_AUDIO_SIZE" }, 400);
      // AAC/M4A: صندوق ftyp يبدأ عند البايت الرابع.
      const isM4a = String.fromCharCode(...bytes.slice(4, 8)) === "ftyp";
      if (!isM4a) return json({ success: false, error: "INVALID_AUDIO_CONTENT" }, 400);
      const actualDuration = readM4aDurationSeconds(bytes);
      if (actualDuration == null || actualDuration < 0.5 || actualDuration > 61.5) {
        return json({ success: false, error: "INVALID_AUDIO_DURATION" }, 400);
      }
      if (Math.abs(actualDuration - duration) > 3) {
        return json({ success: false, error: "AUDIO_DURATION_MISMATCH" }, 400);
      }
      const path = `${uid}/chat/${consultId}/${crypto.randomUUID()}.m4a`;
      const { error } = await supabaseAdmin.storage.from("consultation_files")
        .upload(path, bytes, { contentType: "audio/mp4", cacheControl: "3600", upsert: false });
      if (error) return json({ success: false, error: "CHAT_VOICE_UPLOAD_FAILED" }, 400);
      return json({ success: true, path });
    }

    // ─── تنظيف ملف محادثة رُفع لكن فشل ربطه برسالة ───
    if (action === "discard_chat_upload") {
      const consultId = (body.consultation_id ?? "").toString();
      const path = (body.path ?? "").toString();
      if (!consultId || !path.startsWith(`${uid}/chat/${consultId}/`) || path.includes("..")) {
        return json({ success: false, error: "INVALID_FILE_PATH" }, 403);
      }
      const { data: row } = await supabaseAdmin.from("legal_consultations")
        .select("user_uid, lawyer_uid").eq("id", consultId).eq("i_del", 0).maybeSingle();
      const participant = row?.user_uid === uid || (isLawyer(role) && row?.lawyer_uid === uid);
      if (!participant) return json({ success: false, error: "NOT_PARTICIPANT" }, 403);
      const { count } = await supabaseAdmin.from("consultation_chats")
        .select("id", { count: "exact", head: true }).eq("file_url", path).eq("i_del", 0);
      if ((count ?? 0) > 0) return json({ success: false, error: "FILE_ALREADY_LINKED" }, 409);
      const { error } = await supabaseAdmin.storage.from("consultation_files").remove([path]);
      if (error) return json({ success: false, error: "CHAT_UPLOAD_CLEANUP_FAILED" }, 400);
      return json({ success: true });
    }

    // ─── إرسال رسالة في المحادثة ───
    if (action === "send_chat_message") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const messageType = (body.message_type ?? "text").toString();
      const content = (body.content ?? "").toString().trim();
      const fileUrl = (body.file_url ?? "").toString();
      const fileName = (body.file_name ?? "").toString();
      const durationSeconds = body.duration_seconds ? Number(body.duration_seconds) : null;
      let clientMessageId = (body.client_message_id ?? "").toString();

      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      // توافق مؤقت مع النسخ المثبتة قبل هذا التحصين؛ النسخة الجديدة ترسل UUID ثابتاً.
      if (!clientMessageId) clientMessageId = crypto.randomUUID();
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(clientMessageId)) {
        return json({ success: false, error: "CLIENT_MESSAGE_ID_REQUIRED" }, 400);
      }
      if (!["text", "image", "voice"].includes(messageType)) {
        return json({ success: false, error: "INVALID_MESSAGE_TYPE" }, 400);
      }
      if (messageType === "text" && !content) return json({ success: false, error: "CONTENT_REQUIRED" }, 400);
      if (content.length > 4000) return json({ success: false, error: "MESSAGE_TOO_LONG" }, 413);
      if (fileName.length > 160) return json({ success: false, error: "FILE_NAME_TOO_LONG" }, 413);
      if (messageType !== "text" && !fileUrl) return json({ success: false, error: "FILE_REQUIRED" }, 400);
      if (messageType === "voice" && (!durationSeconds || durationSeconds < 1 || durationSeconds > 60)) {
        return json({ success: false, error: "INVALID_VOICE_DURATION" }, 400);
      }

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, chat_started_at, chat_duration_minutes, status")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // التحقق: المستخدم أو المحامي المُسند فقط
      const isStudent = row.user_uid === uid;
      const isAssignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      if (!isStudent && !isAssignedLawyer) {
        return json({ success: false, error: "NOT_PARTICIPANT" }, 403);
      }
      if (messageType !== "text" &&
          (!fileUrl.startsWith(`${uid}/chat/${consultId}/`) || fileUrl.includes(".."))) {
        return json({ success: false, error: "INVALID_FILE_PATH" }, 403);
      }

      if (Number(row.status) !== 1) return json({ success: false, error: "CHAT_CLOSED" }, 409);
      if (!row.chat_started_at) return json({ success: false, error: "CHAT_NOT_STARTED" }, 400);
      const startedAt = new Date(row.chat_started_at).getTime();
      const durationMs = (Number(row.chat_duration_minutes) || 15) * 60 * 1000;
      if (Date.now() >= startedAt + durationMs) {
        return json({ success: false, error: "CHAT_TIME_EXPIRED" }, 409);
      }

      // التحقق: المحادثة لم تتجاوز 7 أيام
      const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
      if (Date.now() > startedAt + sevenDaysMs) {
        return json({ success: false, error: "CHAT_EXPIRED_7DAYS", message: "انتهت صلاحية المحادثة (7 أيام)" }, 400);
      }

      // عدم التكرار: إعادة نفس الطلب الشبكي تعيد الرسالة نفسها بلا إشعار ثانٍ.
      const { data: existingMessage } = await supabaseAdmin
        .from("consultation_chats")
        .select("*")
        .eq("consultation_id", consultId)
        .eq("sender_id", uid)
        .eq("client_message_id", clientMessageId)
        .maybeSingle();
      if (existingMessage) return json({ success: true, message: existingMessage, duplicate: true });

      // حد إساءة الاستخدام: عشرون رسالة في الدقيقة لكل مرسل داخل الاستشارة.
      const minuteAgo = new Date(Date.now() - 60_000).toISOString();
      const { count: recentCount } = await supabaseAdmin
        .from("consultation_chats")
        .select("id", { count: "exact", head: true })
        .eq("consultation_id", consultId)
        .eq("sender_id", uid)
        .gte("ts_crt", minuteAgo);
      if ((recentCount ?? 0) >= 20) {
        return json({ success: false, error: "CHAT_RATE_LIMIT" }, 429);
      }

      // حفظ الرسالة
      const { data: msg, error: insertErr } = await supabaseAdmin
        .from("consultation_chats").insert({
          consultation_id: consultId, sender_id: uid,
          message_type: messageType, content,
          file_url: fileUrl || null, file_name: fileName || null,
          duration_seconds: durationSeconds, client_message_id: clientMessageId,
        }).select().single();
      if (insertErr?.code === "23505") {
        const { data: duplicate } = await supabaseAdmin.from("consultation_chats")
          .select("*").eq("consultation_id", consultId)
          .eq("sender_id", uid).eq("client_message_id", clientMessageId).maybeSingle();
        if (duplicate) return json({ success: true, message: duplicate, duplicate: true });
      }
      if (insertErr) return json({ success: false, error: insertErr.message }, 400);

      // إشعار الطرف الآخر
      const recipientUid = isStudent ? row.lawyer_uid : row.user_uid;
      if (recipientUid) {
        // 🔒 حماية الخصوصية: لا نعرض محتوى الرسالة في Push (يظهر على شاشة القفل)
        const inAppPreview = messageType === "text" ? content.slice(0, 50) : messageType === "voice" ? "🎤 رسالة صوتية" : "📎 صورة";
        await supabaseAdmin.from("notifications").insert({
          uid: recipientUid, tp: 1, ttl: "💬 رسالة جديدة",
          bdy: inAppPreview, ref_id: consultId, act: "chat_message", i_rd: 0, i_del: 0,
          ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: recipientUid, p_title: "💬 رسالة جديدة",
            p_body: "لديك رسالة جديدة في الاستشارة القانونية",
            p_data: { act: "chat_message", ref_id: consultId },
          });
        } catch {}
      }

      // حدث لحظي بلا محتوى حساس؛ الطرف الآخر يعيد الجلب عبر الحارس.
      try {
        const channel = supabaseAdmin.channel(`consultation:${consultId}`);
        await channel.send({
          type: "broadcast",
          event: "messages_changed",
          payload: { changed: true },
        });
        await supabaseAdmin.removeChannel(channel);
      } catch { /* الإشعار يبقى مساراً احتياطياً */ }

      return json({ success: true, message: msg });
    }

    // ─── جلب رسائل المحادثة ───
    if (action === "get_chat_messages") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, chat_started_at, chat_duration_minutes, extended, renew_count, status, lawyer_alias")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // التحقق: المشارك فقط
      const isStudent = row.user_uid === uid;
      const isAssignedLawyer = isLawyer(role) && row.lawyer_uid === uid;
      const isReadOnlyManager = Number(role) === 6;
      if (!isStudent && !isAssignedLawyer && !isReadOnlyManager) {
        return json({ success: false, error: "NOT_PARTICIPANT" }, 403);
      }

      const pageSize = Math.min(100, Math.max(20, Number(body.limit ?? 50)));
      const before = (body.before ?? "").toString();
      let messagesQuery = supabaseAdmin.from("consultation_chats")
        .select("*").eq("consultation_id", consultId).eq("i_del", 0)
        .order("ts_crt", { ascending: false }).limit(pageSize + 1);
      if (before) messagesQuery = messagesQuery.lt("ts_crt", before);
      const { data: rawMessages, error: msgErr } = await messagesQuery;
      if (msgErr) return json({ success: false, error: msgErr.message }, 400);
      const hasMore = (rawMessages?.length ?? 0) > pageSize;
      const messages = (rawMessages ?? []).slice(0, pageSize).reverse();

      // توقيع روابط الملفات
      const signedMessages = await Promise.all(messages.map(async (m: Record<string, unknown>) => {
        const msg = { ...m };
        const fileUrl = (msg.file_url ?? "").toString();
        if (fileUrl && !fileUrl.startsWith("http")) {
          const { data } = await supabaseAdmin.storage
            .from("consultation_files").createSignedUrl(fileUrl, 3600);
          if (data?.signedUrl) msg.file_signed_url = data.signedUrl;
        }
        return msg;
      }));

      // تحديد الرسائل غير المقروءة كمقروءة (للطرف الآخر)
      const otherUid = isStudent ? row.lawyer_uid : isAssignedLawyer ? row.user_uid : null;
      if (otherUid) {
        const { data: readRows } = await supabaseAdmin.from("consultation_chats")
          .update({ is_read: true })
          .eq("consultation_id", consultId)
          .eq("is_read", false)
          .neq("sender_id", uid)
          .select("id");
        if ((readRows?.length ?? 0) > 0) {
          try {
            const channel = supabaseAdmin.channel(`consultation:${consultId}`);
            await channel.send({
              type: "broadcast", event: "messages_read", payload: { changed: true },
            });
            await supabaseAdmin.removeChannel(channel);
          } catch { /* القراءة ستظهر عند الجلب التالي */ }
        }
      }

      // حساب الوقت المتبقي
      let remainingSeconds = 0;
      let chatExpired = false;
      if (row.chat_started_at) {
        const startedAt = new Date(row.chat_started_at).getTime();
        const durationMs = (Number(row.chat_duration_minutes) || 15) * 60 * 1000;
        const elapsed = Date.now() - startedAt;
        remainingSeconds = Math.max(0, Math.floor((durationMs - elapsed) / 1000));
        chatExpired = elapsed > durationMs;
      }

      return json({
        success: true,
        messages: signedMessages,
        has_more: hasMore,
        chat_info: {
          chat_started_at: row.chat_started_at,
          chat_duration_minutes: row.chat_duration_minutes,
          extended: row.extended,
          renew_count: row.renew_count ?? 0,
          remaining_seconds: remainingSeconds,
          chat_expired: chatExpired,
          lawyer_alias: row.lawyer_alias ?? "محامي المكتب",
          status: row.status,
        },
      });
    }

    // ─── تمديد المحادثة (5 دقائق — مرة واحدة فقط) ───
    if (action === "extend_chat") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, extended, chat_duration_minutes, chat_started_at, status")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // فقط المحامي المُسند يمدد؛ الإدارة لا تنوب عنه في هبة الوقت المجانية.
      if (!isLawyer(role) || row.lawyer_uid !== uid) {
        return json({ success: false, error: "NOT_ASSIGNED_LAWYER" }, 403);
      }
      if (Number(row.status) !== 1) return json({ success: false, error: "CHAT_CLOSED" }, 409);
      if (row.extended) return json({ success: false, error: "ALREADY_EXTENDED" }, 400);
      if (!row.chat_started_at) return json({ success: false, error: "CHAT_NOT_STARTED" }, 400);
      const currentDuration = Number(row.chat_duration_minutes) || 15;
      const currentEnd = new Date(row.chat_started_at).getTime() + currentDuration * 60 * 1000;
      if (Date.now() > currentEnd + 5 * 60 * 1000) {
        return json({ success: false, error: "EXTENSION_WINDOW_EXPIRED" }, 409);
      }

      const newDuration = currentDuration + 5;
      const { data: extendedRows, error: extendErr } = await supabaseAdmin
        .from("legal_consultations").update({
          extended: true, extended_by: uid, chat_duration_minutes: newDuration,
        })
        .eq("id", consultId)
        .eq("status", 1)
        .eq("extended", false)
        .select("id");
      if (extendErr) return json({ success: false, error: extendErr.message }, 400);
      if (!extendedRows || extendedRows.length !== 1) {
        return json({ success: false, error: "ALREADY_EXTENDED" }, 409);
      }

      // رسالة system
      await supabaseAdmin.from("consultation_chats").insert({
        consultation_id: consultId, sender_id: uid,
        message_type: "system", content: "⏱️ تم تمديد المحادثة 5 دقائق إضافية",
      });

      // إشعار الطالب
      if (row.user_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: row.user_uid, tp: 1, ttl: "⏱️ تم تمديد المحادثة",
          bdy: "المحامي مدّد المحادثة 5 دقائق إضافية",
          ref_id: consultId, act: "chat_extended", i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: row.user_uid, p_title: "⏱️ تمديد المحادثة",
            p_body: "5 دقائق إضافية",
            p_data: { act: "chat_extended", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, new_duration: newDuration });
    }

    // ─── إبلاغ الإدارة عن مشكلة في الاستشارة ───
    if (action === "report_consultation_issue") {
      const consultId = (body.consultation_id ?? "").toString();
      const details = (body.details ?? "").toString().trim();
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      if (details.length < 10 || details.length > 1000) {
        return json({ success: false, error: "REPORT_DETAILS_INVALID" }, 400);
      }
      const { data: row } = await supabaseAdmin.from("legal_consultations")
        .select("user_uid, lawyer_uid").eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);
      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      const { count } = await supabaseAdmin.from("reports")
        .select("id", { count: "exact", head: true })
        .eq("rep_uid", uid).eq("tgt_tp", 4).eq("tgt_id", consultId).eq("sts", 0);
      if ((count ?? 0) > 0) return json({ success: false, error: "REPORT_ALREADY_OPEN" }, 409);
      const { error } = await supabaseAdmin.from("reports").insert({
        rep_uid: uid, tgt_uid: row.lawyer_uid, tgt_tp: 4,
        tgt_id: consultId, rsn: 6, det: details, sts: 0,
      });
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true });
    }

    // ─── تقييم الاستشارة ───
    if (action === "rate_consultation") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const rating = Number(body.rating ?? 0);
      const comment = (body.comment ?? "").toString().trim();

      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      if (rating < 1 || rating > 5) return json({ success: false, error: "INVALID_RATING" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, rating, status, service_type, chat_started_at, chat_duration_minutes")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      // فقط صاحب الاستشارة يقيّم
      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (row.rating) return json({ success: false, error: "ALREADY_RATED" }, 400);

      // 🔒 BUG-029 (2026-08-14): لم يكن هناك فحص للحالة ⇒ المستخدم يقيّم
      // استشارة **لم تُنجَز بعد** (status=1 «مؤكدة» أو حتى 0 «بانتظار
      // المحامي»). أُكِّد حياً: تقييم 5 نجوم مرّ على استشارة قيد التنفيذ.
      // والأثر مزدوج: (1) تقييم بلا خدمة يشوّه متوسط تقييم المحامي؛
      // (2) التقييم يُقبل **مرة واحدة** (ALREADY_RATED) فيفقد المستخدم
      // فرصته الحقيقية بعد انتهاء الخدمة فعلاً.
      // القاعدة: التقييم بعد الإنجاز فقط (status = 2 «مكتملة»).
      let effectiveStatus = Number(row.status);
      if (effectiveStatus === 1 && Number(row.service_type) === 0 && row.chat_started_at) {
        const endAt = new Date(row.chat_started_at).getTime() +
          (Number(row.chat_duration_minutes) || 15) * 60 * 1000;
        if (Date.now() >= endAt) {
          const { data: closed } = await supabaseAdmin.from("legal_consultations")
            .update({ status: 2, ts_upd: new Date().toISOString() })
            .eq("id", consultId).eq("status", 1).select("id");
          if ((closed?.length ?? 0) === 1) effectiveStatus = 2;
        }
      }
      if (effectiveStatus !== 2) {
        return json({
          success: false,
          error: "CONSULTATION_NOT_COMPLETED",
          detail: "يمكن التقييم بعد اكتمال الاستشارة فقط.",
        }, 409);
      }

      const { data: ratedRows, error: rateErr } = await supabaseAdmin
        .from("legal_consultations").update({
          rating, rating_comment: comment || null,
        }).eq("id", consultId).eq("status", 2).is("rating", null).select("id");
      if (rateErr) return json({ success: false, error: rateErr.message }, 400);
      if (!ratedRows || ratedRows.length !== 1) {
        return json({ success: false, error: "ALREADY_RATED" }, 409);
      }

      return json({ success: true });
    }

    // ─── إعادة تفعيل الاستشارة (بعد عدم رد المحامي) ───
    if (action === "reactivate_consultation") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, status, ts_crt, reactivate_count")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);

      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (Number(row.status) !== 0) return json({ success: false, error: "NOT_PENDING" }, 400);

      // التحقق: مرّت ساعة على الأقل
      const createdAt = new Date(row.ts_crt).getTime();
      const hoursPassed = (Date.now() - createdAt) / (1000 * 60 * 60);
      if (hoursPassed < 1) return json({ success: false, error: "TOO_EARLY", hours_remaining: Math.ceil(1 - hoursPassed) }, 400);

      const now = new Date().toISOString();
      const newCount = (Number(row.reactivate_count) || 0) + 1;
      await supabaseAdmin.from("legal_consultations").update({
        reactivate_count: newCount, last_reactivate_at: now,
      }).eq("id", consultId);

      // إشعار المحامي
      if (row.lawyer_uid) {
        await supabaseAdmin.from("notifications").insert({
          uid: row.lawyer_uid, tp: 1, ttl: "🔔 إعادة تفعيل استشارة",
          bdy: `المستخدم أعاد تفعيل طلب الاستشارة (المرة ${newCount})`,
          ref_id: consultId, act: "consultation_reactivated", i_rd: 0, i_del: 0, ts_crt: now,
        });
        try {
          await supabaseAdmin.rpc("send_push_notification", {
            p_uid: row.lawyer_uid, p_title: "🔔 استشارة معاد تفعيلها",
            p_body: `المرة ${newCount}`,
            p_data: { act: "consultation_reactivated", ref_id: consultId },
          });
        } catch {}
      }

      return json({ success: true, reactivate_count: newCount });
    }

    // ─── التجديد لا يتم من هذا الإجراء إطلاقاً ───
    // المسار الوحيد: إنشاء دفعة meta.continue_chat ثم اعتمادها إدارياً عبر
    // approve_payment_final_v2. إبقاء الاسم يعيد خطأً واضحاً للعملاء القدماء.
    if (action === "renew_chat") {
      return json({
        success: false,
        error: "يلزم إنشاء دفعة تجديد وانتظار اعتمادها من الإدارة أولاً.",
        code: "RENEWAL_PAYMENT_REQUIRED",
      }, 409);
    }

    // ─── جلب المحادثات السابقة (لخيار المتابعة) ───
    if (action === "list_previous_chats") {
      const { data, error } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, subject, lawyer_alias, chat_started_at, chat_duration_minutes, renew_count, status, ts_crt")
        .eq("user_uid", uid)
        .eq("service_type", 0) // هاتفية فقط
        .in("status", [1, 2]) // مؤكدة أو منتهية
        .eq("i_del", 0)
        .order("ts_crt", { ascending: false })
        .limit(10);
      if (error) return json({ success: false, error: error.message }, 400);
      return json({ success: true, consultations: data ?? [] });
    }

    // ─── تحويل لحضورية مع خصم ───
    // ─── 🔀 تحويل الاستشارة الهاتفية إلى جلسة حضورية (أُصلح 2026-08-14) ───
    // كان مكسوراً منطقياً بعد اعتماد نظام المواعيد:
    //   ❌ لا يُنشئ موعداً (فتصير حضورية بلا موعد — الفراغ الذي أصلحناه)
    //   ❌ لا يغيّر service_type من 0 إلى 1 (تبقى «هاتفية» بالواجهة)
    //   ❌ لا يتحقق من توفر السلوت ولا يمنع التعارض
    // الآن: يشترط اختيار موعد متاح، ويُنشئ الموعد، ويحوّل النوع فعلياً،
    // ويحسب الفرق المستحق من الإعدادات (الحضورية − المدفوع سابقاً).
    if (action === "convert_to_onsite") {
      const consultId = (body.consultation_id ?? body.consultationId)?.toString() ?? "";
      const slot = (body.slot ?? "").toString();
      if (!consultId) return json({ success: false, error: "CONSULTATION_ID_REQUIRED" }, 400);
      if (!slot) return json({ success: false, error: "SLOT_REQUIRED_FOR_ONSITE" }, 400);

      const { data: row } = await supabaseAdmin
        .from("legal_consultations")
        .select("id, user_uid, lawyer_uid, price, status, service_type, converted_to_onsite, subject")
        .eq("id", consultId).eq("i_del", 0).maybeSingle();
      if (!row) return json({ success: false, error: "CONSULTATION_NOT_FOUND" }, 404);
      if (row.user_uid !== uid) return json({ success: false, error: "NOT_OWNER" }, 403);
      if (row.converted_to_onsite) return json({ success: false, error: "ALREADY_CONVERTED" }, 400);
      if (Number(row.service_type) === 1) {
        return json({ success: false, error: "ALREADY_ONSITE" }, 400);
      }
      if (![0, 1, 5].includes(Number(row.status))) {
        return json({ success: false, error: "CONSULTATION_NOT_CONVERTIBLE" }, 409);
      }
      if (!row.lawyer_uid) {
        return json({ success: false, error: "NO_LAWYER_ASSIGNED" }, 409);
      }

      // السلوت يجب أن يكون ضمن أوقات المحامي وغير محجوز (منع التعارض)
      const { data: freeSlots } = await supabaseAdmin
        .rpc("get_lawyer_free_slots", { p_lawyer_uid: row.lawyer_uid, p_days: 30 });
      const wanted = new Date(slot).getTime();
      const isFree = ((freeSlots ?? []) as Record<string, unknown>[])
        .some((r) => new Date(String(r.slot_dt)).getTime() === wanted);
      if (!isFree) return json({ success: false, error: "SLOT_NO_LONGER_AVAILABLE" }, 409);

      const priceCfg = await getLegalPrices(supabaseAdmin);
      const discount = Number(row.price) || priceCfg.phone;
      const remainingAmount = Math.max(0, priceCfg.onsite - discount);

      const { data: appt, error: apptErr } = await supabaseAdmin
        .from("appointments")
        .insert({
          bkr_id: row.lawyer_uid, req_uid: uid, dt: slot, sts: 0,
          ts_crt: new Date().toISOString(),
          executor_notes: String(row.subject ?? "").slice(0, 200),
        })
        .select("id").single();
      if (apptErr) return json({ success: false, error: apptErr.message }, 400);

      await supabaseAdmin.from("legal_consultations").update({
        service_type: 1,                 // تصبح حضورية فعلياً
        converted_to_onsite: true,
        onsite_discount: discount,
        appointment_id: appt?.id ?? null,
        requested_slot: slot,
        status: 0,                       // بانتظار تأكيد المحامي للموعد
        ts_upd: new Date().toISOString(),
      }).eq("id", consultId);

      // إشعار المحامي بالتحويل والموعد
      await supabaseAdmin.from("notifications").insert({
        uid: row.lawyer_uid, tp: 1, ttl: "🔀 تحويل إلى جلسة حضورية",
        bdy: `حوّل العميل استشارته لجلسة حضورية — راجع «مواعيدي» وأكّد الموعد.`,
        ref_id: consultId, act: "legal_consultation_new",
        i_rd: 0, i_del: 0, ts_crt: new Date().toISOString(),
      });
      try {
        await supabaseAdmin.rpc("send_push_notification", {
          p_uid: row.lawyer_uid, p_title: "🔀 تحويل إلى جلسة حضورية",
          p_body: "موعد جديد بانتظار تأكيدك",
          p_data: { act: "legal_consultation_new", ref_id: consultId },
        });
      } catch { /* push ثانوي */ }

      return json({
        success: true, discount, remaining_amount: remainingAmount,
        appointment_id: appt?.id ?? null,
      });
    }

    return json({ success: false, error: "UNKNOWN_ACTION" }, 400);
  } catch (error) {
    return json({ success: false, error: (error as Error).message }, 500);
  }
});
