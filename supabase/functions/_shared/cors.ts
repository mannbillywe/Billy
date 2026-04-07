/**
 * CORS for Edge Functions: strict browser origins + permissive non-browser (no Origin).
 *
 * Operator checklist (see docs/PRODUCTION_READINESS.md A6):
 * - In Supabase Dashboard → Edge Functions → Secrets: set ALLOWED_ORIGINS to a comma-separated
 *   list of any extra origins (production + staging custom domains) beyond DEFAULT_ALLOWLIST.
 * - Preview URLs: *.vercel.app patterns are allowed via vercelPreviewOrigin().
 * - After changing secrets, redeploy process-invoice and analytics-insights.
 */

const DEFAULT_ALLOWLIST = [
  "http://localhost:3000",
  "http://127.0.0.1:3000",
  "http://localhost:8080",
  "http://127.0.0.1:8080",
  "http://localhost:54321",
  "https://web-iota-lilac-34.vercel.app",
  "https://billycon.vercel.app",
  "https://web-15rpy0ypp-mannbillywes-projects.vercel.app",
];

function vercelPreviewOrigin(origin: string): boolean {
  return /^https:\/\/[a-z0-9-]+-mannbillywes-projects\.vercel\.app$/i.test(origin) ||
    /^https:\/\/[a-z0-9-]+-[a-z0-9]+\.vercel\.app$/i.test(origin);
}

function loadAllowedOrigins(): Set<string> {
  const set = new Set(DEFAULT_ALLOWLIST);
  const extra = Deno.env.get("ALLOWED_ORIGINS");
  if (extra) {
    for (const part of extra.split(",")) {
      const t = part.trim();
      if (t.length > 0) set.add(t);
    }
  }
  return set;
}

const ALLOWED = loadAllowedOrigins();

export function resolveCorsOrigin(req: Request): string {
  const origin = req.headers.get("Origin");
  if (!origin || origin === "null") {
    return "*";
  }
  if (ALLOWED.has(origin) || vercelPreviewOrigin(origin)) {
    return origin;
  }
  return "";
}

export function corsHeadersFor(req: Request): Record<string, string> {
  const requested = req.headers.get("access-control-request-headers");
  const allowHeaders =
    requested?.trim() ||
    "authorization, x-client-info, apikey, content-type, accept, accept-encoding";
  const allowOrigin = resolveCorsOrigin(req);

  if (allowOrigin === "") {
    return {
      "Access-Control-Allow-Headers": allowHeaders,
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Max-Age": "86400",
      Vary: "Origin",
    };
  }

  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Headers": allowHeaders,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}
