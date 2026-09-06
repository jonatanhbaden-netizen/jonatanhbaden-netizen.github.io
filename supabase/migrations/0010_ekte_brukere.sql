-- ---------------------------------------------------------------------------
-- Klar for ekte brukere: selvregistrering, intervjubooking med tidspunkter,
-- GDPR-eksport og -sletting, synonymer, varslingskø, betalinger og felt for
-- importerte stillinger. Betaling, e-post og import kobles til i Edge
-- Functions; databasen her fungerer uansett om nøklene finnes.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- 1. Registrering: auth.users → profiles eller companies + employer_users,
--    styrt av raw_user_meta_data.rolle fra signUp-kallet.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  cid  uuid;
begin
  if meta->>'rolle' = 'arbeidsgiver' then
    insert into public.companies (name, org_nr, kommune, industry)
    values (coalesce(nullif(meta->>'firma', ''), 'Uten navn'),
            nullif(meta->>'org_nr', ''),
            coalesce(nullif(meta->>'kommune', ''), 'Oslo'),
            nullif(meta->>'bransje', ''))
    returning id into cid;
    insert into public.employer_users (id, company_id, name, email)
    values (new.id, cid, coalesce(nullif(meta->>'navn', ''), new.email), new.email);
  elsif meta->>'rolle' = 'kandidat' then
    insert into public.profiles (id, first_name, last_name, email)
    values (new.id, coalesce(meta->>'fornavn', ''), coalesce(meta->>'etternavn', ''), new.email);
  end if;
  return new;
end
$fn$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- 2. Lukket stilling frigjør kandidatenes plasser.
-- ---------------------------------------------------------------------------
create or replace function public.trg_jobs_allocate()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  if new.status = 'published' then
    perform public.allocate_new_job(new.id);
  else
    delete from public.allocations where job_id = new.id;
  end if;
  return null;
end
$fn$;

-- ---------------------------------------------------------------------------
-- 3. Intervju: arbeidsgiver foreslår tidspunkter, kandidaten velger ett.
-- ---------------------------------------------------------------------------
create type interview_status as enum ('foreslatt', 'bekreftet', 'avlyst');

alter table public.interviews
  alter column scheduled_at drop not null,
  add column proposed_times timestamptz[] not null default '{}',
  add column status interview_status not null default 'foreslatt',
  add column location text;

update public.interviews set status = 'bekreftet' where scheduled_at is not null;

create or replace function public.confirm_interview(p_id uuid, p_time timestamptz)
returns void language plpgsql security definer set search_path = public as $fn$
declare v public.interviews;
begin
  select i.* into v from public.interviews i
  join public.applications a on a.id = i.application_id
  where i.id = p_id and a.profile_id = auth.uid();
  if v.id is null then raise exception 'Fant ikke intervjuet'; end if;
  if v.status <> 'foreslatt' then raise exception 'Intervjuet er allerede avgjort'; end if;
  if not (p_time = any(v.proposed_times)) then raise exception 'Tidspunktet er ikke blant de foreslåtte'; end if;
  update public.interviews set scheduled_at = p_time, status = 'bekreftet' where id = p_id;
end
$fn$;

-- Kandidaten oppdaterer intervjuer bare gjennom confirm_interview.
grant execute on function public.confirm_interview(uuid, timestamptz) to authenticated;
revoke execute on function public.confirm_interview(uuid, timestamptz) from anon;

create or replace view public.job_stats with (security_invoker = on) as
select
  j.id as job_id,
  j.company_id,
  j.title,
  j.status,
  j.kommune,
  j.published_at,
  j.shortlist_cap,
  j.guaranteed_interviews,
  (select count(*) from public.match_scores m
     where m.job_id = j.id and m.score >= 60)               as qualified_count,
  (select count(*) from public.applications a
     where a.job_id = j.id)                                 as application_count,
  (select count(*) from public.applications a
     where a.job_id = j.id and a.status = 'intervju')        as interview_count,
  (select count(*) from public.interviews i
     join public.applications a on a.id = i.application_id
     where a.job_id = j.id and i.status <> 'avlyst')        as booked_interviews
from public.jobs j;

-- ---------------------------------------------------------------------------
-- 4. GDPR: eksport og sletting
-- ---------------------------------------------------------------------------
create or replace function public.delete_my_account()
returns void language plpgsql security definer set search_path = public, auth as $fn$
declare uid uuid := auth.uid(); cid uuid;
begin
  if uid is null then raise exception 'Ikke innlogget'; end if;
  select company_id into cid from public.employer_users where id = uid;
  delete from auth.users where id = uid;
  if cid is not null and not exists (select 1 from public.employer_users where company_id = cid) then
    delete from public.companies where id = cid;
  end if;
end
$fn$;

grant execute on function public.delete_my_account() to authenticated;
revoke execute on function public.delete_my_account() from anon;

-- ---------------------------------------------------------------------------
-- 5. Synonymer: «js» finner JavaScript i søkefeltet. Vokabularet er uendret.
-- ---------------------------------------------------------------------------
create table public.skill_synonyms (
  synonym text primary key,
  skill   text not null references public.skills(name) on delete cascade
);
alter table public.skill_synonyms enable row level security;
create policy skill_synonyms_select on public.skill_synonyms for select to authenticated using (true);
create policy skill_synonyms_select_anon on public.skill_synonyms for select to anon using (true);

insert into public.skill_synonyms (synonym, skill) values
('js','javascript'),('ecmascript','javascript'),('ts','typescript'),('node','nodejs'),
('reactjs','react'),('react.js','react'),('vuejs','vue'),('postgres','postgresql'),
('psql','postgresql'),('k8s','kubernetes'),('c sharp','csharp'),('.net','csharp'),
('dotnet','csharp'),('amazon web services','aws'),('microsoft azure','azure'),
('ci','ci-cd'),('cd','ci-cd'),('devops','ci-cd'),('rest','rest-api'),('api','rest-api'),
('ux','ux-design'),('ui','ux-design'),('design','ux-design'),('agile','scrum'),
('smidig','scrum'),('git hub','git'),('github','git'),('gitlab','git'),('unix','linux'),
('support','brukerstotte'),('helpdesk','brukerstotte'),('it-sikkerhet','informasjonssikkerhet'),
('security','informasjonssikkerhet'),('word','office'),('powerpoint','office'),
('outlook','office'),('kasse','kassaapparat'),('kassa','kassaapparat'),
('kundebehandling','kundeservice'),('service','kundeservice'),('butikk','butikkdrift'),
('varer','varepafylling'),('lager','lagerarbeid'),('truck','truckforer'),
('gaffeltruck','truckforer'),('sjåfør','yrkessjafor'),('sjafor','yrkessjafor'),
('lastebil','yrkessjafor'),('førerkort','forerkort-b'),('forerkort','forerkort-b'),
('bil','forerkort-b'),('kran','kranforer'),('sykepleier','sykepleie'),
('helsefagarbeider','helsefagarbeid'),('omsorg','pleie'),('pleie','pleie'),
('demens','demensomsorg'),('medisin','medisinhandtering'),('sår','sarstell'),
('kokk','matlaging'),('kjøkken','kjokkendrift'),('servitør','servering'),
('kaffe','barista'),('bar','bartender'),('vin','vinkunnskap'),('bakst','konditor'),
('regnskapsfører','regnskap'),('bokføring','bokforing'),('lønn','lonnskjoring'),
('faktura','fakturering'),('budsjett','budsjettering'),('moms','mva'),
('årsregnskap','arsoppgjor'),('tømrer','tommerarbeid'),('snekker','tommerarbeid'),
('rørlegger','rorlegging'),('elektriker','elektroinstallasjon'),('murer','muring'),
('maler','maling'),('sveiser','sveising'),('graver','gravemaskin'),
('stillas','stillasmontering'),('tak','taktekking'),('lærer','klasseledelse'),
('barnehage','barnehagearbeid'),('barn','barneomsorg'),('spesped','spesialpedagogikk'),
('prosjekt','prosjektledelse'),('leder','ledelse'),('teamleder','ledelse'),
('engelsk','kommunikasjon'),('excel-ark','excel'),('regneark','excel');

-- ---------------------------------------------------------------------------
-- 6. Varslingskø. Rader legges i kø av triggere; en Edge Function sender dem
--    hvert femte minutt hvis RESEND_API_KEY finnes. Uten nøkkel blir de liggende.
-- ---------------------------------------------------------------------------
create type notification_status as enum ('venter', 'sendt', 'feilet');

create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  email      text not null,
  subject    text not null,
  body       text not null,
  path       text not null default '/',
  status     notification_status not null default 'venter',
  error      text,
  created_at timestamptz not null default now(),
  sent_at    timestamptz
);
create index notifications_status_idx on public.notifications (status, created_at);
alter table public.notifications enable row level security;
create policy notifications_select_own on public.notifications
  for select to authenticated using (user_id = auth.uid());

create or replace function public.notify(p_user uuid, p_email text, p_subject text, p_body text, p_path text default '/')
returns void language sql security definer set search_path = public as $fn$
  insert into public.notifications (user_id, email, subject, body, path)
  select p_user, p_email, p_subject, p_body, p_path where p_user is not null and p_email is not null
$fn$;

-- Alle arbeidsgivere i et firma får samme varsel.
create or replace function public.notify_company(p_company uuid, p_subject text, p_body text, p_path text default '/')
returns void language sql security definer set search_path = public as $fn$
  insert into public.notifications (user_id, email, subject, body, path)
  select e.id, e.email, p_subject, p_body, p_path from public.employer_users e where e.company_id = p_company
$fn$;

create or replace function public.trg_application_notify()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare j public.jobs; c public.companies; p public.profiles;
begin
  select * into j from public.jobs where id = new.job_id;
  select * into c from public.companies where id = j.company_id;
  select * into p from public.profiles where id = new.profile_id;

  if tg_op = 'INSERT' then
    perform public.notify_company(j.company_id,
      'Ny søker på ' || j.title,
      p.first_name || ' ' || p.last_name || ' har søkt på «' || j.title || '». Se shortlisten for score og begrunnelse.',
      '/employer/stilling.html?id=' || j.id);
  elsif new.status is distinct from old.status then
    if new.status = 'intervju' then
      perform public.notify(p.id, p.email, 'Du er kalt inn til intervju hos ' || c.name,
        c.name || ' vil møte deg om stillingen «' || j.title || '». Velg et tidspunkt som passer.',
        '/kandidat/soknader.html');
    elsif new.status = 'tilbud' then
      perform public.notify(p.id, p.email, 'Du har fått et tilbud fra ' || c.name,
        'Gratulerer! ' || c.name || ' vil tilby deg stillingen «' || j.title || '». De tar kontakt med detaljene.',
        '/kandidat/soknader.html');
    elsif new.status = 'avslag' then
      perform public.notify(p.id, p.email, 'Svar på søknaden din til ' || c.name,
        c.name || ' gikk videre med andre kandidater til «' || j.title || '». Plassen din er frigjort, så du kan søke på en ny match.',
        '/kandidat/matcher.html');
    end if;
  end if;
  return null;
end
$fn$;

create trigger applications_notify
  after insert or update of status on public.applications
  for each row execute function public.trg_application_notify();

create or replace function public.trg_interview_notify()
returns trigger language plpgsql security definer set search_path = public as $fn$
declare a public.applications; j public.jobs; c public.companies; p public.profiles;
begin
  select * into a from public.applications where id = new.application_id;
  select * into j from public.jobs where id = a.job_id;
  select * into c from public.companies where id = j.company_id;
  select * into p from public.profiles where id = a.profile_id;

  if tg_op = 'INSERT' and new.status = 'foreslatt' then
    perform public.notify(p.id, p.email, 'Velg tidspunkt for intervju hos ' || c.name,
      c.name || ' har foreslått ' || cardinality(new.proposed_times) || ' tidspunkter for intervju om «' || j.title || '». Logg inn og velg det som passer.',
      '/kandidat/soknader.html');
  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    if new.status = 'bekreftet' then
      perform public.notify_company(j.company_id,
        p.first_name || ' ' || p.last_name || ' har bekreftet intervju',
        'Intervju om «' || j.title || '» er satt til ' || to_char(new.scheduled_at at time zone 'Europe/Oslo', 'DD.MM.YYYY HH24:MI') || '.',
        '/employer/stilling.html?id=' || j.id);
    elsif new.status = 'avlyst' then
      perform public.notify(p.id, p.email, 'Intervjuet hos ' || c.name || ' er avlyst',
        c.name || ' har avlyst intervjuet om «' || j.title || '».', '/kandidat/soknader.html');
    end if;
  end if;
  return null;
end
$fn$;

create trigger interviews_notify
  after insert or update of status on public.interviews
  for each row execute function public.trg_interview_notify();

-- Nye matcher: én e-post per kandidat, bare for par som er nye siden sist.
create or replace function public.allocate_new_job(p_job_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare j public.jobs; c public.companies;
begin
  select * into j from public.jobs where id = p_job_id;
  select * into c from public.companies where id = j.company_id;

  with nye as (
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
      limit public.job_free_cap(p_job_id)
    returning profile_id, score
  )
  insert into public.notifications (user_id, email, subject, body, path)
    select p.id, p.email, 'Ny match: ' || j.title || ' hos ' || c.name,
           'Du matcher «' || j.title || '» hos ' || c.name || ' med ' || n.score || ' poeng. Stillingen ligger klar blant matchene dine.',
           '/kandidat/matcher.html'
    from nye n join public.profiles p on p.id = n.profile_id;
end
$fn$;

-- Eksport ligger her fordi den leser notifications.
create or replace function public.export_my_data()
returns jsonb language sql stable set search_path = public as $fn$
  select jsonb_build_object(
    'eksportert', now(),
    'profil', (select to_jsonb(p) from public.profiles p where p.id = auth.uid()),
    'arbeidsgiver', (select to_jsonb(e) from public.employer_users e where e.id = auth.uid()),
    'soknader', (select coalesce(jsonb_agg(jsonb_build_object(
        'stilling', j.title, 'firma', c.name, 'status', a.status,
        'score', a.score_at_apply, 'sendt', a.created_at)), '[]'::jsonb)
      from public.applications a
      join public.jobs j on j.id = a.job_id
      join public.companies c on c.id = j.company_id
      where a.profile_id = auth.uid()),
    'intervjuer', (select coalesce(jsonb_agg(to_jsonb(i)), '[]'::jsonb)
      from public.interviews i
      join public.applications a on a.id = i.application_id
      where a.profile_id = auth.uid()),
    'matcher', (select coalesce(jsonb_agg(jsonb_build_object(
        'stilling', j.title, 'score', al.score, 'tildelt', al.created_at)), '[]'::jsonb)
      from public.allocations al join public.jobs j on j.id = al.job_id
      where al.profile_id = auth.uid()),
    'varsler', (select coalesce(jsonb_agg(to_jsonb(n)), '[]'::jsonb)
      from public.notifications n where n.user_id = auth.uid())
  )
$fn$;

grant execute on function public.export_my_data() to authenticated;
revoke execute on function public.export_my_data() from anon;

-- Nattkjøringen varsler om nye par.
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

  -- Én e-post per kandidat som fikk minst én match de ikke hadde fra før.
  insert into public.notifications (user_id, email, subject, body, path)
    select p.id, p.email,
           case when x.n = 1 then 'Du har en ny match på Jobbo'
                else 'Du har ' || x.n || ' nye matcher på Jobbo' end,
           'Nattens fordeling ga deg ' || x.n || ' ' ||
           case when x.n = 1 then 'ny stilling' else 'nye stillinger' end ||
           ' du er kvalifisert for. Logg inn for å se dem og søke.',
           '/kandidat/matcher.html'
    from (select h.profile_id, count(*) as n from held h
          where not exists (select 1 from public.allocations a
                            where a.profile_id = h.profile_id and a.job_id = h.job_id)
          group by h.profile_id) x
    join public.profiles p on p.id = x.profile_id;

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
-- 7. Betalinger. Skrives av Edge Functions med service role.
-- ---------------------------------------------------------------------------
create table public.payments (
  id         uuid primary key default gen_random_uuid(),
  job_id     uuid not null references public.jobs(id) on delete cascade,
  provider   text not null,
  session_id text unique,
  amount_nok int  not null,
  status     text not null default 'venter',
  created_at timestamptz not null default now(),
  paid_at    timestamptz
);
alter table public.payments enable row level security;
create policy payments_select_employer on public.payments
  for select to authenticated
  using (exists (select 1 from public.jobs j
                 where j.id = public.payments.job_id and j.company_id = public.current_company_id()));

-- ---------------------------------------------------------------------------
-- 8. Importerte stillinger (Arbeidsplassen/NAV). Søknaden går til kilden.
-- ---------------------------------------------------------------------------
alter table public.jobs
  add column source       text not null default 'jobbo',
  add column external_url text,
  add column external_id  text unique;

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
  j.published_at,
  j.source,
  j.external_url
from public.allocations a
join public.jobs j      on j.id = a.job_id
join public.companies c on c.id = j.company_id
left join public.match_scores m on m.job_id = a.job_id and m.profile_id = a.profile_id
where a.profile_id = auth.uid()
  and j.status = 'published'
order by a.score desc;

-- ---------------------------------------------------------------------------
-- Rettigheter
-- ---------------------------------------------------------------------------
revoke execute on function public.handle_new_user()                 from anon, authenticated;
revoke execute on function public.notify(uuid, text, text, text, text)        from anon, authenticated;
revoke execute on function public.notify_company(uuid, text, text, text)      from anon, authenticated;
revoke execute on function public.trg_application_notify()          from anon, authenticated;
revoke execute on function public.trg_interview_notify()            from anon, authenticated;
