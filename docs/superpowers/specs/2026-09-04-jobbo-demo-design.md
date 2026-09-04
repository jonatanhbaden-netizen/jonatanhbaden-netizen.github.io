# Jobbo — Demo 1 Design

**Date:** 2026-09-04
**Status:** Approved 2026-09-04 (design confirmed in chat)
**Path:** Architectural (new project). Next step after approval: `superpowers:writing-plans`.

---

## Context

Oslo has ~12 000 registered jobseekers and ~4 900 open positions, yet individual postings routinely receive 400 applications while only a handful get a reply. The problem is not supply — it is **concentration**: applying is free, so everyone applies everywhere, and the same attractive jobs drown while others go unfilled.

Jobbo is a two-sided job marketplace for Norway where:

- **Candidates** build one structured profile (which *is* their CV), get shown only the 3–5 jobs they genuinely fit, and can hold at most 5 active applications.
- **Employers** post structured job listings and receive a ranked shortlist of ~10 qualified applicants instead of 400 unfiltered ones.
- The rationing + matching makes it possible to sell employers an **interview guarantee** for shortlisted candidates.
- **Monetisation:** employers pay per listing (target 5 000 NOK vs Finn's ~10 000 NOK).

Jobbo is **the** place where jobs are posted and applied to. It does not aggregate from Finn or NAV.

### Why a demo first

The marketplace has a two-sided cold start. The path chosen: build a working demo to pre-sell listings to Oslo employers, then onboard candidates against real listings. This spec covers **Demo 1** only.

### Honest constraints carried into the design

1. **Matching routes, it does not create candidates.** The rationing rules (top-5, max-5, cap-10) are the mechanic that makes "10 not 400" true. They are enforced in the database, not only the UI.
2. **The interview guarantee is a contractual promise by the employer.** The system only tracks it; it cannot produce it.
3. **Recruitment AI is high-risk under the EU AI Act (Annex III) and GDPR Art. 22 applies.** Even the rule-based demo is built explainable (every score carries human-readable `reasons`), never auto-rejects, keeps humans as the only actors that change application status, and stores data in the EU. This is the baseline any later AI model is measured against.

---

## Decisions made

| Question | Decision |
|---|---|
| Audience for Demo 1 | Employers — to pre-sell listings |
| Fidelity | Real backend (Supabase), **rule-based** matching, no LLM |
| Platform | Approach A — employer web + candidate **mobile-first web** now; native iOS in Phase 2 on the same backend |
| Language | Norwegian bokmål UI and seed data |
| Auth on stage | Email + password (magic links are awkward in a live pitch) |
| Payments | Fake checkout page — no Stripe/Vipps |

---

## 1. Data model

Supabase Postgres, region `eu-west-1`. New project (none exists for Jobbo).

### Enums

```sql
create type education_level  as enum ('grunnskole','videregaende','fagbrev','bachelor','master','phd');
create type language_level   as enum ('ingen','grunnleggende','god','flytende','morsmal');
create type job_status       as enum ('draft','published','closed');
create type application_status as enum ('sendt','sett','intervju','tilbud','avslag');
```

### Tables

| Table | Key columns | Notes |
|---|---|---|
| `companies` | `id, name, org_nr, industry, kommune, logo_url, created_at` | Employer organisations |
| `employer_users` | `id → auth.users, company_id, name, email` | One login belongs to one company |
| `jobs` | `id, company_id, title, description, required_skills text[], nice_skills text[], education_min, experience_min int, experience_max int, kommune, norsk_min, engelsk_min, language_required bool, start_date date, shortlist_cap int default 10, guaranteed_interviews int default 10, status job_status, price_nok int default 5000, published_at, created_at` | Structured, not a free-text blob — the structure is what makes matching work |
| `profiles` | `id → auth.users, first_name, last_name, email, phone, kommune, acceptable_kommuner text[], education jsonb, experience jsonb, skills text[], norsk language_level, engelsk language_level, available_from date, about text, updated_at` | **The profile is the CV.** `education`/`experience` are jsonb arrays of `{title, institution/company, from, to, description}`; `to = null` means current |
| `match_scores` | `job_id, profile_id, score int, reasons jsonb, computed_at` — PK `(job_id, profile_id)` | Recomputed by trigger on any job/profile change |
| `applications` | `id, job_id, profile_id, status application_status, score_at_apply int, created_at, updated_at` — unique `(job_id, profile_id)` | Status changed only by employer |
| `interviews` | `id, application_id, scheduled_at, outcome, notes` | Drives the guarantee dashboard |

Skills are lowercase canonical strings from a seed vocabulary (~150 entries). Synonym handling is out of scope for the demo.

### Roles

A login is **either** an employer (row in `employer_users`) **or** a candidate (row in `profiles`), never both. `web/shared/auth.js` resolves the role by checking which table contains the user's id and redirects to the right app.

### Row-level security

- Candidate: read/write **own** `profiles` row; read own `applications` and own `match_scores`; read `jobs` where `status = 'published'`.
- Employer: read/write `jobs` and `companies` for own `company_id`; read `applications` on own jobs; read `profiles` **only** where that profile has applied to one of the company's jobs; read `match_scores` on own jobs (for the "47 matchet" count only — no profile details without an application).
- Nobody browses the full candidate pool.

---

## 2. Matching

### `compute_match(job_id, profile_id) → (score int, reasons jsonb)`

A single SQL/plpgsql function. Deterministic. Weights sum to 100.

| Component | Points | Rule |
|---|---|---|
| Required skills | 35 | `35 × |required ∩ skills| / |required|`; empty `required` → 35 |
| Nice-to-have skills | 5 | `5 × |nice ∩ skills| / |nice|`; empty → 0 |
| Utdanning | 15 | level ≥ `education_min` → 15; one level below → 7; else 0 |
| Erfaring | 15 | total years (from `experience` date ranges) within `[min, max]` → 15; below min → `15 × years/min`; above max → 10 |
| Sted | 15 | same `kommune` → 15; job kommune in `acceptable_kommuner` → 10; else 0 |
| Språk | 10 | `norsk ≥ norsk_min` and `engelsk ≥ engelsk_min` → 10; else 0. **If `language_required` and it fails → hard exclude: score 0** |
| Oppstart | 5 | `start_date` null or `available_from ≤ start_date` → 5; within 30 days after → 3; else 0 |

`reasons` is a jsonb array of `{key, ok, text}` in Norwegian, one per component, e.g.
`[{"key":"skills","ok":true,"text":"4 av 5 påkrevde ferdigheter"}, {"key":"sted","ok":true,"text":"Bor i Oslo"}, {"key":"sprak","ok":false,"text":"Mangler engelsk: god"}]`.

**Kvalifisert** = `score ≥ 60`.

### Recompute triggers

- `jobs` insert/update where `status = 'published'` → recompute for all profiles.
- `profiles` insert/update → recompute for all published jobs.
- Demo scale (≈300 × 60 = 18 000 pairs) makes full recompute trivial.

### Rationing — enforced in the database

| Rule | Where |
|---|---|
| Candidate can only apply to a job with `match_scores.score ≥ 60` | `BEFORE INSERT` trigger on `applications` → `raise 'Du kan bare søke på stillinger du matcher'` |
| Max 5 active applications (`status in ('sendt','sett','intervju')`) | Same trigger → `raise 'Maks 5 aktive søknader'` |
| Only published jobs accept applications | Same trigger |
| Candidate sees **top 5** matches | View `my_matches`: top 5 by score among published jobs not yet applied to, score ≥ 60 (top-5 is enforced in the view/UI, not as a constraint, since rankings shift) |
| Employer sees at most `shortlist_cap` applicants | View `job_shortlist`: applicants ranked by **live** `match_scores.score` (so a candidate who improves their profile moves up), `row_number ≤ shortlist_cap`. `applications.score_at_apply` is kept as an audit snapshot only. Applicants beyond the cap remain `sendt` and are shown as **"Venteliste (n)"** — they are never rejected automatically |

---

## 3. Employer web app (`web/employer/`) — the polished side

**Flow:** Logg inn → Dashboard → Legg ut stilling → Betaling (demo) → Stillingsside → Kandidatprofil → Status / intervju → Garanti

| Page | Content |
|---|---|
| `index.html` | Login (email + password) |
| `dashboard.html` | Company's jobs as cards: *Matchet / Søkt / Intervju* counts, status. CTA "Legg ut ny stilling" |
| `ny-stilling.html` | Wizard, 3 steps: (1) tittel, beskrivelse, kommune, oppstart; (2) påkrevde + ønskede ferdigheter (tag input from vocabulary), utdanning, erfaring, språk; (3) oppsummering + garanti-vilkår ("Du forplikter deg til å intervjue inntil 10 kandidater fra shortlisten") → saves as `draft` |
| `betaling.html` | Fake checkout: "5 000 kr — Betal (demo)" → sets `status = 'published'`, `published_at = now()`. Shows Finn comparison (10 000 kr) |
| `stilling.html?id=` | Header with *"47 kvalifiserte matchet · 12 har søkt · du ser de 10 beste"*. Guarantee bar *"Garantert 10 intervjuer · 3 booket"* — *booket* = number of `interviews` rows on this job's applications. Ranked shortlist cards: name, score, reasons chips, status pill, buttons `Sett` / `Book intervju` / `Tilbud` / `Avslag`. `Book intervju` opens a date-time picker, inserts an `interviews` row and sets status → `intervju`. Status never changes automatically. Below: "Venteliste (n)" collapsed |
| `kandidat.html?id=` | Full profile rendered as a CV + the match `reasons` for this job + status controls |

---

## 4. Candidate web app (`web/kandidat/`) — mobile-first, believable

**Flow:** Logg inn → Bygg profil (CV) → Mine matcher → Søk → Mine søknader → Last ned CV

| Page | Content |
|---|---|
| `index.html` | Login / "Opprett profil" |
| `profil.html` | CV builder: sectioned form (personalia, utdanning, erfaring, ferdigheter, språk, sted, tilgjengelig fra, om meg) with a **live preview** beside/below it. Saves to `profiles`. On save, matches recompute |
| `matcher.html` | The top-5 match cards: tittel, firma, score, reasons ("Derfor passer du"), `Søk` button. Empty state explains "Fullfør profilen for å få matcher" |
| `soknader.html` | Active applications with status timeline; counter *"3 av 5 aktive søknader"* |
| `cv.html` | Print view of the profile; `@media print` CSS; user does "Lagre som PDF". No PDF library |

Applying to a job that is not in the match list is not possible in the UI (and rejected by the DB).

---

## 5. Stack, structure, seed data

### Stack

- **Backend:** Supabase — Postgres, Auth (email + password), RLS, SQL functions/triggers/views. No Edge Functions for the demo.
- **Front-end:** vanilla JS ES modules + `@supabase/supabase-js` (ESM from CDN). No framework, no build step. Multi-page. Semantic HTML, no inline handlers, design tokens as CSS custom properties, mobile-first with `clamp()`, CSS Grid layout, `prefers-reduced-motion` on all animation, no `!important`. Font: not Inter/Roboto/Open Sans/Lato — chosen during build via the frontend-design skill.
- **Hosting:** any static host (Netlify / Cloudflare Pages). Supabase URL + anon key in `web/shared/config.js`.
- **Phase 2 (not this spec):** `ios/` SwiftUI + `supabase-swift` against the same backend.

### Folder structure

```
Jobbo/
├── CLAUDE.md                       # index only → @.claude/rules/*.md
├── .claude/rules/
│   ├── design.md                   # tokens, fonts, layout, motion
│   ├── code.md                     # vanilla JS, semantic HTML, module layout
│   ├── database.md                 # migrations, RLS, naming, Norwegian enums
│   └── workflow.md                 # TDD for SQL, demo-script verification
├── docs/superpowers/specs/         # this file
├── supabase/
│   ├── config.toml
│   ├── migrations/
│   │   ├── 0001_schema.sql
│   │   ├── 0002_rls.sql
│   │   ├── 0003_matching.sql       # compute_match + recompute triggers
│   │   └── 0004_rationing.sql      # application trigger + views
│   ├── seed/
│   │   ├── generate.mjs            # → seed.sql
│   │   └── seed.sql
│   └── tests/
│       └── matching.test.sql       # pgTAP
└── web/
    ├── shared/
    │   ├── config.js  supabase.js  auth.js
    │   ├── tokens.css  base.css  components.css
    │   └── components/             # small vanilla modules (tag-input, status-pill, match-card)
    ├── employer/                   # pages in §3
    └── kandidat/                   # pages in §4
```

### Seed data (all Norwegian)

- ~150 canonical skills across bransjer (butikk/service, helse, IT, bygg, økonomi, logistikk, barnehage/skole, restaurant)
- ~40 Oslo-area companies (fictional names, real kommuner)
- ~60 jobs: mixed bransjer, ~50 published, ~10 draft/closed
- ~300 candidate profiles with realistic education/experience/skills distributions
- ~250 applications with a spread of statuses, so dashboards and guarantee bars are populated
- **Seed must pass the production rules.** `generate.mjs` creates auth users via the Supabase Admin API (service-role key, local only — never shipped to the browser), inserts companies → jobs → profiles, lets the triggers compute `match_scores`, then generates applications **only** from pairs with score ≥ 60 and at most 5 active per profile — so seeding exercises the same triggers as real usage.
- **Demo accounts** (password `jobbo-demo`):
  - `arbeidsgiver1@jobbo.demo` — company with 3 published jobs, full shortlists
  - `arbeidsgiver2@jobbo.demo` — company with 1 draft job (for the live "post + pay + publish" moment)
  - `kandidat@jobbo.demo` — half-filled profile (for the live "complete profile → matches appear" moment)

### The demo script (what the build must make possible)

1. Laptop, employer dashboard: *"Tre stillinger. Butikkmedarbeider: 47 kvalifiserte matchet, 12 har søkt, du ser de 10 beste."*
2. Open the shortlist → score + reasons → open a CV.
3. Post a new job via the wizard → fake pay 5 000 kr → publish → shortlist counts appear immediately from seeded candidates.
4. Phone, candidate app: complete the profile → matches appear → apply → back on the laptop the application shows up with its score.
5. Show the guarantee bar and the Finn price comparison.

---

## 6. Testing

- **SQL (TDD, pgTAP):** `compute_match` component-by-component (perfect match = 100; language hard-exclude = 0; 2/5 skills = 14 skill points; experience edge cases); rationing trigger (6th active application raises; score < 60 raises; unpublished job raises); `job_shortlist` caps at `shortlist_cap`; RLS (employer cannot read a profile that has not applied).
- **Run:** `supabase test db` locally (Supabase CLI + Docker), or against the hosted project via the Supabase MCP `execute_sql`.
- **UI:** walk the demo script end-to-end in the browser (desktop + mobile viewport) before calling any phase done.

---

## 7. Out of scope for Demo 1

Real payments · any LLM/AI · email/SMS notifications · employer self-signup (accounts seeded) · aggregation from Finn/NAV · iOS app · English UI · skill synonyms · candidate account deletion / data export (required before real users — Phase 2) · real interview scheduling/calendar.

---

## 8. Open questions

- Domain and static host — decided at deploy time (last build phase). Not blocking.
- Project location: stays at `~/Jobbo` — deliberate exception to the `~/Prosjekter/` folder rule (user decision 2026-09-04).
