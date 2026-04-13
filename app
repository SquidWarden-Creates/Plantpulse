import { useState, useEffect, useRef } from "react";

const CATEGORIES = [
  { id: "shrubs", label: "Shrubs & Trees", icon: "🌳", note: "Highest ROI" },
  { id: "annuals", label: "Annuals", icon: "🌸", note: "High Velocity" },
  { id: "perennials", label: "Perennials", icon: "🌿", note: "Repeat Buyers" },
  { id: "natives", label: "Native Plants", icon: "🦋", note: "Growing Demand" },
];

const SEASON = (() => {
  const m = new Date().getMonth();
  if (m >= 2 && m <= 4) return "spring";
  if (m >= 5 && m <= 7) return "summer";
  if (m >= 8 && m <= 10) return "fall";
  return "winter";
})();

// Map pytrends slope to display signal
const slopeToSignal = (slope, score) => {
  if (slope === "rising") return "rising";
  if (slope === "climbing") return "rising";
  if (slope === "falling" || slope === "declining") return "falling";
  if (score >= 60) return "peaking";
  if (score >= 30) return "stable";
  return "emerging";
};

export default function PlantPulse() {
  const [zipInput, setZipInput] = useState("56001");
  const [zip, setZip] = useState("");
  const [zipError, setZipError] = useState("");
  const [zoneData, setZoneData] = useState(null);
  const [category, setCategory] = useState(CATEGORIES[0]);
  const [loading, setLoading] = useState(false);
  const [loadingStage, setLoadingStage] = useState("");
  const [results, setResults] = useState(null);
  const [error, setError] = useState(null);
  const [dots, setDots] = useState("");
  const intervalRef = useRef(null);

  useEffect(() => {
    if (loading) {
      intervalRef.current = setInterval(() => {
        setDots(d => d.length >= 3 ? "" : d + ".");
      }, 400);
    } else {
      clearInterval(intervalRef.current);
      setDots("");
    }
    return () => clearInterval(intervalRef.current);
  }, [loading]);

  const validateZip = (val) => /^\d{5}$/.test(val);

  const fetchZone = async (zipCode) => {
    const res = await fetch(`/api/zone?zip=${zipCode}`);
    const data = await res.json();
    if (!data.success) throw new Error("Zone lookup failed");
    return data;
  };

  const fetchTrends = async (state, cat) => {
    const res = await fetch(`/api/trends?category=${cat}&state=${state}`);
    const data = await res.json();
    return data;
  };

  const fetchClaudeInterpretation = async (trendData, zoneInfo, catLabel) => {
    const topPlants = trendData.plants
      .slice(0, 15)
      .map(p => ({
        name: p.commonName,
        botanical: p.botanicalName,
        score: p.trendScore,
        slope: p.slope,
      }));

    const prompt = `You are a plant market intelligence analyst for independent garden centers.

Real Google Trends data has been fetched for the region:
- State: ${zoneInfo.state}
- Hardiness Zone: ${zoneInfo.zone} (range: ${zoneInfo.zone_range})
- Category: ${catLabel}
- Season: ${SEASON}

Here is the actual trend data from Google Trends (90-day window, filtered to ${zoneInfo.state}):
${JSON.stringify(topPlants, null, 2)}

Slope values: "rising" or "climbing" = upward momentum, "stable" = flat, "falling" or "declining" = losing interest, "insufficient_data" or "no_data" = not enough regional data.

Your job is to interpret this real data for a garden center buyer. Apply your knowledge of:
- What performs in Zone ${zoneInfo.zone} specifically
- Seasonal timing (it is currently ${SEASON})
- Whether a trend reflects genuine retail demand or just hobbyist/collector interest
- New cultivar releases from Proven Winners, Bailey, Monrovia, Spring Meadow that are relevant
- What reps are likely pushing vs. what consumers are actually seeking

Return ONLY a JSON object, no markdown, no explanation:
{
  "summary": "2-3 sentence market summary grounded in the actual trend data above",
  "trends": [
    {
      "commonName": "exact name from the data above",
      "botanicalName": "correct botanical name",
      "trendSignal": "rising|stable|peaking|emerging|falling",
      "signalStrength": 1-10,
      "zoneCompatible": true|false,
      "whyItMatters": "1-2 sentences interpreting this specific data point for a buyer",
      "buyWindow": "specific timing advice for ${SEASON} ordering",
      "riskFlag": "specific overstock or zone risk, or null",
      "source": "google_trends_${zoneInfo.state}|cultivar_release|regional_demand"
    }
  ],
  "watchList": ["name 1", "name 2", "name 3"],
  "avoidList": [
    {"name": "plant name", "reason": "specific reason based on the data or zone"}
  ],
  "buyerNote": "One honest, specific sentence of advice for a Zone ${zoneInfo.zone} buyer this ${SEASON}"
}

Only include plants from the data provided. Return 5-8 trends. Flag zone incompatibilities honestly — do not recommend plants outside Zone ${zoneInfo.zone} survivability without a clear warning.`;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 1000,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    const data = await response.json();
    const text = data.content?.map(i => i.text || "").join("") || "";
    const clean = text.replace(/```json|```/g, "").trim();
    return JSON.parse(clean);
  };

  const runScan = async () => {
    if (!validateZip(zipInput)) {
      setZipError("Enter a valid 5-digit zip code");
      return;
    }
    setZipError("");
    setLoading(true);
    setError(null);
    setResults(null);

    try {
      // Stage 1: Zone lookup
      setLoadingStage("Looking up hardiness zone");
      const zoneInfo = await fetchZone(zipInput);
      setZoneData(zoneInfo);
      setZip(zipInput);

      // Stage 2: Real trends data
      setLoadingStage("Fetching regional Google Trends data");
      const trendData = await fetchTrends(zoneInfo.state, category.id);

      if (!trendData.plants || trendData.plants.length === 0) {
        throw new Error("No trend data returned. Google Trends may be rate-limiting. Try again in a moment.");
      }

      // Stage 3: Claude interpretation
      setLoadingStage("Interpreting signals for your region");
      const interpretation = await fetchClaudeInterpretation(trendData, zoneInfo, category.label);

      setResults({ ...interpretation, zoneInfo, rawCount: trendData.plants.length });

    } catch (err) {
      setError(err.message || "Something went wrong. Please try again.");
    } finally {
      setLoading(false);
      setLoadingStage("");
    }
  };

  const signalColor = (signal) => ({
    rising: "#4ade80",
    emerging: "#facc15",
    stable: "#94a3b8",
    peaking: "#f97316",
    falling: "#f87171",
  }[signal] || "#94a3b8");

  const signalLabel = (signal) => ({
    rising: "↑ Rising",
    emerging: "◆ Emerging",
    stable: "→ Stable",
    peaking: "▲ Peaking",
    falling: "↓ Falling",
  }[signal] || signal);

  const strengthBar = (n) => Array.from({ length: 5 }, (_, i) => (
    <span key={i} style={{
      display: "inline-block", width: 8, height: 8, borderRadius: 2, marginRight: 2,
      background: i < Math.round(n / 2) ? "#c8f542" : "#2a3a1a",
    }} />
  ));

  return (
    <div style={{ minHeight: "100vh", background: "#0d1a08", fontFamily: "'Georgia', 'Times New Roman', serif", color: "#e8f0dc" }}>

      {/* Header */}
      <div style={{
        borderBottom: "1px solid #2a3a1a", padding: "28px 40px 24px",
        background: "linear-gradient(180deg, #111f0a 0%, #0d1a08 100%)",
        display: "flex", alignItems: "flex-end", justifyContent: "space-between", flexWrap: "wrap", gap: 16,
      }}>
        <div>
          <div style={{ fontSize: 11, letterSpacing: "0.25em", color: "#c8f542", textTransform: "uppercase", marginBottom: 6, fontFamily: "'Courier New', monospace" }}>
            Garden Center Intelligence
          </div>
          <h1 style={{ margin: 0, fontSize: 32, fontWeight: 400, letterSpacing: "-0.02em", color: "#f0f7e6", lineHeight: 1 }}>
            PlantPulse
          </h1>
          <div style={{ fontSize: 13, color: "#6b8a4e", marginTop: 4, fontStyle: "italic" }}>
            Regional trend intelligence for independent buyers
          </div>
        </div>
        <div style={{ fontSize: 11, color: "#4a6a2e", fontFamily: "'Courier New', monospace", textAlign: "right", letterSpacing: "0.1em" }}>
          SEASON: {SEASON.toUpperCase()}<br />
          {new Date().toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" }).toUpperCase()}<br />
          {zoneData && <span style={{ color: "#c8f542" }}>ZONE {zoneData.zone.toUpperCase()} · {zoneData.state}</span>}
        </div>
      </div>

      <div style={{ padding: "32px 40px", maxWidth: 900, margin: "0 auto" }}>

        {/* Controls */}
        <div style={{ display: "grid", gridTemplateColumns: "200px 1fr", gap: 20, marginBottom: 24 }}>

          {/* Zip input */}
          <div>
            <label style={{ display: "block", fontSize: 10, letterSpacing: "0.2em", color: "#c8f542", textTransform: "uppercase", marginBottom: 8, fontFamily: "'Courier New', monospace" }}>
              Zip Code
            </label>
            <input
              type="text"
              value={zipInput}
              maxLength={5}
              onChange={e => { setZipInput(e.target.value.replace(/\D/g, "")); setZipError(""); }}
              onKeyDown={e => e.key === "Enter" && runScan()}
              placeholder="56001"
              style={{
                width: "100%", background: "#111f0a", border: `1px solid ${zipError ? "#f97316" : "#2a3a1a"}`,
                color: "#e8f0dc", padding: "10px 14px", fontSize: 16, borderRadius: 4,
                fontFamily: "'Courier New', monospace", letterSpacing: "0.15em", boxSizing: "border-box",
                outline: "none",
              }}
            />
            {zipError && <div style={{ fontSize: 11, color: "#f97316", marginTop: 4, fontFamily: "'Courier New', monospace" }}>{zipError}</div>}
          </div>

          {/* Category */}
          <div>
            <label style={{ display: "block", fontSize: 10, letterSpacing: "0.2em", color: "#c8f542", textTransform: "uppercase", marginBottom: 8, fontFamily: "'Courier New', monospace" }}>
              Category
            </label>
            <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
              {CATEGORIES.map(c => (
                <button key={c.id} onClick={() => setCategory(c)} style={{
                  background: category.id === c.id ? "#c8f542" : "#111f0a",
                  border: "1px solid", borderColor: category.id === c.id ? "#c8f542" : "#2a3a1a",
                  color: category.id === c.id ? "#0d1a08" : "#6b8a4e",
                  padding: "8px 14px", fontSize: 12, borderRadius: 3, cursor: "pointer",
                  fontFamily: "'Courier New', monospace", letterSpacing: "0.05em",
                  transition: "all 0.15s", fontWeight: category.id === c.id ? 700 : 400,
                }}>
                  {c.icon} {c.label}
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Run Button */}
        <button onClick={runScan} disabled={loading} style={{
          width: "100%", background: loading ? "#1a2e0f" : "#c8f542",
          border: "none", color: loading ? "#4a6a2e" : "#0d1a08",
          padding: "14px 24px", fontSize: 13, letterSpacing: "0.2em", textTransform: "uppercase",
          fontFamily: "'Courier New', monospace", cursor: loading ? "not-allowed" : "pointer",
          borderRadius: 4, marginBottom: 8, transition: "all 0.2s", fontWeight: 700,
        }}>
          {loading ? `${loadingStage}${dots}` : `▶ Run Trend Scan — ${zipInput || "Enter Zip"} · ${category.label}`}
        </button>

        {/* Data source note */}
        <div style={{ fontSize: 10, color: "#2a3a1a", fontFamily: "'Courier New', monospace", letterSpacing: "0.1em", marginBottom: 28, textAlign: "center" }}>
          LIVE DATA: GOOGLE TRENDS (90-DAY REGIONAL) · USDA PHZM 2023 · CLAUDE INTERPRETATION
        </div>

        {error && (
          <div style={{ background: "#1a0f0f", border: "1px solid #4a1a1a", color: "#f87171", padding: "14px 18px", borderRadius: 4, fontSize: 13, marginBottom: 24, fontFamily: "'Courier New', monospace" }}>
            ⚠ {error}
          </div>
        )}

        {/* Results */}
        {results && (
          <div style={{ animation: "fadeIn 0.4s ease" }}>

            {/* Zone + data badge */}
            <div style={{ display: "flex", gap: 10, marginBottom: 16, flexWrap: "wrap" }}>
              <span style={{ fontSize: 10, fontFamily: "'Courier New', monospace", color: "#c8f542", border: "1px solid #2a4a1a", padding: "3px 8px", borderRadius: 2, letterSpacing: "0.1em" }}>
                ZONE {results.zoneInfo?.zone?.toUpperCase()} · {results.zoneInfo?.state}
              </span>
              <span style={{ fontSize: 10, fontFamily: "'Courier New', monospace", color: "#4a6a2e", border: "1px solid #1a2e0f", padding: "3px 8px", borderRadius: 2, letterSpacing: "0.1em" }}>
                {results.rawCount} PLANTS SCANNED
              </span>
              <span style={{ fontSize: 10, fontFamily: "'Courier New', monospace", color: "#4a6a2e", border: "1px solid #1a2e0f", padding: "3px 8px", borderRadius: 2, letterSpacing: "0.1em" }}>
                SOURCE: GOOGLE TRENDS · {results.zoneInfo?.source === "usda_api" ? "USDA API" : "ZONE ESTIMATE"}
              </span>
            </div>

            {/* Summary */}
            <div style={{ background: "#111f0a", border: "1px solid #2a3a1a", borderLeft: "3px solid #c8f542", padding: "16px 20px", marginBottom: 24, borderRadius: "0 4px 4px 0" }}>
              <div style={{ fontSize: 10, letterSpacing: "0.2em", color: "#c8f542", textTransform: "uppercase", fontFamily: "'Courier New', monospace", marginBottom: 8 }}>
                Market Summary · {zip} · {SEASON.charAt(0).toUpperCase() + SEASON.slice(1)}
              </div>
              <p style={{ margin: 0, fontSize: 14, lineHeight: 1.6, color: "#b8d4a0", fontStyle: "italic" }}>{results.summary}</p>
            </div>

            {/* Trend Cards */}
            <div style={{ fontSize: 10, letterSpacing: "0.2em", color: "#4a6a2e", textTransform: "uppercase", fontFamily: "'Courier New', monospace", marginBottom: 12 }}>
              Active Signals — {results.trends?.length || 0} plants flagged
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: 12, marginBottom: 28 }}>
              {results.trends?.map((t, i) => (
                <div key={i} style={{ background: "#111f0a", border: "1px solid #2a3a1a", borderRadius: 4, padding: "16px 20px", display: "grid", gridTemplateColumns: "1fr auto", gap: 12 }}>
                  <div>
                    <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 4, flexWrap: "wrap" }}>
                      <span style={{ fontSize: 16, fontWeight: 400, color: "#f0f7e6" }}>{t.commonName}</span>
                      <span style={{ fontSize: 10, color: signalColor(t.trendSignal), fontFamily: "'Courier New', monospace", letterSpacing: "0.1em", border: `1px solid ${signalColor(t.trendSignal)}`, padding: "2px 6px", borderRadius: 2 }}>
                        {signalLabel(t.trendSignal)}
                      </span>
                      {!t.zoneCompatible && (
                        <span style={{ fontSize: 10, color: "#f97316", fontFamily: "'Courier New', monospace", border: "1px solid #f97316", padding: "2px 6px", borderRadius: 2 }}>
                          ⚠ ZONE RISK
                        </span>
                      )}
                    </div>
                    <div style={{ fontSize: 11, color: "#4a6a2e", fontStyle: "italic", marginBottom: 8 }}>{t.botanicalName}</div>
                    <p style={{ margin: "0 0 8px", fontSize: 13, lineHeight: 1.5, color: "#b8d4a0" }}>{t.whyItMatters}</p>
                    <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
                      <span style={{ fontSize: 11, color: "#4a6a2e", fontFamily: "'Courier New', monospace" }}>
                        BUY WINDOW: <span style={{ color: "#8ab870" }}>{t.buyWindow}</span>
                      </span>
                      <span style={{ fontSize: 11, color: "#4a6a2e", fontFamily: "'Courier New', monospace" }}>
                        SOURCE: <span style={{ color: "#8ab870" }}>{t.source}</span>
                      </span>
                    </div>
                    {t.riskFlag && (
                      <div style={{ marginTop: 8, fontSize: 11, color: "#f97316", fontFamily: "'Courier New', monospace" }}>⚠ {t.riskFlag}</div>
                    )}
                  </div>
                  <div style={{ textAlign: "right", minWidth: 60 }}>
                    <div style={{ marginBottom: 4 }}>{strengthBar(t.signalStrength)}</div>
                    <div style={{ fontSize: 10, color: "#4a6a2e", fontFamily: "'Courier New', monospace", letterSpacing: "0.1em" }}>{t.signalStrength}/10</div>
                  </div>
                </div>
              ))}
            </div>

            {/* Watch + Avoid */}
            <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 16, marginBottom: 28 }}>
              <div style={{ background: "#111f0a", border: "1px solid #2a3a1a", borderRadius: 4, padding: "16px 20px" }}>
                <div style={{ fontSize: 10, letterSpacing: "0.2em", color: "#facc15", textTransform: "uppercase", fontFamily: "'Courier New', monospace", marginBottom: 12 }}>
                  ◆ Watch List — Monitor Only
                </div>
                {results.watchList?.map((w, i) => (
                  <div key={i} style={{ fontSize: 13, color: "#8ab870", padding: "4px 0", borderBottom: i < results.watchList.length - 1 ? "1px solid #1a2e0f" : "none" }}>{w}</div>
                ))}
              </div>
              <div style={{ background: "#111f0a", border: "1px solid #2a3a1a", borderRadius: 4, padding: "16px 20px" }}>
                <div style={{ fontSize: 10, letterSpacing: "0.2em", color: "#f97316", textTransform: "uppercase", fontFamily: "'Courier New', monospace", marginBottom: 12 }}>
                  ✕ Avoid This Season
                </div>
                {results.avoidList?.map((a, i) => (
                  <div key={i} style={{ padding: "6px 0", borderBottom: i < results.avoidList.length - 1 ? "1px solid #1a2e0f" : "none" }}>
                    <div style={{ fontSize: 13, color: "#f87171" }}>{a.name}</div>
                    <div style={{ fontSize: 11, color: "#4a3a2e", marginTop: 2 }}>{a.reason}</div>
                  </div>
                ))}
              </div>
            </div>

            {/* Buyer Note */}
            <div style={{ background: "#0a1206", border: "1px solid #c8f542", borderRadius: 4, padding: "14px 20px", display: "flex", gap: 12, alignItems: "flex-start" }}>
              <span style={{ fontSize: 18, lineHeight: 1, color: "#c8f542" }}>◈</span>
              <div>
                <div style={{ fontSize: 10, letterSpacing: "0.2em", color: "#c8f542", textTransform: "uppercase", fontFamily: "'Courier New', monospace", marginBottom: 6 }}>
                  Buyer's Note
                </div>
                <p style={{ margin: 0, fontSize: 13, color: "#b8d4a0", lineHeight: 1.6, fontStyle: "italic" }}>{results.buyerNote}</p>
              </div>
            </div>
          </div>
        )}

        {/* Empty state */}
        {!results && !loading && !error && (
          <div style={{ textAlign: "center", padding: "60px 20px", color: "#2a3a1a" }}>
            <div style={{ fontSize: 48, marginBottom: 16 }}>⬡</div>
            <div style={{ fontSize: 12, letterSpacing: "0.2em", fontFamily: "'Courier New', monospace", textTransform: "uppercase" }}>
              Enter your zip code and run a scan
            </div>
          </div>
        )}
      </div>

      <style>{`
        @keyframes fadeIn { from { opacity: 0; transform: translateY(8px); } to { opacity: 1; transform: translateY(0); } }
        input:focus { border-color: #c8f542 !important; }
      `}</style>
    </div>
  );
}