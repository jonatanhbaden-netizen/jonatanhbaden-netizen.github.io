-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

create or replace function public.education_rank(l education_level)
returns int language sql immutable as $fn$
  select case l
    when 'grunnskole'   then 1
    when 'videregaende' then 2
    when 'fagbrev'      then 3
    when 'bachelor'     then 4
    when 'master'       then 5
    when 'phd'          then 6
  end
$fn$;

create or replace function public.education_label(l education_level)
returns text language sql immutable as $fn$
  select case l
    when 'grunnskole'   then 'grunnskole'
    when 'videregaende' then 'videregående'
    when 'fagbrev'      then 'fagbrev'
    when 'bachelor'     then 'bachelorgrad'
    when 'master'       then 'mastergrad'
    when 'phd'          then 'doktorgrad'
  end
$fn$;

create or replace function public.language_label(l language_level)
returns text language sql immutable as $fn$
  select case l
    when 'ingen'         then 'ingen'
    when 'grunnleggende' then 'grunnleggende'
    when 'god'           then 'god'
    when 'flytende'      then 'flytende'
    when 'morsmal'       then 'morsmål'
  end
$fn$;

-- Sum of all experience periods in years. `to` = null means "still there".
-- stable, not immutable, because an open period is measured against today.
create or replace function public.total_experience_years(experience jsonb)
returns numeric language sql stable as $fn$
  select round(coalesce(sum(
    greatest(0, (coalesce(nullif(e->>'to','')::date, current_date) - (e->>'from')::date))
  ), 0) / 365.25, 2)
  from jsonb_array_elements(coalesce(experience, '[]'::jsonb)) e
  where coalesce(e->>'from', '') <> ''
$fn$;

-- Norwegian decimal comma, one decimal place: 3.5 -> '3,5'
create or replace function public.nb_num(n numeric)
returns text language sql immutable as $fn$
  select replace(to_char(round(n, 1), 'FM999999990.0'), '.', ',')
$fn$;

-- ---------------------------------------------------------------------------
-- compute_match — deterministic, explainable, weights sum to 100
--
--   påkrevde ferdigheter 35 | ønskede 5 | utdanning 15 | erfaring 15
--   sted 15 | språk 10 | oppstart 5
--
-- Every component contributes a {key, ok, text} entry to `reasons`, in
-- Norwegian, including when the language requirement hard-excludes the
-- candidate — the score becomes 0 but the explanation is still complete.
-- Nothing here rejects anyone: only an employer changes an application status.
-- ---------------------------------------------------------------------------
create or replace function public.compute_match(j public.jobs, p public.profiles)
returns table (score int, reasons jsonb)
language plpgsql stable as $fn$
declare
  req_total  int := coalesce(cardinality(j.required_skills), 0);
  nice_total int := coalesce(cardinality(j.nice_skills), 0);
  req_hit    int := 0;
  nice_hit   int := 0;
  p_skills numeric := 0; p_nice  numeric := 0; p_edu   numeric := 0;
  p_exp    numeric := 0; p_sted  numeric := 0; p_sprak numeric := 0;
  p_start  numeric := 0;
  yrs        numeric;
  cand_rank  int;
  need_rank  int;
  lang_ok    boolean;
  days_late  int;
  r          jsonb := '[]'::jsonb;
  total      numeric;
begin
  select count(*) into req_hit
    from unnest(coalesce(j.required_skills, '{}')) s
    where s = any(coalesce(p.skills, '{}'));

  select count(*) into nice_hit
    from unnest(coalesce(j.nice_skills, '{}')) s
    where s = any(coalesce(p.skills, '{}'));

  -- Påkrevde ferdigheter (35)
  if req_total = 0 then
    p_skills := 35;
    r := r || jsonb_build_object('key','skills','ok',true,
           'text','Ingen spesifikke ferdighetskrav');
  else
    p_skills := 35.0 * req_hit / req_total;
    r := r || jsonb_build_object('key','skills','ok', req_hit = req_total,
           'text', req_hit || ' av ' || req_total || ' påkrevde ferdigheter');
  end if;

  -- Ønskede ferdigheter (5)
  if nice_total = 0 then
    p_nice := 0;
  else
    p_nice := 5.0 * nice_hit / nice_total;
    r := r || jsonb_build_object('key','nice','ok', nice_hit > 0,
           'text', nice_hit || ' av ' || nice_total || ' ønskede ferdigheter');
  end if;

  -- Utdanning (15): på nivå eller over = 15, ett nivå under = 7, ellers 0
  cand_rank := public.education_rank(p.highest_education);
  need_rank := public.education_rank(j.education_min);
  if cand_rank >= need_rank then
    p_edu := 15;
    r := r || jsonb_build_object('key','utdanning','ok',true,
           'text','Har ' || public.education_label(p.highest_education));
  elsif cand_rank = need_rank - 1 then
    p_edu := 7;
    r := r || jsonb_build_object('key','utdanning','ok',false,
           'text','Ett nivå under kravet ' || public.education_label(j.education_min));
  else
    p_edu := 0;
    r := r || jsonb_build_object('key','utdanning','ok',false,
           'text','Krever ' || public.education_label(j.education_min));
  end if;

  -- Erfaring (15)
  yrs := public.total_experience_years(p.experience);
  if yrs >= j.experience_min and yrs <= j.experience_max then
    p_exp := 15;
    r := r || jsonb_build_object('key','erfaring','ok',true,
           'text', public.nb_num(yrs) || ' års erfaring');
  elsif yrs < j.experience_min then
    p_exp := case when j.experience_min = 0 then 15
                  else 15.0 * yrs / j.experience_min end;
    r := r || jsonb_build_object('key','erfaring','ok',false,
           'text', public.nb_num(yrs) || ' av ' || j.experience_min || ' års erfaring');
  else
    p_exp := 10;
    r := r || jsonb_build_object('key','erfaring','ok',true,
           'text','Mer erfaring enn kravet (' || public.nb_num(yrs) || ' år)');
  end if;

  -- Sted (15)
  if p.kommune is not null and p.kommune = j.kommune then
    p_sted := 15;
    r := r || jsonb_build_object('key','sted','ok',true,'text','Bor i ' || j.kommune);
  elsif j.kommune = any(coalesce(p.acceptable_kommuner, '{}')) then
    p_sted := 10;
    r := r || jsonb_build_object('key','sted','ok',true,'text','Åpen for jobb i ' || j.kommune);
  else
    p_sted := 0;
    r := r || jsonb_build_object('key','sted','ok',false,
           'text','Stillingen er i ' || j.kommune ||
                  coalesce(', bor i ' || p.kommune, ''));
  end if;

  -- Språk (10)
  lang_ok := p.norsk >= j.norsk_min and p.engelsk >= j.engelsk_min;
  if lang_ok then
    p_sprak := 10;
    r := r || jsonb_build_object('key','sprak','ok',true,
           'text','Norsk: ' || public.language_label(p.norsk) ||
                  ', engelsk: ' || public.language_label(p.engelsk));
  else
    p_sprak := 0;
    r := r || jsonb_build_object('key','sprak','ok',false,
           'text','Krever norsk ' || public.language_label(j.norsk_min) ||
                  ' og engelsk ' || public.language_label(j.engelsk_min));
  end if;

  -- Oppstart (5)
  if j.start_date is null or p.available_from is null
     or p.available_from <= j.start_date then
    p_start := 5;
    r := r || jsonb_build_object('key','oppstart','ok',true,'text','Kan starte til avtalt tid');
  else
    days_late := p.available_from - j.start_date;
    if days_late <= 30 then
      p_start := 3;
      r := r || jsonb_build_object('key','oppstart','ok',true,
             'text','Tilgjengelig ' || days_late || ' dager etter ønsket oppstart');
    else
      p_start := 0;
      r := r || jsonb_build_object('key','oppstart','ok',false,
             'text','Tilgjengelig først ' || to_char(p.available_from, 'DD.MM.YYYY'));
    end if;
  end if;

  total := p_skills + p_nice + p_edu + p_exp + p_sted + p_sprak + p_start;

  -- Hard exclude: språk er absolutt krav for denne stillingen
  if j.language_required and not lang_ok then
    total := 0;
    r := r || jsonb_build_object('key','ekskludert','ok',false,
           'text','Språkkravet er absolutt for denne stillingen');
  end if;

  score   := round(total)::int;
  reasons := r;
  return next;
end
$fn$;

-- Convenience overload used by callers that only have ids.
create or replace function public.compute_match(p_job_id uuid, p_profile_id uuid)
returns table (score int, reasons jsonb)
language plpgsql stable as $fn$
declare j public.jobs; p public.profiles;
begin
  select * into j from public.jobs     where id = p_job_id;
  select * into p from public.profiles where id = p_profile_id;
  if j.id is null or p.id is null then return; end if;
  return query select * from public.compute_match(j, p);
end
$fn$;

-- ---------------------------------------------------------------------------
-- Recompute
-- ---------------------------------------------------------------------------

create or replace function public.recompute_job_matches(p_job_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare j public.jobs; p public.profiles; s int; rs jsonb;
begin
  select * into j from public.jobs where id = p_job_id;
  if j.id is null or j.status <> 'published' then
    delete from public.match_scores where job_id = p_job_id;
    return;
  end if;
  for p in select * from public.profiles loop
    select c.score, c.reasons into s, rs from public.compute_match(j, p) c;
    insert into public.match_scores (job_id, profile_id, score, reasons, computed_at)
    values (j.id, p.id, s, rs, now())
    on conflict (job_id, profile_id)
      do update set score = excluded.score, reasons = excluded.reasons, computed_at = now();
  end loop;
end
$fn$;

create or replace function public.recompute_profile_matches(p_profile_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare j public.jobs; p public.profiles; s int; rs jsonb;
begin
  select * into p from public.profiles where id = p_profile_id;
  if p.id is null then return; end if;
  for j in select * from public.jobs where status = 'published' loop
    select c.score, c.reasons into s, rs from public.compute_match(j, p) c;
    insert into public.match_scores (job_id, profile_id, score, reasons, computed_at)
    values (j.id, p.id, s, rs, now())
    on conflict (job_id, profile_id)
      do update set score = excluded.score, reasons = excluded.reasons, computed_at = now();
  end loop;
end
$fn$;

create or replace function public.trg_jobs_recompute()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  perform public.recompute_job_matches(new.id);
  return null;
end
$fn$;

create or replace function public.trg_profiles_recompute()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  perform public.recompute_profile_matches(new.id);
  return null;
end
$fn$;

create trigger jobs_recompute
  after insert or update on public.jobs
  for each row execute function public.trg_jobs_recompute();

create trigger profiles_recompute
  after insert or update on public.profiles
  for each row execute function public.trg_profiles_recompute();
