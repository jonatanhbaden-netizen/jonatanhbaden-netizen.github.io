# Jobbo

A Norwegian job marketplace where employers get ten qualified applicants instead
of four hundred unfiltered ones.

A candidate builds one structured profile (which *is* their CV), is shown at most
five jobs they genuinely fit, and can hold at most five active applications. The
employer gets a shortlist of ten, ranked, each with the reasons for the match —
which is what makes it possible to sell them a guarantee to interview all ten.

This repository is **Demo 1**: a working product used to pre-sell listings to
Oslo employers. Matching is deterministic and rule-based; there is no LLM.

- Spec: `docs/superpowers/specs/2026-09-04-jobbo-demo-design.md`
- Backend plan: `docs/superpowers/plans/2026-09-04-jobbo-backend.md`
- Drift (nøkler, Stripe, Resend, NAV, dashboard-innstillinger): `docs/DRIFT.md`

## Running it

```bash
npm install
npm run dev          # serves web/ on http://localhost:5173
```

The frontend has no build step — vanilla JS ES modules, loaded directly. It talks
to a hosted Supabase project; the URL and anon key are in `web/shared/config.js`.

## Demo accounts

Password for all three: `jobbo-demo`

| Account | What it shows |
|---|---|
| `arbeidsgiver1@jobbo.demo` | Grünerløkka Matsenter — three published jobs, full shortlists and a venteliste |
| `arbeidsgiver2@jobbo.demo` | Storo Sport — one draft, for the live "post → pay → publish" moment |
| `kandidat@jobbo.demo` | Half-filled profile with **no** matches, so completing it makes matches appear |

## The demo script

1. Employer dashboard: three jobs, each with *kvalifiserte matchet → har søkt → til intervju*.
2. Open a shortlist: ten ranked candidates, every score with its reasons. Open a CV.
3. Post a new job through the wizard, pay 5 000 kr (fake), publish — the shortlist
   fills immediately from candidates already in the system.
4. On a phone: complete the candidate profile, watch matches appear, apply. The
   application shows up on the employer's shortlist with its score.
5. Show the guarantee meter and the Finn price comparison.

## How it works

Everything lives in Postgres.

- **`compute_match(job, profile)`** scores a pair 0–100 and returns a Norwegian
  `reasons` array. Weights: påkrevde ferdigheter 35, ønskede 5, utdanning 15,
  erfaring 15, sted 15, språk 10, oppstart 5. Two rules zero the score outright:
  an absolute language requirement that is not met, and matching *none* of the
  required skills.
- **Triggers** recompute scores whenever a job or a profile changes.
- **Rationing is enforced in the database**, not the UI. A `BEFORE INSERT` trigger
  on `applications` rejects anything below a score of 60, on an unpublished job,
  or beyond five active applications. The seed goes through the same trigger.
- **RLS** means nobody browses the candidate pool: an employer can read a profile
  only if that person applied to one of their own jobs.

## Layout

```
supabase/migrations/   0001 schema · 0002 RLS · 0003 matching · 0004 rationing
                       0005 skills vocabulary · 0006 required-skills rule
supabase/seed/seed.sql runs against an empty, migrated database
web/shared/            tokens, base and component CSS; supabase client; CV renderer
web/employer/          login, dashboard, job wizard, payment, shortlist, candidate CV
web/kandidat/          login, profile builder, matches, applications, printable CV
```

## Not built yet

Real payments, any AI, notifications, employer self-signup, iOS, English UI,
skill synonyms, and candidate data export/deletion — the last of which is
required before real users touch this. See spec section 7.
