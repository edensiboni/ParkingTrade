# Environment bootstrap

`bootstrap.sql` + `../../scripts/bootstrap-env.sh` bring a Supabase project from
"migrations applied" to "fully serving", **idempotently**, on every deploy.

It exists outside the migration chain on purpose: it carries an
environment-specific Functions URL and the `service_role` key, and neither may
live in a git-committed migration (see
`../migrations/039_spot_availability_webhook.sql` header).

## What the automated bootstrap does

Run automatically by `deploy-staging.yml` / `deploy-production.yml` after
`supabase db push`:

1. `supabase secrets set FIREBASE_SERVICE_ACCOUNT=… PLACES_API_KEY=…` — Edge
   runtime secrets, sourced from GitHub secrets (single source of truth).
2. `bootstrap.sql`:
   - `CREATE EXTENSION IF NOT EXISTS pg_cron, pg_net`
   - upserts the **6 Vault secrets** the migration-039/040/044 webhook triggers
     read: `{announcement,spot,waitlist}_notify_{functions_base_url,service_role_key}`
   - (re)schedules the **5 pg_cron jobs**: `complete-bookings` (*/15),
     `expire-waitlist` (*/15), and the three `drain-*-notifications` (*/2 —
     durability backstop; the `pg_net` webhooks are the fast path)
3. Asserts the counts (5 cron jobs, 6 vault secrets, both extensions present).

## Manual steps the bootstrap does NOT do (one-time per project)

| Step | Where | Notes |
| --- | --- | --- |
| Enable `pg_cron` / `pg_net` if `CREATE EXTENSION` is blocked | Dashboard → Database → Extensions | Bootstrap errors loud if this is needed first |
| Phone/OTP auth provider | Dashboard → Auth → Providers | Required before any sign-in |
| Twilio SMS credentials (prod sender / subaccount) | Dashboard → Auth → SMS | Separate from dev Twilio — see below |
| Site URL + redirect allowlist | Dashboard → Auth → URL Configuration | Prod web origin + `parkingtrade://` scheme |
| PITR / daily backups | Dashboard → Database → Backups | Needs the Pro plan |

No `SUPABASE_DB_URL` secret is needed — `bootstrap-env.sh` derives the Postgres
connection from `supabase/.temp/pooler-url` (written by `supabase link`) and
injects `SUPABASE_DB_PASSWORD` via `PGPASSWORD`.

## Running it by hand (fallback)

```bash
supabase link --project-ref "$SUPABASE_PROJECT_REF"   # writes supabase/.temp/pooler-url
export SUPABASE_PROJECT_REF=…  SUPABASE_ACCESS_TOKEN=…  SUPABASE_DB_PASSWORD=…
export FUNCTIONS_BASE_URL="https://<ref>.supabase.co"
export SERVICE_ROLE_KEY=…  FIREBASE_SERVICE_ACCOUNT="$(cat sa.json)"  PLACES_API_KEY=…
bash scripts/bootstrap-env.sh
```

Or just the SQL:

```bash
PGPASSWORD="<db password>" psql "$(cat supabase/.temp/pooler-url)" \
  -v functions_base_url="https://<ref>.supabase.co" \
  -v service_role_key="<service_role secret>" \
  -f supabase/bootstrap/bootstrap.sql
```

## Rotating the `service_role` key

Re-run the bootstrap. It refreshes both the Vault secrets **and** the cron drain
command strings (the key is embedded literally in each `cron.job.command`).
