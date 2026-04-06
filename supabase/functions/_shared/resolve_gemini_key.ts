/**
 * Gemini API key resolution for Edge Functions.
 *
 * Default (main Billy / invoice pipeline): GEMINI_API_KEY → app_api_keys.gemini
 * GOAT: GOAT_GEMINI_API_KEY → app_api_keys.goat_gemini → same as default (fallback)
 *
 * Set secrets in Supabase Dashboard → Edge Functions → Secrets.
 * Or insert DB rows (service role): provider = 'gemini' | 'goat_gemini'.
 */
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export type GeminiKeyScope = "default" | "goat";

function createServiceClient(): SupabaseClient | null {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !serviceRoleKey) return null;
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

async function fetchProviderKey(client: SupabaseClient, provider: string): Promise<string | null> {
  const { data } = await client
    .from("app_api_keys")
    .select("api_key")
    .eq("provider", provider)
    .eq("is_active", true)
    .maybeSingle();
  const k = (data?.api_key as string | null)?.trim() ?? "";
  return k.length > 0 ? k : null;
}

/** Main app: env first (matches analytics-insights historical order), then shared `gemini` row. */
export async function resolveDefaultGeminiKey(): Promise<{ key: string; source: string } | null> {
  const fromSecret = Deno.env.get("GEMINI_API_KEY")?.trim() ?? "";
  if (fromSecret.length > 0) {
    return { key: fromSecret, source: "GEMINI_API_KEY" };
  }
  const serviceClient = createServiceClient();
  if (!serviceClient) return null;
  const fromShared = await fetchProviderKey(serviceClient, "gemini");
  if (!fromShared) return null;
  return { key: fromShared, source: "app_api_keys:gemini" };
}

/** GOAT workspace: dedicated env/row when present; otherwise same key as main app. */
export async function resolveGoatGeminiKey(): Promise<{ key: string; source: string } | null> {
  const goatEnv = Deno.env.get("GOAT_GEMINI_API_KEY")?.trim() ?? "";
  if (goatEnv.length > 0) {
    return { key: goatEnv, source: "GOAT_GEMINI_API_KEY" };
  }
  const serviceClient = createServiceClient();
  if (!serviceClient) return await resolveDefaultGeminiKey();
  const fromGoatRow = await fetchProviderKey(serviceClient, "goat_gemini");
  if (fromGoatRow) {
    return { key: fromGoatRow, source: "app_api_keys:goat_gemini" };
  }
  return await resolveDefaultGeminiKey();
}

export async function resolveGeminiKeyForScope(
  scope: GeminiKeyScope,
): Promise<{ key: string; source: string } | null> {
  if (scope === "goat") return await resolveGoatGeminiKey();
  return await resolveDefaultGeminiKey();
}
