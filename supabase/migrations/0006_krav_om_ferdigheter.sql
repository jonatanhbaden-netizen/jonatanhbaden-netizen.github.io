-- A candidate who matches NONE of a job's required skills is not a match,
-- whatever the rest of the profile says. Without this a blank profile scores
-- exactly 60 on an undemanding job (0 + 0 + 15 utdanning + 15 erfaring +
-- 15 sted + 10 språk + 5 oppstart) and counts as kvalifisert — which is the
-- very problem Jobbo exists to remove. Treated like the absolute language
-- requirement: score 0, with the reason spelled out.
--
-- Only the closing rule of compute_match changes; every weight is unchanged.
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

  if req_total = 0 then
    p_skills := 35;
    r := r || jsonb_build_object('key','skills','ok',true,
           'text','Ingen spesifikke ferdighetskrav');
  else
    p_skills := 35.0 * req_hit / req_total;
    r := r || jsonb_build_object('key','skills','ok', req_hit = req_total,
           'text', req_hit || ' av ' || req_total || ' påkrevde ferdigheter');
  end if;

  if nice_total = 0 then
    p_nice := 0;
  else
    p_nice := 5.0 * nice_hit / nice_total;
    r := r || jsonb_build_object('key','nice','ok', nice_hit > 0,
           'text', nice_hit || ' av ' || nice_total || ' ønskede ferdigheter');
  end if;

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

  if j.language_required and not lang_ok then
    total := 0;
    r := r || jsonb_build_object('key','ekskludert','ok',false,
           'text','Språkkravet er absolutt for denne stillingen');
  end if;

  -- New in 0006.
  if req_total > 0 and req_hit = 0 then
    total := 0;
    r := r || jsonb_build_object('key','ekskludert','ok',false,
           'text','Mangler alle de påkrevde ferdighetene');
  end if;

  score   := round(total)::int;
  reasons := r;
  return next;
end
$fn$;
