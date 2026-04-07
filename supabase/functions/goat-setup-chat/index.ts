// goat-setup-chat: Gemini interprets natural-language GOAT setup into strict JSON draft only.
// Auth: JWT. AI key: resolveGoatGeminiKey. Max 2 Gemini calls per user enforced via DB RPC (reserve/release).
// Does not write financial_accounts, income_streams, etc.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

import { corsHeadersFor } from "../_shared/cors.ts";
import { resolveGoatGeminiKey } from "../_shared/resolve_gemini_key.ts";

const GEMINI_MODEL = "gemini-2.5-flash";

type Json = Record<string, unknown>;

function jsonResponse(body: Json, req: Request, status = 200): Response {
  const cors = corsHeadersFor(req);
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function serviceClient(): SupabaseClient | null {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  if (!supabaseUrl || !serviceRoleKey) return null;
  return createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function buildPrompt(
  message: string,
  callIndex: number,
  context: Json | undefined,
): string {
  const safeMsg = message.replace(/</g, " ").slice(0, 12_000);
  const ctxStr = JSON.stringify(context ?? {}).slice(0, 8000);
  const mergeHint = callIndex >= 2
    ? "You are merging a FOLLOW-UP user message with previous_draft in context. Preserve confirmed fields; update only what the new message clarifies."
    : "This is the PRIMARY interpretation pass.";

  return `You are Billy GOAT setup assistant. ${mergeHint}

User message (natural language):
${safeMsg}

Context JSON (existing profile hints, counts, optional previous_draft):
${ctxStr}

Return ONLY valid JSON (no markdown fences). Shape MUST match this schema (use null where unknown; use empty arrays if none):

{
  "profile_defaults": {
    "preferred_currency": "INR | USD | EUR | GBP | AED | SGD | null",
    "goat_analysis_lens": "smart | statements_only | ocr_only | combined_raw | null"
  },
  "accounts": [
    {
      "name": "string | null",
      "account_type": "cash | bank | wallet | credit_card | loan | other | null",
      "current_balance": 0.0,
      "available_credit": 0.0,
      "is_primary": true,
      "include_in_safe_to_spend": true,
      "institution_name": "string | null",
      "source": "manual | inferred",
      "confidence": 0.0,
      "value_origin": "user_provided | inferred | defaulted",
      "warnings": []
    }
  ],
  "income_streams": [
    {
      "title": "string | null",
      "frequency": "weekly | biweekly | monthly | irregular | custom | null",
      "expected_amount": 0.0,
      "next_expected_date": "YYYY-MM-DD | null",
      "notes": "string | null",
      "confidence": 0.0,
      "value_origin": "user_provided | inferred | defaulted",
      "warnings": []
    }
  ],
  "recurring_items": [
    {
      "title": "string | null",
      "kind": "bill | subscription | income | transfer | null",
      "expected_amount": 0.0,
      "frequency": "weekly | biweekly | monthly | quarterly | yearly | custom | null",
      "next_due_date": "YYYY-MM-DD | null",
      "autopay_enabled": true,
      "autopay_method": "upi_autopay | card_autopay | bank_auto_debit | manual | cash | other | null",
      "confidence": 0.0,
      "value_origin": "user_provided | inferred | defaulted",
      "warnings": []
    }
  ],
  "planned_cashflow_events": [
    {
      "title": "string | null",
      "event_date": "YYYY-MM-DD | null",
      "amount": 0.0,
      "direction": "inflow | outflow | null",
      "notes": "string | null",
      "confidence": 0.0,
      "value_origin": "user_provided | inferred | defaulted",
      "warnings": []
    }
  ],
  "goals": [
    {
      "title": "string | null",
      "goal_type": "emergency_fund | sinking_fund | purchase | travel | bill_buffer | debt_paydown | custom | null",
      "target_amount": 0.0,
      "target_date": "YYYY-MM-DD | null",
      "forecast_reserve": "none | soft | hard | null",
      "confidence": 0.0,
      "value_origin": "user_provided | inferred | defaulted",
      "warnings": []
    }
  ],
  "source_preference": {
    "statement_preference": "statements_first | receipts_first | smart_mixed | unknown",
    "has_statement_data_already": true,
    "confidence": 0.0,
    "value_origin": "user_provided | inferred | defaulted"
  },
  "missing_questions": [
    { "key": "string", "question": "string", "priority": "critical | optional" }
  ],
  "readiness_hints": {
    "critical_missing": [],
    "optional_missing": [],
    "summary": "string"
  },
  "overall_confidence": 0.0
}

Rules:
- Never invent exact salary, balances, bills, or goal targets the user did not state. If vague, lower confidence and mark value_origin inferred/defaulted.
- If user says they do not know, leave numbers at 0 with low confidence and a warning explaining uncertainty; do not fabricate.
- Omit entire list entries if there is no usable title or numeric hint for bills/goals (empty array).
- overall_confidence: 0-1 number.
- All confidence fields per row: 0-1.
`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeadersFor(req) });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, req, 405);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  if (!supabaseUrl || !anonKey) {
    return jsonResponse({ error: "server_misconfigured" }, req, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return jsonResponse({ error: "unauthorized" }, req, 401);
  }
  const userId = userData.user.id;

  const svc = serviceClient();
  if (!svc) {
    return jsonResponse({ error: "server_misconfigured" }, req, 500);
  }

  let body: {
    message?: string;
    call_index?: number;
    context?: Json;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, req, 400);
  }

  const message = (body.message ?? "").trim();
  const callIndex = typeof body.call_index === "number" && body.call_index >= 2 ? 2 : 1;
  if (message.length < 3) {
    return jsonResponse({ error: "message_too_short" }, req, 400);
  }

  const { data: reserveRaw, error: reserveErr } = await svc.rpc("goat_setup_reserve_ai_slot", {
    p_user_id: userId,
  });
  if (reserveErr) {
    console.error("goat-setup-chat reserve", reserveErr);
    return jsonResponse({ error: "reserve_failed" }, req, 500);
  }

  const reserve = reserveRaw as Json | null;
  if (!reserve || reserve["ok"] !== true) {
    return jsonResponse({ error: "ai_call_limit", reason: reserve?.["reason"] ?? "limit_exceeded" }, req, 429);
  }

  const setupStateId = reserve["setup_state_id"] as string;
  const callsAfter = Number(reserve["calls_after"] ?? 1);

  const keyPack = await resolveGoatGeminiKey();
  if (!keyPack) {
    await svc.rpc("goat_setup_release_ai_slot", { p_user_id: userId });
    return jsonResponse({ error: "no_ai_key" }, req, 503);
  }

  const prompt = buildPrompt(message, callIndex, body.context);

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(keyPack.key)}`;
  const controller = new AbortController();
  const tid = setTimeout(() => controller.abort(), 90_000);

  let res: Response;
  try {
    res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: 8192 },
      }),
    });
  } catch (e) {
    clearTimeout(tid);
    await svc.rpc("goat_setup_release_ai_slot", { p_user_id: userId });
    console.error("goat-setup-chat gemini fetch", e);
    return jsonResponse({ error: "gemini_unreachable" }, req, 502);
  } finally {
    clearTimeout(tid);
  }

  const gj = (await res.json()) as Record<string, unknown>;
  if (!res.ok) {
    await svc.rpc("goat_setup_release_ai_slot", { p_user_id: userId });
    console.error("goat-setup-chat gemini", res.status, JSON.stringify(gj).slice(0, 500));
    return jsonResponse({ error: "gemini_failed" }, req, 502);
  }

  const text = (gj as { candidates?: { content?: { parts?: { text?: string }[] } }[] })
    .candidates?.[0]?.content?.parts?.[0]?.text;
  if (!text || typeof text !== "string") {
    await svc.rpc("goat_setup_release_ai_slot", { p_user_id: userId });
    return jsonResponse({ error: "empty_model_output" }, req, 502);
  }

  let s = text.trim();
  if (s.startsWith("```")) {
    s = s.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
  }
  if (!s.startsWith("{")) {
    const m = s.match(/\{[\s\S]*\}/);
    if (m) s = m[0];
  }

  let parsed: Json;
  try {
    parsed = JSON.parse(s) as Json;
  } catch {
    await svc.rpc("goat_setup_release_ai_slot", { p_user_id: userId });
    return jsonResponse({ error: "invalid_model_json" }, req, 502);
  }

  const overall = typeof parsed.overall_confidence === "number" ? parsed.overall_confidence : null;
  const followup =
    overall !== null && overall < 0.45 && callsAfter < 2;

  const { data: stateRow, error: selErr } = await svc
    .from("goat_setup_state")
    .select("metadata")
    .eq("id", setupStateId)
    .maybeSingle();

  if (selErr) {
    console.error("goat-setup-chat select state", selErr);
  }

  const prevMeta = (stateRow?.metadata as Json | null) ?? {};
  const nextMeta: Json = {
    ...prevMeta,
    last_ai_interpretation_at: new Date().toISOString(),
    last_ai_confidence: overall,
    followup_needed: followup,
    ai_calls_used: callsAfter,
  };

  const { error: upMetaErr } = await svc
    .from("goat_setup_state")
    .update({
      metadata: nextMeta,
      last_seen_at: new Date().toISOString(),
    })
    .eq("id", setupStateId)
    .eq("user_id", userId);

  if (upMetaErr) {
    console.error("goat-setup-chat update meta", upMetaErr);
  }

  const { data: draftRow, error: insErr } = await svc
    .from("goat_setup_drafts")
    .insert({
      user_id: userId,
      setup_state_id: setupStateId,
      source_message: message,
      parsed_payload: parsed,
      parse_confidence: overall,
      parse_status: "draft",
      ai_call_index: callsAfter,
    })
    .select("id")
    .single();

  if (insErr || !draftRow) {
    console.error("goat-setup-chat insert draft", insErr);
    return jsonResponse({ error: "draft_insert_failed" }, req, 500);
  }

  return jsonResponse({
    ok: true,
    interpretation: parsed,
    draft_id: draftRow.id as string,
    setup_state_id: setupStateId,
    calls_after: callsAfter,
    followup_suggested: followup,
  }, req, 200);
});
