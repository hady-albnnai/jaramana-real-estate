import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json" };
const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

async function removeObjects(
  admin: ReturnType<typeof createClient>,
  objects: Record<string, unknown>[],
) {
  const byBucket = new Map<string, string[]>();
  for (const object of objects) {
    const bucket = String(object.bucket_id ?? "");
    const name = String(object.name ?? "");
    if (!bucket || !name) continue;
    const paths = byBucket.get(bucket) ?? [];
    paths.push(name);
    byBucket.set(bucket, paths);
  }
  let removed = 0;
  const failures: string[] = [];
  for (const [bucket, paths] of byBucket.entries()) {
    for (let i = 0; i < paths.length; i += 100) {
      const batch = paths.slice(i, i + 100);
      const { error } = await admin.storage.from(bucket).remove(batch);
      if (error) failures.push(`${bucket}:${error.message}`);
      else removed += batch.length;
    }
  }
  return { removed, failures };
}

serve(async (req) => {
  if (req.method !== "POST") return json({ success: false, error: "METHOD_NOT_ALLOWED" }, 405);
  const expected = Deno.env.get("CLEANUP_CRON_TOKEN") ?? "";
  const supplied = req.headers.get("x-cleanup-token") ?? "";
  if (!expected || supplied !== expected) return json({ success: false, error: "FORBIDDEN" }, 403);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
  const cutoff = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data: objects, error } = await admin.rpc("list_consultation_orphan_files_v2");
  if (error) return json({ success: false, error: "STORAGE_SCAN_FAILED" }, 500);
  const result = await removeObjects(admin, (objects ?? []) as Record<string, unknown>[]);
  return json({
    success: result.failures.length === 0,
    scanned: objects?.length ?? 0,
    removed: result.removed,
    failures: result.failures,
    cutoff,
  }, result.failures.length === 0 ? 200 : 500);
});
