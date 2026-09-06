-- En kandidat som lagrer profilen skal få plass med en gang hvis scoren slår
-- laveste *ventende* tildeling på en full stilling — akkurat som nattkjøringen
-- ville gjort. Søknader fortrenges aldri; bare tildelinger ingen har brukt.
create or replace function public.allocate_profile(p_profile_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
declare m record; v_lavest record;
begin
  for m in
    select ms.job_id, ms.score
    from public.match_scores ms
    join public.jobs j on j.id = ms.job_id and j.status = 'published'
    where ms.profile_id = p_profile_id and ms.score >= 60
      and not exists (select 1 from public.allocations a
                      where a.job_id = ms.job_id and a.profile_id = p_profile_id)
      and not exists (select 1 from public.applications a
                      where a.job_id = ms.job_id and a.profile_id = p_profile_id)
    order by ms.score desc, ms.job_id
  loop
    exit when public.free_slots(p_profile_id) <= 0;

    if public.job_free_cap(m.job_id) > 0 then
      insert into public.allocations (profile_id, job_id, score, source)
      values (p_profile_id, m.job_id, m.score, 'lopende');
    else
      select a.profile_id, a.score into v_lavest
      from public.allocations a where a.job_id = m.job_id
      order by a.score asc, a.profile_id desc limit 1;
      if v_lavest.profile_id is not null and m.score > v_lavest.score then
        delete from public.allocations
        where job_id = m.job_id and profile_id = v_lavest.profile_id;
        insert into public.allocations (profile_id, job_id, score, source)
        values (p_profile_id, m.job_id, m.score, 'lopende');
      end if;
    end if;
  end loop;
end
$fn$;
revoke execute on function public.allocate_profile(uuid) from public, anon, authenticated;

-- Forklaringen regnes live fra tildelingene, ikke fra forrige nattkjøring.
-- cutoff_score = 0 betyr at stillingen er full av søknader, ikke tildelinger.
create or replace view public.my_missed with (security_invoker = on) as
select
  j.id as job_id,
  j.title,
  c.name as company_name,
  m.score,
  coalesce((select min(a.score) from public.allocations a where a.job_id = j.id), 0) as cutoff_score,
  (select count(*) from public.allocations a where a.job_id = j.id)::int as holders
from public.match_scores m
join public.jobs j      on j.id = m.job_id and j.status = 'published'
join public.companies c on c.id = j.company_id
where m.profile_id = auth.uid()
  and m.score >= 60
  and public.job_free_cap(j.id) = 0
  and not exists (select 1 from public.allocations a
                  where a.job_id = m.job_id and a.profile_id = auth.uid())
  and not exists (select 1 from public.applications a
                  where a.job_id = m.job_id and a.profile_id = auth.uid())
order by m.score desc;
