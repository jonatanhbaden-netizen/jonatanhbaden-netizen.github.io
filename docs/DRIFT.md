# Drift — det som må settes opp utenfor koden

Alt i repoet virker uten disse. Hver del skrur seg på når nøkkelen finnes.

## Supabase-dashboard (én gang)

Authentication → URL Configuration
- **Site URL:** adressen siden ligger på (f.eks. `https://jobbo.no`)
- **Redirect URLs:** `<site>/kandidat/matcher.html`, `<site>/employer/dashboard.html`, `<site>/konto/nytt-passord.html`

Authentication → Providers → Email
- **Confirm email:** på. Uten egen SMTP sender Supabase maks 2 e-poster i timen — sett opp
  **Custom SMTP** (Resend gir SMTP-detaljer) før ekte brukere.

Authentication → Password
- **Leaked password protection:** på (HaveIBeenPwned-sjekk).

## Hemmeligheter (Edge Functions → Secrets)

| Nøkkel | Brukes av | Uten den |
|---|---|---|
| `STRIPE_SECRET_KEY` | `create-checkout` | Stillinger publiseres uten betaling (demo-modus) |
| `STRIPE_WEBHOOK_SECRET` | `stripe-webhook` | Webhook avviser alt |
| `RESEND_API_KEY` | `send-notifications` | Varsler blir liggende i køen (`notifications`, status `venter`) |
| `EMAIL_FROM` | `send-notifications` | `Jobbo <onboarding@resend.dev>` |
| `SITE_URL` | `send-notifications` | Lenkene i e-postene blir relative |
| `NAV_API_TOKEN` | `import-nav` | Ingen import |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` og `SUPABASE_SERVICE_ROLE_KEY` settes automatisk.

## Stripe

1. Opprett konto på stripe.com, aktiver NOK. Vipps kan skrus på som betalingsmetode i Stripe-dashbordet.
2. Developers → Webhooks → Add endpoint:
   `https://ndvefswyfriivcqntpxu.supabase.co/functions/v1/stripe-webhook`, hendelse `checkout.session.completed`.
3. Legg inn `STRIPE_SECRET_KEY` (sk_live_… / sk_test_…) og `STRIPE_WEBHOOK_SECRET` (whsec_…).

Flyt: `betaling.html` → `create-checkout` lager en Checkout Session og en rad i `payments` →
Stripe sender kunden tilbake med `session_id` → webhooken setter `payments.status = betalt`
og publiserer stillingen → siden poller til den er publisert.

## Resend

1. Opprett konto, verifiser domenet du vil sende fra.
2. `RESEND_API_KEY`, `EMAIL_FROM` (f.eks. `Jobbo <hei@jobbo.no>`), `SITE_URL`.

Varslene legges i `notifications` av triggere: ny søker (arbeidsgiver), intervju/tilbud/avslag
(kandidat), foreslåtte intervjutider (kandidat), bekreftet intervju (arbeidsgiver), nye matcher
(kandidat, én e-post per natt). `pg_cron` kaller `send-notifications` hvert femte minutt.

## Arbeidsplassen (NAV)

1. Be om token på arbeidsplassen.nav.no (offentlig API for stillingsfeed, gratis).
2. `NAV_API_TOKEN`. Importen kjører 03:30 hver natt, før fordelingen kl. 04:00.

Importerte stillinger ligger under firmaet «Arbeidsplassen (NAV)» med `source = 'nav'` og
`external_url`. Kandidaten sender søknaden hos kilden; Jobbo teller bare plassen.
**Feltnavnene i feeden er skrevet etter dokumentasjonen, ikke testet mot et ekte token** —
kjør funksjonen manuelt første gang og sjekk `jobs` etterpå.

## Nattkjøring

`pg_cron`-jobber (se `select * from cron.job`):
- `jobbo_import_nav` 03:30
- `jobbo_tildeling` 04:00 — `run_allocation()`, global fordeling
- `jobbo_varsler` hvert 5. minutt

Statistikk per kjøring i `allocation_cycles.stats`.
