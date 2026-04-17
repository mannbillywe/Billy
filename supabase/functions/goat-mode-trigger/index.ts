// goat-mode-trigger: thin orchestrator that authenticates a Supabase user,
// validates the trigger payload, and dispatches the compute job to the
// Billy AI backend on Cloud Run using a shared secret.
//
// Responsibilities (Phase 5):
//   1. Authenticate the caller from the Authorization JWT.
//   2. Derive user_id from auth context — any caller-supplied user_id is
//      ignored (and warned).
//   3. Validate scope + optional date range + dry_run.
//   4. Optional gate on profiles.goat_mode so non-entitled users can't trigger.
//   5. Dispatch to Cloud Run backend via shared secret helper.
//   6. Return a concise, client-safe response.
//
// The function is intentionally boring — NO analytics compute lives here.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import { corsHeadersFor } from "../_shared/cors.ts";
import { dispatchGoatBackend } from "../_shared/backend_dispatch.ts";

type Json = Record<string, unknown>;

const ALLOWED_SCOPES = new Set([
  "overview",
  "cashflow",
  "budgets",
  "recurring",
  "debt",
  "goals",
  "full",
]);

const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function jsonResponse(body: Json, req: Request, status = 200): Response {
  const cors = corsHeadersFor(req);
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function errorResponse(
  req: Request,
  status: number,
  code: string,
  message: string,
  extra?: Json,
): Response {
  return jsonResponse(
    {
      ok: false,
      error: { code, message },
      ...(extra ?? {}),
    },
    req,
    status,
  );
}

serve(async (req) => {
  const cors = corsHeadersFor(req);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return errorResponse(req, 405, "METHOD_NOT_ALLOWED", "POST only");
  }

  const contentLength = parseInt(req.headers.get("content-length") ?? "0", 10);
  if (contentLength > 65_536) {
    return errorResponse(req, 413, "PAYLOAD_TOO_LARGE", "Max 64 KB");
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return errorResponse(req, 401, "UNAUTHORIZED", "Missing authorization");
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnon) {
    return errorResponse(
      req,
      503,
      "FUNCTION_MISCONFIGURED",
      "SUPABASE_URL or SUPABASE_ANON_KEY missing",
    );
  }

  const supabase: SupabaseClient = createClient(supabaseUrl, supabaseAnon, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: authErr } = await supabase.auth.getUser();
  if (authErr || !user) {
    return errorResponse(req, 401, "UNAUTHORIZED", "Invalid session");
  }

  let body: Json;
  try {
    body = (await req.json()) as Json;
  } catch {
    return errorResponse(req, 400, "INVALID_INPUT", "Invalid JSON body");
  }

  // Security invariant: user_id comes ONLY from auth context.
  if (typeof body.user_id === "string" && body.user_id !== user.id) {
    console.warn(
      `goat-mode-trigger: caller ${user.id} tried to impersonate ${body.user_id}; ignoring`,
    );
  }

  const scope = typeof body.scope === "string" ? body.scope : "overview";
  if (!ALLOWED_SCOPES.has(scope)) {
    return errorResponse(
      req,
      400,
      "INVALID_INPUT",
      `scope must be one of ${[...ALLOWED_SCOPES].join(", ")}`,
    );
  }

  const rangeStart = body.range_start;
  const rangeEnd = body.range_end;
  for (const [label, value] of [
    ["range_start", rangeStart],
    ["range_end", rangeEnd],
  ] as const) {
    if (value != null && (typeof value !== "string" || !ISO_DATE_RE.test(value))) {
      return errorResponse(
        req,
        400,
        "INVALID_INPUT",
        `${label} must be YYYY-MM-DD`,
      );
    }
  }

  const dryRun = body.dry_run === true;

  // Light entitlement gate. Absent or false profiles.goat_mode short-circuits.
  // We use the user-scoped client so RLS applies; non-owners can't escalate.
  const { data: profile, error: profErr } = await supabase
    .from("profiles")
    .select("goat_mode")
    .eq("id", user.id)
    .maybeSingle();
  if (profErr) {
    console.error("goat-mode-trigger profile lookup", profErr.message);
  }
  if (profile && profile.goat_mode !== true) {
    return errorResponse(
      req,
      403,
      "GOAT_MODE_NOT_ENABLED",
      "Goat Mode is not enabled for this account.",
    );
  }

  const dispatch = await dispatchGoatBackend({
    user_id: user.id,
    scope,
    range_start: (rangeStart as string | null | undefined) ?? null,
    range_end: (rangeEnd as string | null | undefined) ?? null,
    dry_run: dryRun,
    trigger_source: "manual",
  });

  if (!dispatch.ok) {
    return jsonResponse(
      {
        ok: false,
        error: dispatch.error,
        backend_status: dispatch.status,
      },
      req,
      dispatch.status >= 500 ? 502 : dispatch.status,
    );
  }

  const b = (dispatch.body ?? {}) as Json;
  return jsonResponse(
    {
      ok: true,
      user_id: user.id,
      scope,
      dry_run: dryRun,
      job_id: b.job_id ?? null,
      snapshot_id: b.snapshot_id ?? null,
      readiness_level: b.readiness_level ?? null,
      snapshot_status: b.snapshot_status ?? null,
      data_fingerprint: b.data_fingerprint ?? null,
      recommendation_count: b.recommendation_count ?? 0,
      layer_errors: b.layer_errors ?? {},
      ai: b.ai
        ? {
          mode: (b.ai as Json).mode ?? null,
          model: (b.ai as Json).model ?? null,
          ai_validated: (b.ai as Json).ai_validated ?? false,
          fallback_used: (b.ai as Json).fallback_used ?? true,
        }
        : null,
    },
    req,
  );
});
