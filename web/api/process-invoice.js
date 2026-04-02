const SUPABASE_FUNCTIONS_URL =
  "https://wpzopkigbbldcfpxuvcm.supabase.co/functions/v1";

module.exports = async (req, res) => {
  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }

  if (req.method !== "POST") {
    return res.status(405).json({ success: false, error: "Method not allowed" });
  }

  const target = `${SUPABASE_FUNCTIONS_URL}/process-invoice`;

  const headers = { "Content-Type": "application/json" };
  if (req.headers.authorization) headers["Authorization"] = req.headers.authorization;
  if (req.headers["apikey"]) headers["apikey"] = req.headers["apikey"];

  try {
    const upstream = await fetch(target, {
      method: "POST",
      headers,
      body: JSON.stringify(req.body),
    });

    const ct = upstream.headers.get("content-type") || "";
    if (ct.includes("application/json")) {
      const data = await upstream.json();
      return res.status(upstream.status).json(data);
    }
    const text = await upstream.text();
    return res.status(upstream.status).send(text);
  } catch (err) {
    console.error("process-invoice proxy error:", err);
    return res.status(502).json({
      success: false,
      error: { code: "PROXY_ERROR", message: `Proxy failed: ${err.message}` },
    });
  }
};
