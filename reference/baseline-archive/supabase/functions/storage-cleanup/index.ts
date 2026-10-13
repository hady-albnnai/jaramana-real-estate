// Edge Function: storage-cleanup — تنظيف ملفات التخزين التشغيلية (2026-08-28)
//
// الغرض: حذف ملفات باكيتات التشغيل (offer_images / consultation_files /
// expediting_docs / payment_proofs) عبر Storage API — الحذف المباشر من
// storage.objects ممنوع بتريغر المنصة protect_delete (خطأ 42501 مؤكد حياً).
//
// الحماية: المفتاح الوحيد المقبول هو SUPABASE_SERVICE_ROLE_KEY نفسه (يُمرَّر
// كمعامل ?key=). لا يمس ids_private (صور هويات الموظفين) ولا config_assets.
//
// يدعم GET حتى يمكن تشغيله برابط مباشر (للوكيل/المتصفح) — المنصة عادة تفرض
// POST فقط، لكن هذه الدالة تُنشر بـ --no-verify-jwt وفق بروتوكول المشروع.
//
// الاستخدام:
//   GET/POST https://<ref>.supabase.co/functions/v1/storage-cleanup?key=<service_role>

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

// الباكيتات المستهدفة بالحذف حصراً — ids_private و config_assets محرمتان هنا.
const BUCKETS = ["offer_images", "consultation_files", "expediting_docs", "payment_proofs"];

function json(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function listRoot(
  base: string,
  key: string,
  bucket: string,
): Promise<{ ok: true; names: string[] } | { ok: false; error: string }> {
  try {
    const response = await fetch(`${base}/storage/v1/object/list/${bucket}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ prefix: "", limit: 100, offset: 0 }),
    });
    if (!response.ok) {
      return { ok: false, error: `LIST_HTTP_${response.status}` };
    }
    const items = (await response.json().catch(() => [])) as Array<Record<string, unknown>>;
    // ملفات الجذر + المجلدات (معرف null) — حذف بادئة المجلد يمسحه بعمقه كاملاً
    const names = items.map((i) => String(i.name ?? "")).filter(Boolean);
    return { ok: true, names };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}

async function bulkDelete(
  base: string,
  key: string,
  bucket: string,
  prefixes: string[],
): Promise<{ ok: boolean; error?: string }> {
  try {
    const response = await fetch(`${base}/storage/v1/object/${bucket}`, {
      method: "DELETE",
      headers: {
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ prefixes }),
    });
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      return { ok: false, error: `DELETE_HTTP_${response.status}: ${text.slice(0, 200)}` };
    }
    return { ok: true };
  } catch (error) {
    return { ok: false, error: error instanceof Error ? error.message : String(error) };
  }
}

async function countRemaining(base: string, key: string, bucket: string): Promise<number> {
  const result = await listRoot(base, key, bucket);
  return result.ok ? result.names.length : -1;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  // المفتاح: service_role نفسه (يقبل من query للسماح بالتشغيل عبر رابط GET).
  const url = new URL(req.url);
  const provided = url.searchParams.get("key") ?? "";
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!provided || !expected || provided !== expected) {
    return json({ success: false, error: "FORBIDDEN" }, 403);
  }

  const base = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  if (!base) return json({ success: false, error: "SUPABASE_URL_MISSING" }, 500);

  const report: Array<Record<string, unknown>> = [];
  for (const bucket of BUCKETS) {
    let rounds = 0;
    let error = "";
    // حلقة: كل جولة تحذف ملفات/مجلدات الجذر حتى تفرغ (تتعامل مع أي عمق تعشيش)
    while (rounds < 20) {
      rounds++;
      const listed = await listRoot(base, expected, bucket);
      if (!listed.ok) {
        error = listed.error;
        break;
      }
      if (listed.names.length === 0) break;
      const deleted = await bulkDelete(base, expected, bucket, listed.names);
      if (!deleted.ok) {
        error = deleted.error ?? "DELETE_FAILED";
        break;
      }
    }
    const remaining = await countRemaining(base, expected, bucket);
    report.push({ bucket, remaining, rounds, error: error || undefined });
  }

  // تحقق إضافي: الباكيتات المحمية يجب أن تبقى كما هي (قراءة فقط)
  const protectedCounts: Record<string, number> = {};
  for (const bucket of ["ids_private", "config_assets"]) {
    protectedCounts[bucket] = await countRemaining(base, expected, bucket);
  }

  return json({ success: true, report, protectedCounts });
});
