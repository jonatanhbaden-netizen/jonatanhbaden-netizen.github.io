-- ---------------------------------------------------------------------------
-- Tildeling — global fordeling av matcher (deferred acceptance med kvoter).
--
-- Problemet: my_matches beregnet topp 5 per kandidat uten å se de andre
-- kandidatene. Samme stilling ble vist til 37 personer, en annen til 2.
--
-- Løsningen: run_allocation() ser hele markedet under ett. Kandidatene
-- foreslår seg til stillinger i score-rekkefølge, hver stilling holder de
-- `exposure_cap` beste og slipper resten, de sluppede foreslår seg videre.
-- Resultatet er stabilt: ingen kandidat og stilling ville begge heller hatt
-- hverandre. Etterpå sikrer et gulv-pass at hver stilling har minst
-- GULV kandidater når kvalifiserte finnes.
--
-- Kapasiteter
--   kandidat: 5 − aktive søknader − ventende tildelinger
--   stilling: shortlist_cap × 2 − mottatte søknader
--
-- En søknad krever fra nå en tildeling, og tildelingen slettes idet
-- søknaden sendes. Slik teller aktive søknader + ventende tildelinger
-- alltid til maks 5 per kandidat, og maks 2×cap personer ser en stilling
-- over hele dens levetid.
-- ---------------------------------------------------------------------------

create type allocation_source as enum ('match', 'gulv', 'lopende');

create table public.allocation_cycles (
  id          uuid primary key default gen_random_uuid(),
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  rounds      int,
  stats       jsonb not null default '{}'::jsonb
);

create table public.allocations (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  job_id     uuid not null references public.jobs(id)     on delete cascade,
  score      int  not null,
  source     allocation_source not null,
  cycle_id   uuid references public.allocation_cycles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (profile_id, job_id)
);
create index allocations_job_idx on public.allocations (job_id);

-- Terskelen hver stilling endte på. Forklaringen til den som ikke kom med:
-- "laveste score på lista er 78, din er 71". Én rad per stilling, siste kjøring.
create table public.job_cutoffs (
  job_id       uuid primary key references public.jobs(id) on delete cascade,
  cycle_id     uuid references public.allocation_cycles(id) on delete set null,
  cutoff_score int not null,
  holders      int not null,
  cap          int not null,
  computed_at  timestamptz not null default now()
);

alter table public.allocation_cycles enable row level security;
alter table public.allocations       enable row level security;
alter table public.job_cutoffs       enable row level security;

create policy allocations_select_own on public.allocations
  for select to authenticated using (profile_id = auth.uid());
-- Ingen persondata, bare en terskel per stilling.
create policy job_cutoffs_select on public.job_cutoffs
  for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- Kapasiteter
-- ---------------------------------------------------------------------------

create or replace function public.free_slots(p_profile_id uuid)
returns int language sql stable set search_path = public as $fn$
  select greatest(0, 5
    - (select count(*) from public.applications
         where profile_id = p_profile_id and status in ('sendt','sett','intervju'))
    - (select count(*) from public.allocations where profile_id = p_profile_id))::int
$fn$;

create or replace function public.job_free_cap(p_job_id uuid)
returns int language sql stable set search_path = public as $fn$
  select greatest(0, j.shortlist_cap * 2
    - (select count(*) from public.applications where job_id = j.id)
    - (select count(*) from public.allocations  where job_id = j.id))::int
  from public.jobs j where j.id = p_job_id
$fn$;

-- ---------------------------------------------------------------------------
-- run_allocation — nattlig global fordeling. Erstatter alle tildelinger.
-- ---------------------------------------------------------------------------

create or replace function public.run_allocation()
returns uuid language plpgsql security definer set search_path = public as $fn$
declare
  gulv     constant int := 3;
  v_cycle  uuid;
  v_round  int := 0;
  v_new    int;
  v_job    record;
begin
  insert into public.allocation_cycles default values returning id into v_cycle;

  -- Alt beregnes på nytt; ventende tildelinger telles derfor ikke mot kvoten her.
  create temp table cand on commit drop as
    select p.id as profile_id,
           greatest(0, 5 - (select count(*) from public.applications a
                            where a.profile_id = p.id
                              and a.status in ('sendt','sett','intervju')))::int as slots
    from public.profiles p;

  create temp table job on commit drop as
    select j.id as job_id,
           greatest(0, j.shortlist_cap * 2
             - (select count(*) from public.applications a where a.job_id = j.id))::int as cap
    from public.jobs j
    where j.status = 'published';

  -- Preferanselister: kvalifiserte par, minus dem kandidaten alt har søkt på.
  create temp table pref on commit drop as
    select m.profile_id, m.job_id, m.score,
           row_number() over (partition by m.profile_id
                              order by m.score desc, m.job_id) as rn
    from public.match_scores m
    join job  on job.job_id = m.job_id and job.cap > 0
    join cand on cand.profile_id = m.profile_id and cand.slots > 0
    where m.score >= 60
      and not exists (select 1 from public.applications a
                      where a.job_id = m.job_id and a.profile_id = m.profile_id);
  create index on pref (profile_id, rn);

  create temp table ptr on commit drop as
    select profile_id, 1 as next_rn from cand where slots > 0;

  create temp table held (
    profile_id uuid, job_id uuid, score int, source allocation_source,
    primary key (profile_id, job_id)
  ) on commit drop;

  create temp table props (profile_id uuid, job_id uuid, score int, rn bigint) on commit drop;

  -- Deferred acceptance
  loop
    v_round := v_round + 1;

    truncate props;
    insert into props
      select p.profile_id, p.job_id, p.score, p.rn
      from (
        select c.profile_id, pt.next_rn,
               c.slots - (select count(*) from held h where h.profile_id = c.profile_id) as free
        from cand c join ptr pt on pt.profile_id = c.profile_id
      ) n
      join pref p on p.profile_id = n.profile_id
                 and p.rn >= n.next_rn and p.rn < n.next_rn + n.free
      where n.free > 0;
    get diagnostics v_new = row_count;
    exit when v_new = 0;

    update ptr set next_rn = x.mx + 1
      from (select profile_id, max(rn) as mx from props group by profile_id) x
      where x.profile_id = ptr.profile_id;

    insert into held select profile_id, job_id, score, 'match' from props;

    -- Hver stilling beholder de cap beste den holder på
    delete from held h
      using (select profile_id, job_id,
                    row_number() over (partition by job_id
                                       order by score desc, profile_id) as r
             from held) x
      join job on job.job_id = x.job_id
      where h.profile_id = x.profile_id and h.job_id = x.job_id and x.r > job.cap;
  end loop;

  -- Gulv: stillinger under GULV fylles fra kandidater med ledige plasser,
  -- aldri over stillingens eget tak.
  -- Rad for rad per stilling så én kandidat ikke fyller to gulv samtidig.
  for v_job in
    select job.job_id, least(gulv, job.cap) - count(h.profile_id) as mangler
    from job left join held h on h.job_id = job.job_id
    group by job.job_id, job.cap having count(h.profile_id) < least(gulv, job.cap)
  loop
    insert into held
      select m.profile_id, m.job_id, m.score, 'gulv'
      from public.match_scores m
      join cand c on c.profile_id = m.profile_id
      where m.job_id = v_job.job_id and m.score >= 60
        and c.slots > (select count(*) from held h where h.profile_id = m.profile_id)
        and not exists (select 1 from held h
                        where h.profile_id = m.profile_id and h.job_id = m.job_id)
        and not exists (select 1 from public.applications a
                        where a.job_id = m.job_id and a.profile_id = m.profile_id)
      order by m.score desc, m.profile_id
      limit v_job.mangler;
  end loop;

  delete from public.allocations;
  insert into public.allocations (profile_id, job_id, score, source, cycle_id)
    select profile_id, job_id, score, source, v_cycle from held;

  delete from public.job_cutoffs;
  insert into public.job_cutoffs (job_id, cycle_id, cutoff_score, holders, cap)
    select job.job_id, v_cycle, coalesce(min(h.score), 0), count(h.profile_id), job.cap
    from job left join held h on h.job_id = job.job_id
    group by job.job_id, job.cap;

  update public.allocation_cycles set
    finished_at = now(),
    rounds = v_round,
    stats = (select jsonb_build_object(
               'tildelinger', count(*),
               'stillinger', (select count(*) from job),
               'under_gulv', (select count(*) from public.job_cutoffs where holders < gulv),
               'min_per_stilling', (select min(holders) from public.job_cutoffs),
               'maks_per_stilling', (select max(holders) from public.job_cutoffs))
             from held)
  where id = v_cycle;

  return v_cycle;
end
$fn$;

-- ---------------------------------------------------------------------------
-- Løpende: en nypublisert stilling fylles straks, uten å fortrenge noen.
-- Nattkjøringen re-optimaliserer.
-- ---------------------------------------------------------------------------

create or replace function public.allocate_new_job(p_job_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.allocations (profile_id, job_id, score, source)
    select m.profile_id, m.job_id, m.score, 'lopende'
    from public.match_scores m
    where m.job_id = p_job_id and m.score >= 60
      and public.free_slots(m.profile_id) > 0
      and not exists (select 1 from public.allocations a
                      where a.job_id = m.job_id and a.profile_id = m.profile_id)
      and not exists (select 1 from public.applications a
                      where a.job_id = m.job_id and a.profile_id = m.profile_id)
    order by m.score desc, m.profile_id
    limit public.job_free_cap(p_job_id);
end
$fn$;

create or replace function public.trg_jobs_allocate()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.status = 'published' then
    perform public.allocate_new_job(new.id);
  end if;
  return null;
end
$fn$;

-- Navnet sorterer etter jobs_recompute, så match_scores finnes når denne kjører.
create trigger jobs_tildel_lopende
  after insert or update on public.jobs
  for each row execute function public.trg_jobs_allocate();

-- ---------------------------------------------------------------------------
-- Søknad krever tildeling. Dette er regelen som stopper 400 på samme stilling.
-- ---------------------------------------------------------------------------

create or replace function public.enforce_application_rules()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  v_status job_status;
  v_score  int;
  v_active int;
begin
  select status into v_status from public.jobs where id = new.job_id;
  if v_status is null or v_status <> 'published' then
    raise exception 'Stillingen er ikke publisert';
  end if;

  if not exists (select 1 from public.allocations
                 where job_id = new.job_id and profile_id = new.profile_id) then
    raise exception 'Du kan bare søke på stillinger du har fått tildelt';
  end if;

  select score into v_score
    from public.match_scores
    where job_id = new.job_id and profile_id = new.profile_id;

  if coalesce(v_score, 0) < 60 then
    raise exception 'Du kan bare søke på stillinger du matcher';
  end if;

  select count(*) into v_active
    from public.applications
    where profile_id = new.profile_id
      and status in ('sendt','sett','intervju');

  if v_active >= 5 then
    raise exception 'Maks 5 aktive søknader';
  end if;

  -- Tildelingen er brukt opp; plassen telles nå som aktiv søknad.
  delete from public.allocations
    where job_id = new.job_id and profile_id = new.profile_id;

  new.score_at_apply := v_score;
  return new;
end
$fn$;

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- Kandidatens tildelte matcher. Et rent oppslag nå, ingen beregning.
create or replace view public.my_matches with (security_invoker = on) as
select
  a.job_id,
  j.title,
  j.description,
  j.kommune,
  j.start_date,
  c.name as company_name,
  c.industry,
  a.score,
  coalesce(m.reasons, '[]'::jsonb) as reasons,
  j.published_at
from public.allocations a
join public.jobs j      on j.id = a.job_id
join public.companies c on c.id = j.company_id
left join public.match_scores m on m.job_id = a.job_id and m.profile_id = a.profile_id
where a.profile_id = auth.uid()
  and j.status = 'published'
order by a.score desc;

-- Stillinger kandidaten er kvalifisert for men ikke fikk fordi lista er full.
create view public.my_missed with (security_invoker = on) as
select
  j.id as job_id,
  j.title,
  c.name as company_name,
  m.score,
  k.cutoff_score,
  k.holders
from public.match_scores m
join public.jobs j        on j.id = m.job_id and j.status = 'published'
join public.companies c   on c.id = j.company_id
join public.job_cutoffs k on k.job_id = m.job_id
where m.profile_id = auth.uid()
  and m.score >= 60
  and k.holders >= k.cap
  and not exists (select 1 from public.allocations a
                  where a.job_id = m.job_id and a.profile_id = auth.uid())
  and not exists (select 1 from public.applications a
                  where a.job_id = m.job_id and a.profile_id = auth.uid())
order by m.score desc;

-- ---------------------------------------------------------------------------
-- Rettigheter og nattkjøring
-- ---------------------------------------------------------------------------

revoke execute on function public.run_allocation()          from anon, authenticated;
revoke execute on function public.allocate_new_job(uuid)    from anon, authenticated;
revoke execute on function public.trg_jobs_allocate()       from anon, authenticated;
revoke execute on function public.free_slots(uuid)          from anon;
revoke execute on function public.job_free_cap(uuid)        from anon;

create extension if not exists pg_cron;
select cron.schedule('jobbo_tildeling', '0 4 * * *', $$select public.run_allocation()$$);
