-- Jobbo demo seed. Runs against an empty database that has migrations
-- 0001–0006 applied. Everything is generated, so re-running from scratch
-- gives the same shape of data (exact rows differ: ids are random).
--
-- Applications are inserted through the production trigger, so the seed is
-- held to the same rules as a real user: score >= 60, published job,
-- max 5 active per candidate.

create extension if not exists pgcrypto with schema extensions;

-- Creates an auth user that can actually sign in. Dropped at the end.
create or replace function public.seed_user(p_email text, p_pw text)
returns uuid language plpgsql security definer set search_path = public, auth, extensions as $fn$
declare uid uuid := gen_random_uuid();
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
    p_email, extensions.crypt(p_pw, extensions.gen_salt('bf')), now(), now(), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, '', '', '', '');
  insert into auth.identities (provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at)
  values (uid::text, uid,
    jsonb_build_object('sub', uid::text, 'email', p_email, 'email_verified', true),
    'email', now(), now(), now());
  return uid;
end
$fn$;

-- 40 fictional Oslo-area companies, 4–5 per bransje.
insert into public.companies (name, industry, kommune) values
('Grünerløkka Matsenter','butikk','Oslo'),('Storo Sport AS','butikk','Oslo'),
('Majorstuen Interiør','butikk','Oslo'),('Sandvika Elektrokjede','butikk','Bærum'),
('Lillestrøm Byggvarehus','butikk','Lillestrøm'),
('Sagene Omsorgssenter','helse','Oslo'),('Nordstrand Bo- og Servicesenter','helse','Oslo'),
('Asker Hjemmetjeneste AS','helse','Asker'),('Vitalis Helsebemanning','helse','Oslo'),
('Lørenskog Sykehjem','helse','Lørenskog'),
('Nordvik Teknologi','it','Oslo'),('Fjordkode AS','it','Oslo'),
('Skyra Systems','it','Bærum'),('Datastuen Konsulent','it','Oslo'),
('Bitfjell Software','it','Drammen'),
('Ekeberg Bygg og Anlegg','bygg','Oslo'),('Romerike Entreprenør AS','bygg','Lillestrøm'),
('Holmen Elektro','bygg','Asker'),('Grorud Rørservice','bygg','Oslo'),
('Follo Tak og Fasade','bygg','Nordre Follo'),
('Kvist Regnskap AS','okonomi','Oslo'),('Sentrum Økonomibyrå','okonomi','Oslo'),
('Bærum Revisjon DA','okonomi','Bærum'),('Nordre Lønnstjenester','okonomi','Lillestrøm'),
('Alfa Controlling AS','okonomi','Oslo'),
('Alnabru Lager og Logistikk','logistikk','Oslo'),('Gardermoen Terminaldrift','logistikk','Ullensaker'),
('Oslo Distribusjon AS','logistikk','Oslo'),('Rælingen Transport','logistikk','Rælingen'),
('Havnelageret Nord','logistikk','Oslo'),
('Bjølsen Barnehage','skole','Oslo'),('Torshov Kultursenter SFO','skole','Oslo'),
('Nesodden Oppvekst','skole','Nesodden'),('Eventyrskogen Barnehage','skole','Bærum'),
('Løren Læringssenter','skole','Oslo'),
('Kafé Skogen','restaurant','Oslo'),('Restaurant Bryggekanten','restaurant','Oslo'),
('Bar Nordvest','restaurant','Oslo'),('Sandvika Storkjøkken','restaurant','Bærum'),
('Kanelbolle Bakeri og Kafé','restaurant','Oslo');

-- 60 jobs: two for the first 20 companies, one for the rest. Required skills
-- are drawn from the company's own bransje so matching has real signal.
with numbered as (
  select c.id, c.industry, c.kommune, row_number() over (order by c.name) as rn
  from public.companies c
),
expanded as (
  select n.*, g as k from numbered n
  cross join generate_series(1, case when n.rn <= 20 then 2 else 1 end) g
),
titled as (
  select e.*,
    (case e.industry
      when 'butikk'     then array['Butikkmedarbeider','Butikkleder','Kundeveileder','Salgskonsulent']
      when 'helse'      then array['Helsefagarbeider','Sykepleier','Pleiemedarbeider','Miljøarbeider']
      when 'it'         then array['Frontendutvikler','Backendutvikler','Systemutvikler','IT-konsulent']
      when 'bygg'       then array['Tømrer','Elektriker','Rørlegger','Anleggsarbeider']
      when 'okonomi'    then array['Regnskapsmedarbeider','Controller','Lønnsmedarbeider','Økonomikonsulent']
      when 'logistikk'  then array['Lagermedarbeider','Truckfører','Logistikkoordinator','Terminalarbeider']
      when 'skole'      then array['Barnehageassistent','Barnehagelærer','SFO-medarbeider','Miljøterapeut']
      when 'restaurant' then array['Kokk','Servitør','Barista','Kjøkkenassistent']
     end)[1 + ((e.rn * 3 + e.k) % 4)] as title,
    ((e.rn * 7 + e.k * 3) % 10) as v
  from expanded e
)
insert into public.jobs (company_id, title, description, required_skills, nice_skills,
  education_min, experience_min, experience_max, kommune, norsk_min, engelsk_min,
  language_required, start_date, status, published_at, shortlist_cap, guaranteed_interviews)
select t.id, t.title,
  'Vi søker en ' || lower(t.title) || ' til vårt team i ' || t.kommune ||
  '. Du blir en del av en arbeidsplass med god opplæring, ryddige vilkår og ' ||
  'mulighet for å utvikle deg videre. Vi legger vekt på samarbeid og faglig kvalitet.',
  (select array_agg(s.name) from (select name from public.skills where category = t.industry
     order by md5(name || t.rn::text || t.k::text) limit 3 + (t.v % 3)) s),
  (select array_agg(s.name) from (select name from public.skills where category = 'generelt'
     order by md5(name || t.rn::text || t.k::text || 'n') limit 2) s),
  (case when t.industry in ('it','okonomi') and t.v > 5 then 'bachelor'::education_level
        when t.industry in ('helse','skole') and t.v > 6 then 'fagbrev'::education_level
        when t.v > 7 then 'videregaende'::education_level
        else 'grunnskole'::education_level end),
  (case when t.v > 6 then 2 when t.v > 3 then 1 else 0 end),
  (case when t.v > 6 then 10 else 99 end),
  t.kommune,
  (case when t.v > 2 then 'god'::language_level else 'grunnleggende'::language_level end),
  (case when t.industry = 'it' then 'god'::language_level else 'ingen'::language_level end),
  (t.industry in ('helse','skole') and t.v > 5),
  (current_date + ((t.v * 10) || ' days')::interval)::date,
  (case when t.rn * 2 + t.k <= 52 then 'published'::job_status else 'draft'::job_status end),
  (case when t.rn * 2 + t.k <= 52 then now() - ((t.v || ' days')::interval) else null end),
  10, 10
from titled t;

-- 300 candidates. The recompute trigger is switched off for the bulk insert and
-- the whole match matrix is computed in one set-based pass afterwards.
alter table public.profiles disable trigger profiles_recompute;

with gen as (
  select n,
    (array['Emma','Nora','Olivia','Ella','Sofie','Ingrid','Maja','Sara','Leah','Anna',
           'Frida','Astrid','Julie','Thea','Hanna','Amalie','Live','Vilde','Mia','Kaja',
           'Jakob','Emil','Noah','Oliver','William','Lucas','Filip','Aksel','Matheo','Theodor',
           'Henrik','Magnus','Elias','Isak','Kasper','Sander','Odin','Jonas','Mathias','Even'
     ])[1 + (n % 40)] as fornavn,
    (array['Hansen','Johansen','Olsen','Larsen','Andersen','Pedersen','Nilsen','Kristiansen',
           'Jensen','Karlsen','Johnsen','Pettersen','Eriksen','Berg','Haugen','Hagen',
           'Johannessen','Andreassen','Jacobsen','Halvorsen','Dahl','Henriksen','Lund',
           'Sørensen','Jørgensen','Moen','Bakken','Strand','Solberg','Ruud'
     ])[1 + ((n * 7) % 30)] as etternavn,
    (array['Oslo','Oslo','Oslo','Oslo','Oslo','Oslo','Oslo','Oslo','Oslo','Oslo',
           'Bærum','Asker','Lillestrøm','Lørenskog','Nordre Follo','Ullensaker',
           'Rælingen','Nesodden','Drammen','Bærum'])[1 + (n % 20)] as kommune,
    (array['butikk','helse','it','bygg','okonomi','logistikk','skole','restaurant'
     ])[1 + (n % 8)] as bransje,
    (n % 13) as yrs,
    ((n * 5) % 10) as v
  from generate_series(1, 300) n
),
gen2 as (
  select g.*, lower(translate(g.fornavn || '.' || g.etternavn, 'æøåÆØÅ', 'aoaAOA'))
    || '.' || g.n || '@example.no' as email
  from gen g
)
insert into public.profiles (id, email, first_name, last_name, phone, kommune,
  acceptable_kommuner, highest_education, education, experience, skills,
  norsk, engelsk, available_from, about)
select
  public.seed_user(g.email, 'jobbo-demo'), g.email, g.fornavn, g.etternavn,
  '9' || lpad(((g.n * 137) % 10000000)::text, 7, '0'),
  g.kommune,
  case when g.kommune = 'Oslo' then array['Bærum','Lørenskog'] else array['Oslo'] end,
  (case
     when g.bransje in ('it','okonomi') and g.v > 6 then 'master'
     when g.bransje in ('it','okonomi') and g.v > 3 then 'bachelor'
     when g.bransje in ('helse','skole') and g.v > 5 then 'fagbrev'
     when g.bransje = 'bygg' and g.v > 4 then 'fagbrev'
     when g.v > 2 then 'videregaende'
     else 'grunnskole' end)::education_level,
  jsonb_build_array(jsonb_build_object(
    'title', case g.bransje
       when 'it' then 'Bachelor i informatikk' when 'okonomi' then 'Bachelor i økonomi og administrasjon'
       when 'helse' then 'Helse- og oppvekstfag' when 'skole' then 'Barne- og ungdomsarbeiderfag'
       when 'bygg' then 'Bygg- og anleggsteknikk' when 'restaurant' then 'Restaurant- og matfag'
       when 'logistikk' then 'Transport og logistikk' else 'Salg, service og reiseliv' end,
    'institution', case when g.v > 5 then 'OsloMet' else 'Elvebakken videregående skole' end,
    'from', (current_date - ((g.yrs + 3) * 365))::text,
    'to', (current_date - (g.yrs * 365))::text, 'description', '')),
  case
    when g.yrs = 0 then '[]'::jsonb
    when g.yrs <= 3 then jsonb_build_array(jsonb_build_object(
      'title', initcap(g.bransje) || 'medarbeider', 'company', 'Nordvik ' || initcap(g.bransje) || ' AS',
      'from', (current_date - (g.yrs * 365))::text, 'to', null, 'description', ''))
    else jsonb_build_array(
      jsonb_build_object('title', initcap(g.bransje) || 'assistent',
        'company', 'Bergli ' || initcap(g.bransje) || ' AS',
        'from', (current_date - (g.yrs * 365))::text,
        'to', (current_date - ((g.yrs - 2) * 365))::text, 'description', ''),
      jsonb_build_object('title', initcap(g.bransje) || 'medarbeider',
        'company', 'Nordvik ' || initcap(g.bransje) || ' AS',
        'from', (current_date - ((g.yrs - 2) * 365))::text, 'to', null, 'description', ''))
  end,
  (select array_agg(s.name) from (select name from public.skills where category = g.bransje
     order by md5(name || g.n::text) limit 5 + (g.n % 5)) s)
  || (select array_agg(s.name) from (select name from public.skills where category = 'generelt'
     order by md5(name || g.n::text || 'g') limit 2) s),
  (case when g.v > 7 then 'god' when g.v > 1 then 'flytende' else 'morsmal' end)::language_level,
  (case when g.v > 7 then 'grunnleggende' when g.v > 4 then 'god' else 'flytende' end)::language_level,
  (current_date + ((g.v * 7) || ' days')::interval)::date,
  'Erfaren og strukturert ' || g.bransje || 'medarbeider fra ' || g.kommune ||
  '. Trives godt i team og er opptatt av å levere kvalitet.'
from gen2 g;

alter table public.profiles enable trigger profiles_recompute;

insert into public.match_scores (job_id, profile_id, score, reasons, computed_at)
select j.id, p.id, c.score, c.reasons, now()
from public.jobs j cross join public.profiles p
cross join lateral public.compute_match(j, p) c
where j.status = 'published'
on conflict (job_id, profile_id) do update
  set score = excluded.score, reasons = excluded.reasons, computed_at = now();

-- Roughly half the candidates apply, to 1–4 jobs each, best match first.
insert into public.applications (job_id, profile_id, created_at)
select job_id, profile_id, now() - ((rn * 3 + (abs(h) % 11)) || ' days')::interval
from (
  select m.job_id, m.profile_id,
    row_number() over (partition by m.profile_id order by m.score desc) as rn,
    ('x' || substr(md5(m.profile_id::text), 1, 8))::bit(32)::int as h
  from public.match_scores m
  join public.jobs j on j.id = m.job_id and j.status = 'published'
  where m.score >= 60
) t
where abs(h) % 10 < 5 and rn <= (abs(h) % 4) + 1;

-- Demo employer 1: three published jobs with full shortlists.
insert into public.jobs (company_id, title, description, required_skills, nice_skills,
  education_min, experience_min, experience_max, kommune, norsk_min, engelsk_min,
  language_required, start_date, status, published_at)
select c.id, 'Butikkmedarbeider deltid',
  'Vi søker en butikkmedarbeider til deltidsstilling på Grünerløkka. Du får opplæring i kasse, varepåfylling og kundeveiledning. Passer godt for deg som vil kombinere jobb med studier.',
  array['kundeservice','kassaapparat','varepafylling'], array['samarbeid','tidsstyring'],
  'grunnskole', 0, 99, 'Oslo', 'grunnleggende', 'ingen', false,
  (current_date + 21), 'published', now() - interval '4 days'
from public.companies c where c.name = 'Grünerløkka Matsenter';

update public.jobs set status = 'published',
  published_at = coalesce(published_at, now() - interval '9 days')
where company_id = (select id from public.companies where name = 'Grünerløkka Matsenter');

-- Demo employer 2 keeps exactly one draft, for the live publish moment.
update public.jobs set status = 'draft', published_at = null
where company_id = (select id from public.companies where name = 'Storo Sport AS');
delete from public.jobs
where company_id = (select id from public.companies where name = 'Storo Sport AS')
  and id not in (select id from public.jobs
    where company_id = (select id from public.companies where name = 'Storo Sport AS') limit 1);

insert into public.employer_users (id, company_id, name, email)
select public.seed_user('arbeidsgiver1@jobbo.demo','jobbo-demo'), c.id, 'Marte Solheim','arbeidsgiver1@jobbo.demo'
from public.companies c where c.name = 'Grünerløkka Matsenter';
insert into public.employer_users (id, company_id, name, email)
select public.seed_user('arbeidsgiver2@jobbo.demo','jobbo-demo'), c.id, 'Jonas Wik','arbeidsgiver2@jobbo.demo'
from public.companies c where c.name = 'Storo Sport AS';

-- Demo candidate: deliberately half-filled, so completing the profile on stage
-- makes matches appear where there were none.
insert into public.profiles (id, email, first_name, last_name, phone, kommune,
  acceptable_kommuner, highest_education, education, experience, skills,
  norsk, engelsk, available_from, about)
values (public.seed_user('kandidat@jobbo.demo','jobbo-demo'), 'kandidat@jobbo.demo',
  'Sofie','Lindberg','91234567','Oslo', array['Bærum'], 'videregaende',
  '[]'::jsonb, '[]'::jsonb, '{}', 'morsmal', 'god', current_date, null);

-- Fill the demo employer's shortlists so there is a real venteliste to show.
with cand as (
  select m.job_id, m.profile_id, m.score,
    row_number() over (partition by m.profile_id order by m.score desc) as rp
  from public.match_scores m
  join public.jobs j on j.id = m.job_id
  where j.company_id = (select id from public.companies where name = 'Grünerløkka Matsenter')
    and m.score >= 60
    and not exists (select 1 from public.applications a where a.profile_id = m.profile_id)
),
picked as (
  select job_id, profile_id, score,
    row_number() over (partition by job_id order by score desc) as rj
  from cand where rp = 1
)
insert into public.applications (job_id, profile_id, created_at)
select job_id, profile_id, now() - ((rj * 2) || ' days')::interval from picked where rj <= 15;

-- A spread of statuses, standing in for employer actions that already happened.
update public.applications a set status = 'sett'
where a.status = 'sendt' and ('x' || substr(md5(a.id::text),1,8))::bit(32)::int % 10 in (0,1,2);
update public.applications a set status = 'intervju'
where a.status = 'sett' and ('x' || substr(md5(a.id::text||'i'),1,8))::bit(32)::int % 10 in (0,1,2,3);
update public.applications a set status = 'tilbud'
where a.status = 'intervju' and ('x' || substr(md5(a.id::text||'t'),1,8))::bit(32)::int % 10 in (0,1);
update public.applications a set status = 'avslag'
where a.status = 'sendt' and ('x' || substr(md5(a.id::text||'a'),1,8))::bit(32)::int % 20 = 0;

insert into public.interviews (application_id, scheduled_at, notes)
select a.id, now() + ((row_number() over (order by a.created_at)) || ' days')::interval,
       'Førstegangsintervju'
from public.applications a where a.status in ('intervju','tilbud');

drop function if exists public.seed_user(text, text);
