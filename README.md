# VIVE EL MUNDIAL EN LA CORTE · Quiniela 2026

Single-file app backed by Supabase. Supports 100+ concurrent users with real-time ranking via Supabase Realtime.

---

## Prerequisites

- [Supabase](https://supabase.com) free account
- [Vercel](https://vercel.com) free account
- GitHub account (to connect Vercel)

---

## Step 1 — Create the Supabase project

1. Go to [supabase.com](https://supabase.com) → **New project**.
2. Choose a name (e.g. `quiniela-mundial`), set a strong database password, select the region closest to Mexico (us-east-1 or us-west-1).
3. Wait ~2 minutes for the project to provision.

---

## Step 2 — Run the SQL migration

1. In your Supabase project, go to **SQL Editor** → **New query**.
2. Open `supabase/migrations/001_init.sql` from this repo.
3. Paste the entire contents into the SQL editor and click **Run**.
4. Verify in **Table Editor** that you see: `profiles`, `matches`, `predicciones`, `codigos`.
5. The `matches` table should already have 104 rows (72 group + 32 KO).

---

## Step 3 — Enable Email OTP auth

1. In Supabase → **Authentication** → **Providers** → **Email**, ensure it is **enabled**.
2. Under **Email** settings, enable **"Confirm email"** (OTP mode, not magic link).
3. In **Authentication** → **URL Configuration**:
   - **Site URL**: set to your Vercel URL (e.g. `https://quiniela-mundial.vercel.app`). You can update this after deploying.
   - **Redirect URLs**: add the same URL.

---

## Step 4 — Get your API credentials

1. Supabase → **Settings** → **API**.
2. Copy:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon / public** key (long JWT string)

---

## Step 5 — Add credentials to index.html

Open `index.html` and find these two lines near the bottom `<script>` block:

```js
const SUPABASE_URL = 'https://YOUR_PROJECT_REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```

Replace the placeholder strings with your actual values. Save the file.

> The anon key is intentionally public-safe — Supabase Row Level Security (RLS) policies protect your data, not key secrecy.

---

## Step 6 — Deploy to Vercel

### Option A — GitHub (recommended)

1. Push this repo to GitHub (any branch).
2. Go to [vercel.com](https://vercel.com) → **New Project** → import your GitHub repo.
3. Leave all settings as defaults (no build command, output directory = `./`).
4. Click **Deploy**.
5. Copy the deployment URL (e.g. `https://quiniela-mundial.vercel.app`).
6. Go back to Supabase → **Authentication** → **URL Configuration** and update **Site URL** and **Redirect URLs** to your Vercel URL.

### Option B — Vercel CLI

```bash
npm i -g vercel
vercel --prod
```

---

## Step 7 — Set up the first admin user

1. Open the deployed app and register with your email.
2. In Supabase → **Table Editor** → `profiles`, find your row and change `role` from `user` to `admin`.
3. Refresh the app — the **ADMIN** tab will appear in the navigation.

---

## Managing roles

| Role      | Can do                                                   |
|-----------|----------------------------------------------------------|
| `user`    | Register, make predictions, redeem codes                 |
| `manager` | Everything a user can + enter match results              |
| `admin`   | Everything a manager can + create/delete codes, reset    |

Change roles directly in **Table Editor** → `profiles` → edit the `role` column.

---

## Real-time

The app subscribes to Supabase Realtime channels for:
- `matches` table — ranking and group tables update instantly when you save a match result.
- `predicciones` table — ranking updates as users make predictions.
- `profiles` table — ranking updates when codes are redeemed.

No page refresh needed.

---

## Codes

Generate visit/consumption codes in the **Admin** tab. Users enter them in the **QUINIELA** tab to earn +15 pts each. Each code is single-use and stored in the `codigos` table.

---

## Scaling

Supabase free tier supports up to 500 concurrent connections. The app uses a single Realtime channel per table (3 total), well within limits for 100+ concurrent users.

---

## Local development

Just open `index.html` in a browser. No build step required. Make sure your Supabase credentials are already in the file.
