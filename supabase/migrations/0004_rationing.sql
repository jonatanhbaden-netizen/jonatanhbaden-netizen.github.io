-- ---------------------------------------------------------------------------
-- Rationing — the mechanic that makes "10 kvalifiserte, ikke 400" true.
-- Enforced in the database, not only in the UI, so the seed generator and any
-- future client are held to the same rules.
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

  -- Audit snapshot. The shortlist ranks on the live score, not this one.
  new.score_at_apply := v_score;
  return new;
end
$fn$;

create trigger applications_enforce_rules
  before insert on public.applications
  for each row execute function public.enforce_application_rules();

create or replace function public.touch_application()
returns trigger language plpgsql as $fn$
begin
  new.updated_at := now();
  return new;
end
$fn$;

create trigger applications_touch
  before update on public.applications
  for each row execute function public.touch_application();

-- ---------------------------------------------------------------------------
-- Views
-- ---------------------------------------------------------------------------

-- The candidate's 3-5 job options. Top 5 published matches at or above the
-- kvalifisert threshold that they have not already applied to.
create view public.my_matches with (security_invoker = on) as
select
  m.job_id,
  j.title,
  j.description,
  j.kommune,
  j.start_date,
  c.name as company_name,
  c.industry,
  m.score,
  m.reasons,
  j.published_at
from public.match_scores m
join public.jobs j      on j.id = m.job_id
join public.companies c on c.id = j.company_id
where m.profile_id = auth.uid()
  and j.status = 'published'
  and m.score >= 60
  and not exists (
    select 1 from public.applications a
    where a.job_id = m.job_id and a.profile_id = auth.uid()
  )
order by m.score desc
limit 5;

-- The employer's shortlist. Ranked by the LIVE score, so a candidate who
-- improves their profile moves up. Rows beyond shortlist_cap stay visible as
-- "Venteliste (n)" — they are never rejected automatically.
create view public.job_shortlist with (security_invoker = on) as
select
  x.*,
  (x.rank <= x.shortlist_cap) as on_shortlist
from (
  select
    a.id             as application_id,
    a.job_id,
    a.profile_id,
    a.status,
    a.created_at,
    a.score_at_apply,
    p.first_name,
    p.last_name,
    p.kommune,
    p.highest_education,
    coalesce(m.score, 0)              as score,
    coalesce(m.reasons, '[]'::jsonb)  as reasons,
    j.shortlist_cap,
    j.guaranteed_interviews,
    row_number() over (
      partition by a.job_id
      order by coalesce(m.score, 0) desc, a.created_at asc
    ) as rank
  from public.applications a
  join public.jobs j     on j.id = a.job_id
  join public.profiles p on p.id = a.profile_id
  left join public.match_scores m
    on m.job_id = a.job_id and m.profile_id = a.profile_id
) x;

-- Per-job counters for the employer dashboard:
-- "47 kvalifiserte matchet · 12 har søkt · du ser de 10 beste"
create view public.job_stats with (security_invoker = on) as
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
     where a.job_id = j.id)                                 as booked_interviews
from public.jobs j;
