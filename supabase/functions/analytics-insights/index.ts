  // analytics-insights: deterministic aggregates + optional dual Gemini (Money Coach + JAI Insight).
  // Default key: GEMINI_API_KEY → app_api_keys.gemini.
  // GOAT key (body gemini_scope=goat, only if profiles.goat): GOAT_GEMINI_API_KEY → app_api_keys.goat_gemini → default chain.

  import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
  import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

  import { corsHeadersFor } from "../_shared/cors.ts";
  import { resolveGeminiKeyForScope, type GeminiKeyScope } from "../_shared/resolve_gemini_key.ts";

  const GEMINI_MODEL = "gemini-2.5-flash-lite";

  type Json = Record<string, unknown>;

  function jsonResponse(body: Json, req: Request, status = 200): Response {
    const cors = corsHeadersFor(req);
    return new Response(JSON.stringify(body), {
      status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  function dayEnd(d: Date): Date {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);
  }

  function dayStart(d: Date): Date {
    return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);
  }

  function toYmd(d: Date): string {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
  }

  /** Same calendar logic as app `DocumentDateRange.forFilter`. */
  function windowForPreset(preset: string, now = new Date()): {
    start: Date;
    end: Date;
    prevStart: Date;
    prevEnd: Date;
  } {
    const end = dayEnd(now);
    let start: Date;
    switch (preset) {
      case "1W":
        start = dayStart(new Date(now.getFullYear(), now.getMonth(), now.getDate() - 7));
        break;
      case "3M":
        start = dayStart(new Date(now.getFullYear(), now.getMonth() - 3, now.getDate()));
        break;
      case "1M":
      default:
        start = dayStart(new Date(now.getFullYear(), now.getMonth() - 1, now.getDate()));
        break;
    }
    const lenMs = end.getTime() - start.getTime();
    const prevEnd = new Date(start.getTime() - 86400000);
    prevEnd.setHours(23, 59, 59, 999);
    const prevStart = new Date(prevEnd.getTime() - lenMs);
    prevStart.setHours(0, 0, 0, 0);
    return { start, end, prevStart, prevEnd: dayEnd(prevEnd) };
  }

  interface DocRow {
    id: string;
    amount: number | null;
    date: string | null;
    vendor_name: string | null;
    description: string | null;
    tax_amount: number | null;
    currency: string | null;
    extracted_data: unknown;
    category_id: string | null;
    status: string | null;
    type?: string | null;
    payment_method?: string | null;
    updated_at: string | null;
    created_at?: string | null;
  }

  interface LbRow {
    id: string;
    user_id: string;
    counterparty_user_id: string | null;
    type: string;
    status: string;
    amount: number | null;
    due_date: string | null;
    created_at: string;
    updated_at: string | null;
    counterparty_name: string | null;
  }

  interface InvoiceRow {
    id: string;
    status: string;
    review_required: boolean | null;
    confidence: number | null;
    cgst: number | null;
    sgst: number | null;
    igst: number | null;
    cess: number | null;
    total_tax: number | null;
    total: number | null;
    vendor_name: string | null;
    created_at: string;
    updated_at: string | null;
  }

  interface GePart {
    user_id: string;
    share_amount: number | null;
  }

  interface GroupExpenseRow {
    id: string;
    group_id: string;
    paid_by_user_id: string;
    amount: number | null;
    expense_date: string;
    group_expense_participants?: GePart[] | null;
  }

  function num(v: unknown): number {
    if (typeof v === "number" && !Number.isNaN(v)) return v;
    if (typeof v === "string") return parseFloat(v) || 0;
    return 0;
  }

  function isDraft(d: DocRow): boolean {
    return (d.status ?? "") === "draft";
  }

  function edMap(d: DocRow): Record<string, unknown> | null {
    const ed = d.extracted_data;
    if (ed && typeof ed === "object" && !Array.isArray(ed)) return ed as Record<string, unknown>;
    return null;
  }

  function isOcrDoc(d: DocRow): boolean {
    const ed = edMap(d);
    const id = ed?.invoice_id;
    return id != null && String(id).trim() !== "";
  }

  function extractionConfidence(d: DocRow): string {
    const ed = edMap(d);
    const c = ed?.extraction_confidence;
    return typeof c === "string" ? c.toLowerCase() : "medium";
  }

  function needsReviewDoc(d: DocRow): boolean {
    if (!isOcrDoc(d)) return false;
    if (extractionConfidence(d) === "low") return true;
    const ed = edMap(d);
    if (ed?.user_flagged_mismatch === true) return true;
    return false;
  }

  function categoryLabel(d: DocRow): string {
    if (d.category_id != null && String(d.category_id).length > 0) {
      const desc = (d.description ?? "").split(",").map((s) => s.trim()).filter(Boolean);
      if (desc.length > 0) return desc[0]!;
    }
    const ed = edMap(d);
    const c = ed?.category;
    if (typeof c === "string" && c.trim()) return c.trim();
    const first = (d.description ?? "").split(",").map((s) => s.trim()).filter(Boolean);
    if (first.length > 0) return first[0];
    return "Uncategorized";
  }

  function isUncategorized(d: DocRow): boolean {
    const hasCatId = d.category_id != null && String(d.category_id).trim() !== "";
    if (hasCatId) return false;
    const lab = categoryLabel(d);
    return lab === "Uncategorized" || lab === "Other";
  }

  function maxUpdatedAt(rows: { updated_at?: string | null }[]): string {
    let m = "";
    for (const r of rows) {
      const u = r.updated_at ?? "";
      if (u > m) m = u;
    }
    return m;
  }

  function fingerprintFor(docs: DocRow[]): string {
    let maxU = "";
    for (const d of docs) {
      const u = d.updated_at ?? "";
      if (u > maxU) maxU = u;
    }
    const total = docs.reduce((s, d) => s + num(d.amount), 0);
    return `${docs.length}:${maxU}:${Math.round(total * 100)}`;
  }

  /** Include lend/borrow, invoices, and group expenses so stale banner can improve later (server truth). */
  function fingerprintExtended(
    docs: DocRow[],
    lbRows: LbRow[],
    invRows: InvoiceRow[],
    geRows: GroupExpenseRow[],
  ): string {
    const docFp = fingerprintFor(docs);
    const lbSum = lbRows.reduce((s, r) => s + num(r.amount), 0);
    const invSum = invRows.reduce((s, r) => s + num(r.total), 0);
    const geSum = geRows.reduce((s, r) => s + num(r.amount), 0);
    return [
      docFp,
      `lb:${lbRows.length}:${maxUpdatedAt(lbRows)}:${Math.round(lbSum * 100)}`,
      `inv:${invRows.length}:${maxUpdatedAt(invRows)}:${Math.round(invSum * 100)}`,
      `ge:${geRows.length}:${maxUpdatedAt(geRows)}:${Math.round(geSum * 100)}`,
    ].join("|");
  }

  function viewerLbPerspective(row: LbRow, myId: string): "lent" | "borrowed" | null {
    if (row.user_id === myId) {
      return row.type === "borrowed" ? "borrowed" : "lent";
    }
    if (row.counterparty_user_id === myId) {
      return row.type === "lent" ? "borrowed" : "lent";
    }
    return null;
  }

  function findDuplicateGroups(docs: DocRow[]): { document_ids: string[]; reason: string }[] {
    const map = new Map<string, string[]>();
    for (const d of docs) {
      if (isDraft(d)) continue;
      const amt = num(d.amount);
      const date = d.date ?? "";
      const v = (d.vendor_name ?? "").toLowerCase().replace(/\s+/g, " ").trim().slice(0, 48);
      const key = `${date}|${amt.toFixed(2)}|${v}`;
      if (!map.has(key)) map.set(key, []);
      map.get(key)!.push(d.id);
    }
    const out: { document_ids: string[]; reason: string }[] = [];
    for (const ids of map.values()) {
      if (ids.length >= 2) {
        out.push({
          document_ids: ids,
          reason: "Same date, amount, and merchant name.",
        });
      }
    }
    return out;
  }

  const LEAKAGE_BUCKETS: Record<string, string[]> = {
    food_delivery: ["swiggy", "zomato", "uber eats", "doordash", "grubhub"],
    cabs: ["uber ", "uber_", "ola ", "lyft", "rapido", "bolt "],
    shopping: ["amazon", "flipkart", "myntra", "ebay", "etsy"],
    subscriptions: ["netflix", "spotify", "prime", "youtube", "apple.com", "google one", "chatgpt"],
    misc: [],
  };

  function matchesLeakage(text: string, bucket: string): boolean {
    const t = text.toLowerCase();
    const keys = LEAKAGE_BUCKETS[bucket] ?? [];
    return keys.some((k) => t.includes(k.trim()));
  }

  function discretionaryProxyLabel(d: DocRow): boolean {
    const lab = `${categoryLabel(d)} ${d.vendor_name ?? ""}`.toLowerCase();
    return (
      matchesLeakage(lab, "food_delivery") ||
      matchesLeakage(lab, "cabs") ||
      matchesLeakage(lab, "shopping") ||
      matchesLeakage(lab, "subscriptions") ||
      /entertainment|dining|restaurant|coffee|cafe|movie|game/i.test(lab)
    );
  }

  function buildDeterministic(
    docs: DocRow[],
    prevDocs: DocRow[],
    preset: string,
    rangeStart: string,
    rangeEnd: string,
    userId: string,
    dateBasis: InsightsDateBasis,
    ctx: {
      currency: string;
      lbRows: LbRow[];
      invoicesInRange: InvoiceRow[];
      groupExpensesInRange: GroupExpenseRow[];
      groupsCount: number;
      connectedAppsCount: number;
      exportsInRangeCount: number;
      profileTrustScore: number | null;
    },
  ): Json {
    const active = docs.filter((d) => !isDraft(d));
    const prevActive = prevDocs.filter((d) => !isDraft(d));

    const total = active.reduce((s, d) => s + num(d.amount), 0);
    const prevTotal = prevActive.reduce((s, d) => s + num(d.amount), 0);
    const changePct = prevTotal > 0 ? Math.round(((total - prevTotal) / prevTotal) * 100) : null;

    const rangeStartD = new Date(rangeStart + "T12:00:00");
    const rangeEndD = new Date(rangeEnd + "T12:00:00");
    const daySpan = Math.max(
      1,
      Math.round((rangeEndD.getTime() - rangeStartD.getTime()) / 86400000) + 1,
    );
    const avgDailySpend = Math.round((total / daySpan) * 100) / 100;

    const amountsSorted = active.map((d) => num(d.amount)).filter((a) => a > 0).sort((a, b) => a - b);
    const medianTransactionSize = amountsSorted.length === 0
      ? 0
      : amountsSorted.length % 2 === 1
      ? amountsSorted[(amountsSorted.length - 1) / 2]!
      : (amountsSorted[amountsSorted.length / 2 - 1]! + amountsSorted[amountsSorted.length / 2]!) / 2;

    const largest5 = [...active]
      .sort((a, b) => num(b.amount) - num(a.amount))
      .slice(0, 5)
      .map((d) => ({
        document_id: d.id,
        amount: num(d.amount),
        vendor_name: d.vendor_name ?? "Unknown",
        date: d.date,
      }));

    const merchantMap = new Map<string, { amount: number; count: number }>();
    for (const d of active) {
      const name = (d.vendor_name ?? "Unknown").trim() || "Unknown";
      const cur = merchantMap.get(name) ?? { amount: 0, count: 0 };
      cur.amount += num(d.amount);
      cur.count += 1;
      merchantMap.set(name, cur);
    }
    const topMerchants = [...merchantMap.entries()]
      .map(([name, v]) => ({ name, amount: v.amount, count: v.count }))
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 8);

    const topMerchantConcentrationPct = total > 0 && topMerchants[0]
      ? Math.round((topMerchants[0].amount / total) * 1000) / 10
      : 0;

    const recurringVendorCandidates = [...merchantMap.entries()]
      .filter(([, v]) => v.count >= 2 && v.amount > 0)
      .map(([name, v]) => ({ name, amount: v.amount, count: v.count }))
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 12);

    const catMap = new Map<string, number>();
    for (const d of active) {
      const c = categoryLabel(d);
      catMap.set(c, (catMap.get(c) ?? 0) + num(d.amount));
    }
    const topCategories = [...catMap.entries()]
      .map(([name, amount]) => ({ name, amount }))
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 8);
    const catDistribution: Record<string, number> = {};
    for (const [k, v] of catMap) catDistribution[k] = Math.round(v * 100) / 100;

    const payMap = new Map<string, number>();
    for (const d of active) {
      const pm = (d.payment_method ?? "").trim() || "unspecified";
      payMap.set(pm, (payMap.get(pm) ?? 0) + num(d.amount));
    }
    const spendByPaymentMethod: Record<string, number> = {};
    for (const [k, v] of payMap) spendByPaymentMethod[k] = Math.round(v * 100) / 100;

    let weekendSpend = 0;
    let weekdaySpend = 0;
    const byDay = new Map<string, number>();
    for (const d of active) {
      const ds = d.date;
      if (!ds) continue;
      const amt = num(d.amount);
      byDay.set(ds, (byDay.get(ds) ?? 0) + amt);
      const wd = new Date(ds + "T12:00:00").getDay();
      if (wd === 0 || wd === 6) weekendSpend += amt;
      else weekdaySpend += amt;
    }
    const dailyVals = [...byDay.values()];
    const meanDaily = dailyVals.length ? dailyVals.reduce((a, b) => a + b, 0) / dailyVals.length : 0;
    let varDaily = 0;
    for (const v of dailyVals) varDaily += (v - meanDaily) ** 2;
    varDaily = dailyVals.length ? varDaily / dailyVals.length : 0;
    const stdDaily = Math.sqrt(varDaily);
    const spendVolatilityScore = meanDaily > 0 && stdDaily > 0
      ? Math.min(100, Math.round((stdDaily / meanDaily) * 45))
      : 0;

    const spikeDays = new Set<string>();
    for (const [day, val] of byDay) {
      if (meanDaily > 0 && stdDaily > 0 && val > meanDaily + 1.5 * stdDaily) spikeDays.add(day);
    }
    let borrowAfterSpendSpike = false;
    for (const lb of ctx.lbRows) {
      if (viewerLbPerspective(lb, userId) !== "borrowed") continue;
      const t = new Date(lb.created_at).getTime();
      for (const spikeDay of spikeDays) {
        const spikeEnd = new Date(spikeDay + "T23:59:59Z").getTime();
        if (t >= spikeEnd && t <= spikeEnd + 2 * 86400000) {
          borrowAfterSpendSpike = true;
          break;
        }
      }
      if (borrowAfterSpendSpike) break;
    }

    const leakage: Record<string, number> = {
      food_delivery: 0,
      cabs: 0,
      shopping: 0,
      subscriptions: 0,
      misc: 0,
    };
    let discretionarySpend = 0;
    let essentialishSpend = 0;
    for (const d of active) {
      const amt = num(d.amount);
      const blob = `${categoryLabel(d)} ${d.vendor_name ?? ""}`.toLowerCase();
      let hit = false;
      for (const b of Object.keys(leakage)) {
        if (b === "misc") continue;
        if (matchesLeakage(blob, b)) {
          leakage[b] += amt;
          hit = true;
          break;
        }
      }
      if (!hit && discretionaryProxyLabel(d)) {
        leakage.misc += amt;
        discretionarySpend += amt;
      } else if (hit) discretionarySpend += amt;
      else essentialishSpend += amt;
    }

    let taxTotal = 0;
    let docsWithTax = 0;
    for (const d of active) {
      const t = num(d.tax_amount);
      if (t > 0) {
        taxTotal += t;
        docsWithTax += 1;
      }
    }

    const uncategorized = active.filter(isUncategorized);
    const lowConf = active.filter((d) => isOcrDoc(d) && extractionConfidence(d) === "low");
    const reviewQueue = active.filter(needsReviewDoc);
    const ocrDocs = active.filter(isOcrDoc);
    const reviewedInvoices = ocrDocs.filter((d) => !needsReviewDoc(d));
    const reviewedVsUnreviewedRatio = ocrDocs.length
      ? Math.round((reviewedInvoices.length / ocrDocs.length) * 1000) / 1000
      : null;
    const highConf = ocrDocs.filter((d) => extractionConfidence(d) === "high");
    const lowConfOcr = ocrDocs.filter((d) => extractionConfidence(d) === "low");
    const highVsLowOcrRatio = lowConfOcr.length > 0
      ? Math.round((highConf.length / lowConfOcr.length) * 100) / 100
      : highConf.length > 0 ? null : null;

    const invoiceCount = active.filter((d) => (d.type ?? "") === "invoice").length;
    const receiptCount = active.filter((d) => (d.type ?? "") === "receipt").length;

    const dups = findDuplicateGroups(active);

    const todayYmd = toYmd(new Date());
    let lentPending = 0;
    let borrowedPending = 0;
    let lentSettled = 0;
    let borrowedSettled = 0;
    let overdueLent = 0;
    let overdueBorrowed = 0;
    const cpTotals = new Map<string, number>();
    let pendingCount = 0;
    let settledCount = 0;

    for (const row of ctx.lbRows) {
      const pv = viewerLbPerspective(row, userId);
      if (!pv) continue;
      const amt = num(row.amount);
      const st = (row.status ?? "").toLowerCase();
      const pend = st === "pending";
      const due = row.due_date;
      const overdue = pend && due != null && due < todayYmd;
      const cp = (row.counterparty_name ?? "Unknown").trim() || "Unknown";

      if (pend) {
        pendingCount += 1;
        if (pv === "lent") {
          lentPending += amt;
          if (overdue) overdueLent += 1;
        } else {
          borrowedPending += amt;
          if (overdue) overdueBorrowed += 1;
        }
        cpTotals.set(cp, (cpTotals.get(cp) ?? 0) + amt);
      } else {
        settledCount += 1;
        if (pv === "lent") lentSettled += amt;
        else borrowedSettled += amt;
      }
    }

    const pendingAmt = lentPending + borrowedPending;
    const settledAmt = lentSettled + borrowedSettled;
    const pendingToSettledRatio = settledAmt > 0 ? Math.round((pendingAmt / settledAmt) * 1000) / 1000 : null;
    const topCounterparties = [...cpTotals.entries()]
      .map(([name, amount]) => ({ name, amount }))
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 8);

    const overdueCount = overdueLent + overdueBorrowed;
    const settlementAvoidanceScore = pendingCount > 0
      ? Math.min(100, Math.round((overdueCount / pendingCount) * 100))
      : 0;
    const recoveryEfficiencyScore = pendingAmt + settledAmt > 0
      ? Math.round((settledAmt / (pendingAmt + settledAmt)) * 100)
      : 100;

    const debtStressScore = Math.min(
      100,
      Math.round(
        (borrowedPending > 0 ? Math.min(50, borrowedPending / Math.max(total, 1) * 20) : 0) +
          overdueBorrowed * 12,
      ),
    );

    let cgstT = 0;
    let sgstT = 0;
    let igstT = 0;
    let cessT = 0;
    let invSuccess = 0;
    let invFail = 0;
    let confSum = 0;
    let confN = 0;
    let reviewReq = 0;
    const failedVendors = new Map<string, number>();

    for (const inv of ctx.invoicesInRange) {
      cgstT += num(inv.cgst);
      sgstT += num(inv.sgst);
      igstT += num(inv.igst);
      cessT += num(inv.cess);
      const st = (inv.status ?? "").toLowerCase();
      if (st === "failed") {
        invFail += 1;
        const v = (inv.vendor_name ?? "unknown").trim() || "unknown";
        failedVendors.set(v, (failedVendors.get(v) ?? 0) + 1);
      } else if (["completed", "reviewed", "confirmed"].includes(st)) {
        invSuccess += 1;
      }
      if (inv.review_required === true) reviewReq += 1;
      if (inv.confidence != null && !Number.isNaN(inv.confidence)) {
        confSum += num(inv.confidence);
        confN += 1;
      }
    }
    const invTotal = invSuccess + invFail;
    const ocrSuccessRate = invTotal > 0 ? Math.round((invSuccess / invTotal) * 1000) / 1000 : null;
    const ocrFailureRate = invTotal > 0 ? Math.round((invFail / invTotal) * 1000) / 1000 : null;
    const avgInvoiceConfidence = confN > 0 ? Math.round((confSum / confN) * 10000) / 10000 : null;
    const reviewRequiredRate = ctx.invoicesInRange.length > 0
      ? Math.round((reviewReq / ctx.invoicesInRange.length) * 1000) / 1000
      : null;
    const repeatedFailureVendors = [...failedVendors.entries()]
      .filter(([, c]) => c >= 2)
      .map(([name, count]) => ({ name, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 6);

    let totalGroupSpend = 0;
    let userPaidForOthers = 0;
    let userShareOwed = 0;
    let payerExpenses = 0;
    let participantOnlyExpenses = 0;

    for (const ge of ctx.groupExpensesInRange) {
      const gAmt = num(ge.amount);
      totalGroupSpend += gAmt;
      const parts = ge.group_expense_participants ?? [];
      const myShare = num(parts.find((p) => p.user_id === userId)?.share_amount);
      userShareOwed += myShare;
      if (ge.paid_by_user_id === userId) {
        payerExpenses += 1;
        const othersOwed = parts
          .filter((p) => p.user_id !== userId)
          .reduce((s, p) => s + num(p.share_amount), 0);
        userPaidForOthers += Math.min(gAmt, othersOwed);
      } else if (parts.some((p) => p.user_id === userId)) {
        participantOnlyExpenses += 1;
      }
    }

    const socialSpendingRatio = total > 0 ? Math.round((totalGroupSpend / (total + totalGroupSpend)) * 1000) / 1000 : null;
    const groupImbalanceScore = totalGroupSpend > 0
      ? Math.min(100, Math.round((Math.abs(userPaidForOthers - userShareOwed) / totalGroupSpend) * 100))
      : 0;
    const generosityOverextensionScore = totalGroupSpend > 0
      ? Math.min(100, Math.round(((userPaidForOthers - userShareOwed) / totalGroupSpend) * 80))
      : 0;

    const userUsuallyPayer = payerExpenses >= participantOnlyExpenses;

    const lowConfRate = ocrDocs.length ? lowConf.length / ocrDocs.length : 0;
    const reviewDocRate = active.length ? reviewQueue.length / active.length : 0;
    const uncRate = active.length ? uncategorized.length / active.length : 0;
    const dataReliabilityScore = Math.max(
      0,
      Math.min(
        100,
        Math.round(100 - lowConfRate * 40 - reviewDocRate * 25 - uncRate * 20),
      ),
    );
    const cleanupDisciplineScore = Math.max(
      0,
      Math.min(100, Math.round(100 - uncRate * 35 - reviewDocRate * 35)),
    );
    const financialFrictionScore = Math.min(
      100,
      Math.round(reviewDocRate * 45 + uncRate * 35 + (1 - (reviewedVsUnreviewedRatio ?? 0.5)) * 20),
    );
    const merchantDependencyScore = Math.round(topMerchantConcentrationPct);
    const categoryDriftScore = topCategories.length >= 2
      ? Math.min(100, Math.round((topCategories[0]!.amount / Math.max(total, 1)) * 100))
      : 0;
    const impulsePurchaseProxy = total > 0 ? Math.min(100, Math.round((weekendSpend / total) * 120)) : 0;

    const exportFreqScore = Math.min(100, ctx.exportsInRangeCount * 20);
    const stackMaturity = Math.min(5, ctx.connectedAppsCount + (ctx.exportsInRangeCount > 0 ? 1 : 0));

    const fingerprint = `${dateBasis}|${
      fingerprintExtended(active, ctx.lbRows, ctx.invoicesInRange, ctx.groupExpensesInRange)
    }`;

    const overview = {
      range: preset,
      range_start: rangeStart,
      range_end: rangeEnd,
      currency: ctx.currency,
      total_spend: Math.round(total * 100) / 100,
      avg_daily_spend: avgDailySpend,
      median_transaction_size: Math.round(medianTransactionSize * 100) / 100,
      spend_change_vs_prev_pct: changePct,
      month_over_month_spend_change_pct: preset === "1M" ? changePct : null,
    };

    const categories = {
      top: topCategories,
      distribution: catDistribution,
      discretionary_vs_essential_proxy: {
        discretionary_spend: Math.round(discretionarySpend * 100) / 100,
        other_spend: Math.round(essentialishSpend * 100) / 100,
      },
    };

    const vendors = {
      top: topMerchants,
      recurring_candidates: recurringVendorCandidates,
      concentration_percent: topMerchantConcentrationPct,
    };

    const debt = {
      lent_pending: Math.round(lentPending * 100) / 100,
      borrowed_pending: Math.round(borrowedPending * 100) / 100,
      lent_settled: Math.round(lentSettled * 100) / 100,
      borrowed_settled: Math.round(borrowedSettled * 100) / 100,
      overdue_lent_count: overdueLent,
      overdue_borrowed_count: overdueBorrowed,
      top_counterparties_by_amount_pending: topCounterparties,
      pending_to_settled_ratio: pendingToSettledRatio,
      debt_stress_score: debtStressScore,
      recovery_efficiency_score: recoveryEfficiencyScore,
    };

    const groups = {
      groups_count: ctx.groupsCount,
      active_groups_count: ctx.groupsCount,
      total_group_spend: Math.round(totalGroupSpend * 100) / 100,
      total_paid_by_user_in_groups: Math.round(userPaidForOthers * 100) / 100,
      total_share_owed_by_user: Math.round(userShareOwed * 100) / 100,
      user_usually_payer: userUsuallyPayer,
      group_imbalance_score: groupImbalanceScore,
      settlement_lag_days_avg: null as number | null,
      settlement_compliance_score: null as number | null,
      social_spending_ratio: socialSpendingRatio,
    };

    const documentsBlock = {
      invoice_count: invoiceCount,
      receipt_count: receiptCount,
      document_count: active.length,
      tax_paid_total: Math.round(taxTotal * 100) / 100,
      cgst_total: Math.round(cgstT * 100) / 100,
      sgst_total: Math.round(sgstT * 100) / 100,
      igst_total: Math.round(igstT * 100) / 100,
      cess_total: Math.round(cessT * 100) / 100,
      weekend_vs_weekday_spend: {
        weekend: Math.round(weekendSpend * 100) / 100,
        weekday: Math.round(weekdaySpend * 100) / 100,
      },
      cash_leakage_buckets: Object.fromEntries(
        Object.entries(leakage).map(([k, v]) => [k, Math.round(v * 100) / 100]),
      ),
      largest_5_transactions: largest5,
      reviewed_vs_unreviewed_invoice_ratio: reviewedVsUnreviewedRatio,
      high_confidence_vs_low_confidence_ocr_ratio: highVsLowOcrRatio,
    };

    const pipeline = {
      invoices_in_range_count: ctx.invoicesInRange.length,
      ocr_success_rate: ocrSuccessRate,
      ocr_failure_rate: ocrFailureRate,
      avg_confidence: avgInvoiceConfidence,
      review_required_rate: reviewRequiredRate,
      repeated_failure_vendors: repeatedFailureVendors,
    };

    const engagement = {
      connected_apps_count: ctx.connectedAppsCount,
      finance_stack_maturity_0_5: stackMaturity,
      export_frequency_score_0_100: exportFreqScore,
      trust_score: ctx.profileTrustScore,
      reporting_engagement_score: Math.min(100, exportFreqScore + (reviewedVsUnreviewedRatio ?? 0) * 30),
    };

    const behavior_features = {
      spend_volatility_score: spendVolatilityScore,
      end_of_month_stress_score: null as number | null,
      borrow_after_spend_spike: borrowAfterSpendSpike,
      settlement_avoidance_score: settlementAvoidanceScore,
      generosity_overextension_score: Math.max(0, generosityOverextensionScore),
      category_drift_score: categoryDriftScore,
      merchant_dependency_score: merchantDependencyScore,
      expense_fragmentation_score: Math.min(100, active.length > 15 ? Math.round(active.length / 2) : 0),
      impulse_purchase_proxy: impulsePurchaseProxy,
      cleanup_discipline_score: cleanupDisciplineScore,
      data_reliability_score: dataReliabilityScore,
      social_finance_dependency_score: socialSpendingRatio != null
        ? Math.min(100, Math.round(socialSpendingRatio * 100))
        : 0,
      financial_friction_score: financialFrictionScore,
    };

    const missingness_flags: string[] = [];
    if (ctx.invoicesInRange.length === 0) missingness_flags.push("no_invoices_in_pipeline_window");
    if (ctx.groupExpensesInRange.length === 0) missingness_flags.push("no_group_expenses_in_range");
    if (ocrDocs.length === 0) missingness_flags.push("few_linked_ocr_documents");

    const quality = {
      data_reliability_score: dataReliabilityScore,
      missingness_flags,
    };

    return {
      period: { preset, start: rangeStart, end: rangeEnd, date_basis: dateBasis },
      fingerprint,
      summary: {
        total_spend: overview.total_spend,
        document_count: active.length,
        previous_period_total: Math.round(prevTotal * 100) / 100,
        change_vs_previous_pct: changePct,
      },
      top_merchants: topMerchants,
      top_categories: topCategories,
      tax_summary: {
        total_tax: Math.round(taxTotal * 100) / 100,
        documents_with_tax: docsWithTax,
      },
      needs_attention: {
        uncategorized_count: uncategorized.length,
        uncategorized_document_ids: uncategorized.map((d) => d.id),
        low_confidence_ocr_count: lowConf.length,
        low_confidence_document_ids: lowConf.map((d) => d.id),
        review_recommended_count: reviewQueue.length,
        review_recommended_document_ids: reviewQueue.map((d) => d.id),
        duplicate_groups: dups,
      },
      spend_by_payment_method: spendByPaymentMethod,
      overview,
      categories,
      vendors,
      debt,
      groups,
      documents: documentsBlock,
      invoice_pipeline: pipeline,
      behavior_features,
      engagement,
      quality,
    };
  }

  async function callGeminiJson(apiKey: string, prompt: string, maxTokens: number): Promise<Json | null> {
    const url =
      `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${encodeURIComponent(apiKey)}`;

    const controller = new AbortController();
    const tid = setTimeout(() => controller.abort(), 60_000);
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: maxTokens },
      }),
    }).finally(() => clearTimeout(tid));

    const json = (await res.json()) as Record<string, unknown>;
    if (!res.ok) {
      console.error("analytics-insights Gemini", res.status, JSON.stringify(json).slice(0, 400));
      return null;
    }
    const text = (json as { candidates?: { content?: { parts?: { text?: string }[] } }[] })
      .candidates?.[0]?.content?.parts?.[0]?.text;
    if (!text || typeof text !== "string") return null;

    let s = text.trim();
    if (s.startsWith("```")) {
      s = s.replace(/^```\w*\n?/, "").replace(/\n?```$/, "");
    }
    if (!s.startsWith("{")) {
      const m = s.match(/\{[\s\S]*\}/);
      if (m) s = m[0];
    }
    try {
      return JSON.parse(s) as Json;
    } catch {
      return null;
    }
  }

  function callGeminiMoneyCoach(apiKey: string, det: Json): Promise<Json | null> {
    const prompt =
      `You are the Money Management Coach for a personal receipt and split-expense app. You ONLY use the JSON below (precomputed aggregates). Do not invent amounts, merchants, or investment advice. Do not recommend specific stocks, funds, or asset allocation. Focus on spending control, categories, debt/settlement hygiene, group expenses, bills, and practical savings habits.

  Rules:
  - Output ONLY valid JSON, no markdown.
  - Tone: calm, direct, actionable.
  - short_narrative: max 2 sentences.
  - prioritized_insights: 0–5 items; type one of: duplicate|category|tax|trend|review|debt|groups|other
  - actions_this_week: 0–3 short imperative strings (concrete, tied to data).

  Input:
  ${JSON.stringify(det)}

  Return:
  {"short_narrative":"","prioritized_insights":[{"type":"","text":"","document_ids":[]}],"actions_this_week":[]}`;

    return callGeminiJson(apiKey, prompt, 1200);
  }

  function callGeminiJaiInsight(apiKey: string, det: Json): Promise<Json | null> {
    const prompt =
      `You are JAI Insight — a behavioral finance analyst. You ONLY use the JSON below. Infer patterns, habits, friction, and risk signals. Do not invent numbers. Do not give investment or tax advice. Use behavior_features, debt, groups, documents, and quality sections heavily.

  Rules:
  - Output ONLY valid JSON, no markdown.
  - Tone: observant, non-judgmental, precise.
  - short_narrative: max 2 sentences (why patterns show up).
  - patterns: 0–5 objects with label + text (one line each).
  - risks: 0–3 short strings (behavioral or data-quality risks only).
  - follow_up_questions: 0–2 optional strings the user could reflect on.

  Input:
  ${JSON.stringify(det)}

  Return:
  {"short_narrative":"","patterns":[{"label":"","text":""}],"risks":[],"follow_up_questions":[]}`;

    return callGeminiJson(apiKey, prompt, 1200);
  }

  async function callGeminiDocumentReview(apiKey: string, docSummary: Json): Promise<Json | null> {
    const prompt =
      `You review one saved receipt/invoice record. Use ONLY the JSON below. Output ONLY valid JSON, no markdown.

  {"review_summary":"1-2 sentences","checks":[{"label":"short","ok":true,"detail":"optional"}],"suggested_actions":["optional short bullets"]}

  Input:
  ${JSON.stringify(docSummary)}`;

    return callGeminiJson(apiKey, prompt, 512);
  }

  function mergeAiLayer(
    coach: Json | null,
    jai: Json | null,
  ): Json {
    const coachInsights = coach?.prioritized_insights;
    const legacyInsights = Array.isArray(coachInsights) ? coachInsights : [];
    const coachN = typeof coach?.short_narrative === "string" ? coach.short_narrative.trim() : "";

    return {
      money_coach: coach,
      jai_insight: jai,
      // Legacy single-field consumers: Money Coach only (JAI lives under jai_insight).
      short_narrative: coachN,
      prioritized_insights: legacyInsights,
    };
  }

  type AiAgentsMode = "both" | "money_coach" | "jai_insight";

  function parseAiAgents(body: Json): AiAgentsMode {
    const raw = body.ai_agents ?? body.agent;
    if (raw === "money_coach" || raw === "jai_insight") return raw;
    return "both";
  }

  type InsightsDateBasis = "bill_date" | "upload_window";

  function parseDateBasis(body: Json): InsightsDateBasis {
    const v = body.date_basis ?? body.insights_date_basis;
    if (v === "upload_window" || v === "uploaded_in_range") return "upload_window";
    return "bill_date";
  }

  function parseGeminiScope(body: Json, profileGoat: boolean): GeminiKeyScope {
    const raw = body.gemini_scope;
    if (raw === "goat" && profileGoat) return "goat";
    if (raw === "goat" && !profileGoat) {
      console.warn("analytics-insights: gemini_scope=goat ignored (profiles.goat is not true)");
    }
    return "default";
  }

  async function runRangeAi(
    apiKey: string,
    det: Json,
    mode: AiAgentsMode,
  ): Promise<{ layer: Json | null; gemini_used: boolean }> {
    if (mode === "money_coach") {
      const coach = await callGeminiMoneyCoach(apiKey, det);
      return { layer: mergeAiLayer(coach, null), gemini_used: coach != null };
    }
    if (mode === "jai_insight") {
      const jai = await callGeminiJaiInsight(apiKey, det);
      return { layer: mergeAiLayer(null, jai), gemini_used: jai != null };
    }
    const [coach, jai] = await Promise.all([
      callGeminiMoneyCoach(apiKey, det),
      callGeminiJaiInsight(apiKey, det),
    ]);
    return { layer: mergeAiLayer(coach, jai), gemini_used: coach != null || jai != null };
  }

  serve(async (req) => {
    const cors = corsHeadersFor(req);
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: cors });
    }
    if (req.method !== "POST") {
      return jsonResponse(
        { success: false, error: { code: "METHOD_NOT_ALLOWED", message: "POST only" } },
        req,
        405,
      );
    }

    const contentLength = parseInt(req.headers.get("content-length") ?? "0", 10);
    if (contentLength > 1_048_576) {
      return jsonResponse(
        {
          success: false,
          error: { code: "PAYLOAD_TOO_LARGE", message: "Request body too large (max 1 MB)" },
        },
        req,
        413,
      );
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse(
        { success: false, error: { code: "UNAUTHORIZED", message: "Missing authorization" } },
        req,
        401,
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnon = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabase: SupabaseClient = createClient(supabaseUrl, supabaseAnon, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authErr } = await supabase.auth.getUser();
    if (authErr || !user) {
      return jsonResponse(
        { success: false, error: { code: "UNAUTHORIZED", message: "Invalid session" } },
        req,
        401,
      );
    }

    let body: Json;
    try {
      body = (await req.json()) as Json;
    } catch {
      return jsonResponse(
        { success: false, error: { code: "INVALID_INPUT", message: "Invalid JSON body" } },
        req,
        400,
      );
    }

    const documentId = typeof body.document_id === "string" ? body.document_id : null;
    const includeAi = body.include_ai === true;
    const aiAgents = parseAiAgents(body);

    let profileGoatForGemini = false;
    if (includeAi) {
      const { data: gProf } = await supabase.from("profiles").select("goat").eq("id", user.id).maybeSingle();
      profileGoatForGemini = gProf?.goat === true;
    }
    const effectiveGeminiScope = parseGeminiScope(body, profileGoatForGemini);

    if (documentId) {
      const { data: doc, error: docErr } = await supabase
        .from("documents")
        .select(
          "id,amount,date,vendor_name,description,tax_amount,currency,extracted_data,category_id,status,type,payment_method,updated_at",
        )
        .eq("id", documentId)
        .eq("user_id", user.id)
        .maybeSingle();

      if (docErr || !doc) {
        return jsonResponse(
          { success: false, error: { code: "NOT_FOUND", message: "Document not found" } },
          req,
          404,
        );
      }

      const row = doc as unknown as DocRow;
      const det: Json = {
        mode: "document",
        document: {
          id: row.id,
          vendor_name: row.vendor_name,
          amount: num(row.amount),
          date: row.date,
          tax_amount: num(row.tax_amount),
          currency: row.currency,
          category_label: categoryLabel(row),
          is_ocr: isOcrDoc(row),
          extraction_confidence: extractionConfidence(row),
          needs_review: needsReviewDoc(row),
        },
      };

      let ai_layer: Json | null = null;
      let gemini_used = false;
      if (includeAi) {
        const keyInfo = await resolveGeminiKeyForScope(effectiveGeminiScope);
        if (keyInfo) {
          console.log(
            `analytics-insights: user=${user.id} mode=document gemini_scope=${effectiveGeminiScope} key_source=${keyInfo.source}`,
          );
          ai_layer = await callGeminiDocumentReview(keyInfo.key, det);
          gemini_used = ai_layer != null;
        }
      }

      return jsonResponse({
        success: true,
        mode: "document",
        deterministic: det,
        ai_layer,
        generated_at: new Date().toISOString(),
        data_fingerprint: fingerprintFor([row]),
        gemini_used,
      }, req);
    }

    const rangePreset = typeof body.range_preset === "string" ? body.range_preset : null;
    if (!rangePreset || !["1W", "1M", "3M"].includes(rangePreset)) {
      return jsonResponse(
        {
          success: false,
          error: { code: "INVALID_INPUT", message: "range_preset must be 1W, 1M, or 3M" },
        },
        req,
        400,
      );
    }

    const dateBasis = parseDateBasis(body);
    const { start, end, prevStart, prevEnd } = windowForPreset(rangePreset);
    const startStr = toYmd(start);
    const endStr = toYmd(end);
    const pStartStr = toYmd(prevStart);
    const pEndStr = toYmd(prevEnd);
    const startIso = start.toISOString();
    const endIso = end.toISOString();
    const prevStartIso = prevStart.toISOString();
    const prevEndIso = prevEnd.toISOString();

    const docSelect =
      "id,amount,date,vendor_name,description,tax_amount,currency,extracted_data,category_id,status,type,payment_method,updated_at,created_at";

    const docsQuery = dateBasis === "upload_window"
      ? supabase.from("documents").select(docSelect).eq("user_id", user.id).gte("created_at", startIso).lte(
        "created_at",
        endIso,
      )
      : supabase.from("documents").select(docSelect).eq("user_id", user.id).gte("date", startStr).lte(
        "date",
        endStr,
      );

    const prevDocsQuery = dateBasis === "upload_window"
      ? supabase.from("documents").select(docSelect).eq("user_id", user.id).gte("created_at", prevStartIso).lte(
        "created_at",
        prevEndIso,
      )
      : supabase.from("documents").select(docSelect).eq("user_id", user.id).gte("date", pStartStr).lte(
        "date",
        pEndStr,
      );

    const [
      docsRes,
      prevRes,
      lbRes,
      invRes,
      geRes,
      profileRes,
      appsRes,
      exportsRes,
      egmRes,
    ] = await Promise.all([
      docsQuery,
      prevDocsQuery,
      supabase.from("lend_borrow_entries").select(
        "id,user_id,counterparty_user_id,type,status,amount,due_date,created_at,updated_at,counterparty_name",
      ),
      supabase.from("invoices").select(
        "id,status,review_required,confidence,cgst,sgst,igst,cess,total_tax,total,vendor_name,created_at,updated_at",
      ).eq("user_id", user.id).gte("created_at", startIso).lte("created_at", endIso),
      supabase.from("group_expenses").select(
        "id,group_id,paid_by_user_id,amount,expense_date,updated_at,group_expense_participants(user_id,share_amount)",
      ).gte("expense_date", startStr).lte("expense_date", endStr),
      supabase.from("profiles").select("preferred_currency,trust_score").eq("id", user.id).maybeSingle(),
      supabase.from("connected_apps").select("id", { count: "exact", head: true }).eq("user_id", user.id).eq(
        "status",
        "connected",
      ),
      supabase.from("export_history").select("id", { count: "exact", head: true }).eq("user_id", user.id).gte(
        "created_at",
        startIso,
      ).lte("created_at", endIso),
      supabase.from("expense_group_members").select("group_id").eq("user_id", user.id),
    ]);

    if (docsRes.error) {
      console.error("analytics-insights query", docsRes.error.message);
      return jsonResponse(
        { success: false, error: { code: "QUERY_ERROR", message: docsRes.error.message } },
        req,
        500,
      );
    }

    if (lbRes.error) console.error("analytics-insights lend_borrow", lbRes.error.message);
    if (invRes.error) console.error("analytics-insights invoices", invRes.error.message);
    if (geRes.error) console.error("analytics-insights group_expenses", geRes.error.message);

    const docs = (docsRes.data ?? []) as unknown as DocRow[];
    const prevDocs = (prevRes.data ?? []) as unknown as DocRow[];
    const lbRows = (lbRes.error ? [] : lbRes.data ?? []) as unknown as LbRow[];
    const invoicesInRange = (invRes.error ? [] : invRes.data ?? []) as unknown as InvoiceRow[];
    const groupExpensesInRange = (geRes.error ? [] : geRes.data ?? []) as unknown as GroupExpenseRow[];

    const egmRows = egmRes.data as { group_id: string }[] | null;
    const groupIds = new Set((egmRows ?? []).map((r) => r.group_id));
    const currency = (profileRes.data?.preferred_currency as string | null)?.trim() || "INR";
    const trustRaw = profileRes.data?.trust_score;
    const profileTrustScore = trustRaw != null ? num(trustRaw) : null;

    const deterministic = buildDeterministic(
      docs,
      prevDocs,
      rangePreset,
      startStr,
      endStr,
      user.id,
      dateBasis,
      {
        currency,
        lbRows,
        invoicesInRange,
        groupExpensesInRange,
        groupsCount: groupIds.size,
        connectedAppsCount: appsRes.count ?? 0,
        exportsInRangeCount: exportsRes.count ?? 0,
        profileTrustScore,
      },
    );

    const fp = deterministic.fingerprint as string;

    let ai_layer: Json | null = null;
    let gemini_used = false;
    if (includeAi) {
      const keyInfo = await resolveGeminiKeyForScope(effectiveGeminiScope);
      if (keyInfo) {
        console.log(
          `analytics-insights: user=${user.id} mode=range gemini_scope=${effectiveGeminiScope} key_source=${keyInfo.source}`,
        );
        const run = await runRangeAi(keyInfo.key, deterministic, aiAgents);
        ai_layer = run.layer;
        gemini_used = run.gemini_used;

        // Single-agent refreshes merge with the existing snapshot so coach ↔ jai stay paired
        // when the client calls the Edge Function twice (Money Coach, then JAI).
        if (
          ai_layer != null &&
          (aiAgents === "money_coach" || aiAgents === "jai_insight")
        ) {
          const { data: existing } = await supabase
            .from("analytics_insight_snapshots")
            .select("ai_layer")
            .eq("user_id", user.id)
            .eq("range_preset", rangePreset)
            .maybeSingle();
          const prev = existing?.ai_layer as Json | undefined;
          if (prev && typeof prev === "object" && !Array.isArray(prev)) {
            const prevCoach = prev["money_coach"] as Json | null | undefined;
            const prevJai = prev["jai_insight"] as Json | null | undefined;
            const cur = ai_layer as Json;
            const newCoach = cur["money_coach"] as Json | null | undefined;
            const newJai = cur["jai_insight"] as Json | null | undefined;
            if (aiAgents === "money_coach") {
              ai_layer = mergeAiLayer(
                (newCoach ?? null) as Json | null,
                (prevJai ?? null) as Json | null,
              );
            } else {
              ai_layer = mergeAiLayer(
                (prevCoach ?? null) as Json | null,
                (newJai ?? null) as Json | null,
              );
            }
          }
        }
      }
    }

    const generatedAt = new Date().toISOString();

    const { error: upErr } = await supabase.from("analytics_insight_snapshots").upsert(
      {
        user_id: user.id,
        range_preset: rangePreset,
        range_start: startStr,
        range_end: endStr,
        data_fingerprint: fp,
        deterministic,
        ai_layer: includeAi ? ai_layer : null,
        generated_at: generatedAt,
      },
      { onConflict: "user_id,range_preset" },
    );

    if (upErr) {
      console.error("analytics-insights upsert", upErr.message);
    }

    return jsonResponse({
      success: true,
      mode: "range",
      deterministic,
      ai_layer,
      generated_at: generatedAt,
      data_fingerprint: fp,
      gemini_used,
      ai_agents: aiAgents,
    }, req);
  });
