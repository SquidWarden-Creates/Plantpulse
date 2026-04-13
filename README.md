# Plantpulse
Plant trend scraper/tracker

# PlantPulse — Deployment Guide

Regional plant market intelligence for independent garden center buyers.
Live data: Google Trends (pytrends) · USDA PHZM 2023 · Claude interpretation layer.

---

## What This Is

PlantPulse fetches real 90-day Google Trends data filtered by US state,
looks up the buyer's USDA hardiness zone by zip code (2023 map), and uses
Claude to interpret that live data into actionable buying intelligence.

No fake data. No manual updates. No catalog integration required.

---

## Project Structure

```
plantpulse/
├── api/
│   ├── trends.py       # Pytrends serverless function (Google Trends)
│   └── zone.py         # USDA zone lookup by zip code
├── src/
│   ├── App.jsx         # Main React frontend
│   └── main.jsx        # React entry point
├── index.html
├── package.json
├── requirements.txt    # Python dependencies for Vercel
├── vercel.json         # Vercel routing + build config
└── vite.config.js
```

---

## Deployment Steps

### 1. Prerequisites

- GitHub account (free): https://github.com
- Vercel account (free): https://vercel.com
- Anthropic API key: https://console.anthropic.com

### 2. Push to GitHub

1. Create a new repository on GitHub called `plantpulse`
2. From inside the plantpulse folder on your computer, run:

```bash
git init
git add .
git commit -m "Initial PlantPulse build"
git remote add origin https://github.com/YOUR_USERNAME/plantpulse.git
git push -u origin main
```

### 3. Deploy to Vercel

1. Go to https://vercel.com and sign in
2. Click "Add New Project"
3. Import your `plantpulse` GitHub repository
4. Vercel will auto-detect the Vite + Python setup
5. Before deploying, add your environment variable:
   - Key: `ANTHROPIC_API_KEY`
   - Value: your key from console.anthropic.com
6. Click Deploy

Vercel will give you a public URL like `https://plantpulse.vercel.app`
That URL is what you share with Drummers or any other garden center.

### 4. Test It

1. Visit your Vercel URL
2. Enter zip code `56001` (Mankato, MN)
3. Select Shrubs & Trees
4. Click Run Trend Scan
5. It will: look up Zone 5A → fetch real Google Trends data for MN → interpret results

---

## Sharing With Garden Centers

Send them the URL. That's it. No install, no login, no account.
They enter their zip code and category. Everything runs in their browser.

---

## Cost Estimates

| Service         | Cost             |
|-----------------|------------------|
| Vercel hosting  | Free (hobby tier)|
| pytrends        | Free             |
| USDA PHZM API   | Free             |
| Anthropic API   | ~$2-5/month at pilot scale |

---

## Upgrading the API Key Model

**Pilot phase (now):** Your ANTHROPIC_API_KEY in Vercel env vars covers all usage.

**Commercial phase:** Add a subscription layer (Stripe) and proxy API calls
through your backend. Users never touch the API key. You charge a seasonal
or annual rate that covers costs plus margin.

---

## Google Trends Rate Limiting

Pytrends queries Google Trends without an API key. Google rate-limits
aggressive usage. The trends.py function includes:
- Batching (max 5 plants per request, as pytrends requires)
- 1.5 second delay between batches
- Exponential backoff retry logic (3 attempts)

For a pilot with 1-10 users per day this is not a concern.
At scale (100+ daily scans), consider caching results for 24 hours.

---

## Hardiness Zone Data

Zone lookups use the official USDA Plant Hardiness Zone Map API (2023).
Endpoint: https://phzmapi.org/{zipcode}.json

This is the most current and authoritative source available.
The 2023 USDA update shifted approximately 30% of US zip codes,
including parts of the Upper Midwest. Do not use older zone data.

If the USDA API is unavailable, zone.py falls back to state-level
zone estimates derived from the 2023 map.

---

## Adding New Plants

To add plants to the tracking list, edit `api/trends.py`:

1. Add to `PLANT_LOOKUP` dict with common name, botanical name, and search aliases
2. Add the common name to the appropriate list in `CATEGORY_PLANTS`

Redeploy to Vercel (automatic if connected to GitHub — just push the change).

