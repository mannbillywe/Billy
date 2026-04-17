/**
 * Mint a Google-signed ID token for invoking a Cloud Run service from a
 * Supabase Edge Function.
 *
 * Expects the service-account key JSON to be provided in the function secret
 * `GCP_INVOKER_SA_KEY` (the entire JSON file contents, as a string). The SA
 * must have `roles/run.invoker` on the target Cloud Run service.
 *
 * Flow:
 *   1. Build a JWT signed with the SA private key (RS256) whose audience is
 *      https://oauth2.googleapis.com/token and whose `target_audience` claim
 *      is the Cloud Run service URL.
 *   2. Exchange it at Google's OAuth2 token endpoint for an ID token.
 *   3. Use that ID token as `Authorization: Bearer <id_token>` on Cloud Run.
 *
 * ID tokens are valid for 1 hour. We cache per-audience for 55 minutes.
 */

interface SaKeyJson {
  client_email: string;
  private_key: string;
  token_uri?: string;
}

interface CachedToken {
  idToken: string;
  expiresAt: number; // epoch ms
}

const cache = new Map<string, CachedToken>();

function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeString(s: string): string {
  return base64UrlEncode(new TextEncoder().encode(s));
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const clean = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(clean);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
}

async function importRsaPrivateKey(pem: string): Promise<CryptoKey> {
  const pkcs8 = pemToPkcs8(pem);
  return await crypto.subtle.importKey(
    "pkcs8",
    pkcs8,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function signAssertionJwt(sa: SaKeyJson, targetAudience: string): Promise<string> {
  const header = { alg: "RS256", typ: "JWT" };
  const nowSec = Math.floor(Date.now() / 1000);
  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: sa.token_uri ?? "https://oauth2.googleapis.com/token",
    target_audience: targetAudience,
    iat: nowSec,
    exp: nowSec + 3600,
  };
  const headerB64 = base64UrlEncodeString(JSON.stringify(header));
  const payloadB64 = base64UrlEncodeString(JSON.stringify(payload));
  const toSign = `${headerB64}.${payloadB64}`;

  const key = await importRsaPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    { name: "RSASSA-PKCS1-v1_5" },
    key,
    new TextEncoder().encode(toSign),
  );
  const sigB64 = base64UrlEncode(new Uint8Array(sig));
  return `${toSign}.${sigB64}`;
}

function readSaKey(): SaKeyJson | { error: string } {
  const raw = Deno.env.get("GCP_INVOKER_SA_KEY");
  if (!raw) return { error: "GCP_INVOKER_SA_KEY not configured" };
  try {
    const parsed = JSON.parse(raw);
    if (!parsed.client_email || !parsed.private_key) {
      return { error: "GCP_INVOKER_SA_KEY missing client_email or private_key" };
    }
    return parsed as SaKeyJson;
  } catch (err) {
    return { error: `GCP_INVOKER_SA_KEY is not valid JSON: ${(err as Error).message}` };
  }
}

/**
 * Return a Google-signed ID token whose `aud` is `targetAudience`.
 * Throws on configuration or signing errors.
 */
export async function getGoogleIdToken(targetAudience: string): Promise<string> {
  const aud = targetAudience.replace(/\/+$/, "");
  const cached = cache.get(aud);
  const now = Date.now();
  if (cached && cached.expiresAt - now > 60_000) {
    return cached.idToken;
  }

  const sa = readSaKey();
  if ("error" in sa) throw new Error(sa.error);

  const assertion = await signAssertionJwt(sa, aud);
  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const form = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion,
  });

  const resp = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });
  const body = await resp.json().catch(() => ({}));
  if (!resp.ok || !body.id_token) {
    const detail = typeof body?.error_description === "string"
      ? body.error_description
      : typeof body?.error === "string"
      ? body.error
      : `HTTP ${resp.status}`;
    throw new Error(`Failed to mint Google ID token: ${detail}`);
  }

  cache.set(aud, {
    idToken: body.id_token,
    expiresAt: now + 55 * 60 * 1000,
  });
  return body.id_token as string;
}

export function isGcpAuthConfigured(): boolean {
  return !!(Deno.env.get("GCP_INVOKER_SA_KEY") ?? "").trim();
}
