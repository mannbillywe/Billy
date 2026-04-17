/**
 * Shared helper: dispatch a Goat Mode job to the Billy AI backend on Cloud Run.
 *
 * The caller is responsible for:
 *   1. authenticating the Supabase user
 *   2. deriving `user_id` from the auth context (NEVER trust the client body)
 *   3. validating the payload fields before calling `dispatchGoatBackend`
 *
 * This helper owns:
 *   - reading backend URL + shared secret from Deno env
 *   - setting the X-Goat-Backend-Secret header (never echoed back in responses)
 *   - minting a Google-signed ID token when GCP_INVOKER_SA_KEY is present,
 *     so we satisfy Cloud Run IAM invoker when the service is private
 *   - reasonable timeout handling
 *   - stable error shaping so route handlers can pass through cleanly
 */

import { getGoogleIdToken, isGcpAuthConfigured } from "./gcp_id_token.ts";

export interface GoatBackendPayload {
  user_id: string;
  scope: string;
  range_start?: string | null;
  range_end?: string | null;
  dry_run?: boolean;
  trigger_source?: string;
}

export interface GoatBackendResult {
  ok: boolean;
  status: number;
  body: unknown;
  error?: { code: string; message: string };
}

const DEFAULT_TIMEOUT_MS = 120_000; // Goat jobs can be chunky on rich users.

function readBackendConfig(): { url: string; secret: string; error?: string } {
  const url = (Deno.env.get("GOAT_BACKEND_URL") ?? "").trim();
  const secret = (Deno.env.get("GOAT_BACKEND_SHARED_SECRET") ?? "").trim();
  if (!url) {
    return { url: "", secret: "", error: "GOAT_BACKEND_URL not configured" };
  }
  if (!secret) {
    return { url, secret: "", error: "GOAT_BACKEND_SHARED_SECRET not configured" };
  }
  return { url: url.replace(/\/+$/, ""), secret };
}

export async function dispatchGoatBackend(
  payload: GoatBackendPayload,
  opts: { timeoutMs?: number } = {},
): Promise<GoatBackendResult> {
  const cfg = readBackendConfig();
  if (cfg.error) {
    return {
      ok: false,
      status: 503,
      body: null,
      error: { code: "BACKEND_MISCONFIGURED", message: cfg.error },
    };
  }

  const controller = new AbortController();
  const timeoutMs = opts.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const tid = setTimeout(() => controller.abort(), timeoutMs);

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-Goat-Backend-Secret": cfg.secret,
  };

  // If a GCP SA key is configured, mint an ID token so Cloud Run's IAM
  // invoker check passes for private services. When not configured (e.g.
  // --allow-unauthenticated Cloud Run, or local backend), skip this.
  if (isGcpAuthConfigured()) {
    try {
      const idToken = await getGoogleIdToken(cfg.url);
      headers["Authorization"] = `Bearer ${idToken}`;
    } catch (err) {
      clearTimeout(tid);
      return {
        ok: false,
        status: 503,
        body: null,
        error: {
          code: "BACKEND_AUTH_FAILED",
          message: `Failed to mint Cloud Run ID token: ${(err as Error).message}`,
        },
      };
    }
  }

  let response: Response;
  try {
    response = await fetch(`${cfg.url}/goat-mode/run`, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
  } catch (err) {
    clearTimeout(tid);
    const aborted = err instanceof DOMException && err.name === "AbortError";
    return {
      ok: false,
      status: aborted ? 504 : 502,
      body: null,
      error: {
        code: aborted ? "BACKEND_TIMEOUT" : "BACKEND_UNREACHABLE",
        message: aborted
          ? `Backend did not respond within ${timeoutMs}ms`
          : `Failed to reach backend: ${(err as Error).message}`,
      },
    };
  } finally {
    clearTimeout(tid);
  }

  let parsed: unknown = null;
  const text = await response.text();
  if (text) {
    try {
      parsed = JSON.parse(text);
    } catch {
      parsed = { raw: text };
    }
  }

  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      body: parsed,
      error: {
        code: response.status === 401
          ? "BACKEND_REJECTED_SECRET"
          : `BACKEND_HTTP_${response.status}`,
        message: (parsed as { detail?: string } | null)?.detail ??
          `Backend returned HTTP ${response.status}`,
      },
    };
  }

  return { ok: true, status: response.status, body: parsed };
}
