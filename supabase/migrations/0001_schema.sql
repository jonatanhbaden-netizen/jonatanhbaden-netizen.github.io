-- pgTAP powers the verification queries
create extension if not exists pgtap with schema extensions;

create type education_level    as enum ('grunnskole','videregaende','fagbrev','bachelor','master','phd');
create type language_level     as enum ('ingen','grunnleggende','god','flytende','morsmal');
create type job_status         as enum ('draft','published','closed');
create type application_status as enum ('sendt','sett','intervju','tilbud','avslag');

create table public.companies (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  org_nr     text,
  industry   text,
  kommune    text not null,
  logo_url   text,
  created_at timestamptz not null default now()
);

create table public.employer_users (
  id         uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  name       text not null,
  email      text not null
);

create table public.jobs (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references public.companies(id) on delete cascade,
  title                 text not null,
  description           text not null default '',
  required_skills       text[] not null default '{}',
  nice_skills           text[] not null default '{}',
  education_min         education_level not null default 'grunnskole',
  experience_min        int not null default 0,
  experience_max        int not null default 99,
  kommune               text not null,
  norsk_min             language_level not null default 'ingen',
  engelsk_min           language_level not null default 'ingen',
  language_required     boolean not null default false,
  start_date            date,
  shortlist_cap         int not null default 10,
  guaranteed_interviews int not null default 10,
  status                job_status not null default 'draft',
  price_nok             int not null default 5000,
  published_at          timestamptz,
  created_at            timestamptz not null default now(),
  constraint jobs_experience_range check (experience_max >= experience_min)
);

-- The profile IS the CV. education/experience are jsonb arrays of
-- {title, institution|company, from, to, description}; to = null means current.
-- highest_education is the single level compared against jobs.education_min.
create table public.profiles (
  id                  uuid primary key references auth.users(id) on delete cascade,
  first_name          text not null default '',
  last_name           text not null default '',
  email               text not null,
  phone               text,
  kommune             text,
  acceptable_kommuner text[] not null default '{}',
  highest_education   education_level not null default 'grunnskole',
  education           jsonb not null default '[]'::jsonb,
  experience          jsonb not null default '[]'::jsonb,
  skills              text[] not null default '{}',
  norsk               language_level not null default 'ingen',
  engelsk             language_level not null default 'ingen',
  available_from      date,
  about               text,
  updated_at          timestamptz not null default now()
);

create table public.match_scores (
  job_id      uuid not null references public.jobs(id) on delete cascade,
  profile_id  uuid not null references public.profiles(id) on delete cascade,
  score       int not null,
  reasons     jsonb not null default '[]'::jsonb,
  computed_at timestamptz not null default now(),
  primary key (job_id, profile_id)
);

create table public.applications (
  id             uuid primary key default gen_random_uuid(),
  job_id         uuid not null references public.jobs(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  status         application_status not null default 'sendt',
  score_at_apply int not null default 0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (job_id, profile_id)
);

create table public.interviews (
  id             uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications(id) on delete cascade,
  scheduled_at   timestamptz not null,
  outcome        text,
  notes          text,
  created_at     timestamptz not null default now()
);

create index jobs_status_idx            on public.jobs (status);
create index jobs_company_idx           on public.jobs (company_id);
create index match_profile_score_idx    on public.match_scores (profile_id, score desc);
create index match_job_score_idx        on public.match_scores (job_id, score desc);
create index applications_profile_idx   on public.applications (profile_id, status);
create index applications_job_idx       on public.applications (job_id);
create index interviews_application_idx on public.interviews (application_id);
