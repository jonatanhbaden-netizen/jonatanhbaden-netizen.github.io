-- En kandidat som fyller ut profilen skal se matcher med en gang, ikke
-- klokka 04. Speilbildet av allocate_new_job: fyll kandidatens ledige
-- plasser fra stillinger med ledig tak, best score først. Fortrenger ingen.

create or replace function public.allocate_profile(p_profile_id uuid)
returns void language plpgsql security definer set search_path = public as $fn$
begin
  insert into public.allocations (profile_id, job_id, score, source)
    select m.profile_id, m.job_id, m.score, 'lopende'
    from public.match_scores m
    join public.jobs j on j.id = m.job_id and j.status = 'published'
    where m.profile_id = p_profile_id and m.score >= 60
      and public.job_free_cap(m.job_id) > 0
      and not exists (select 1 from public.allocations a
                      where a.job_id = m.job_id and a.profile_id = m.profile_id)
      and not exists (select 1 from public.applications a
                      where a.job_id = m.job_id and a.profile_id = m.profile_id)
    order by m.score desc, m.job_id
    limit public.free_slots(p_profile_id);
end
$fn$;

create or replace function public.trg_profiles_allocate()
returns trigger language plpgsql security definer set search_path = public as $fn$
begin
  perform public.allocate_profile(new.id);
  return null;
end
$fn$;

-- Navnet sorterer etter profiles_recompute, så match_scores er ferske.
create trigger profiles_tildel_lopende
  after insert or update on public.profiles
  for each row execute function public.trg_profiles_allocate();

revoke execute on function public.allocate_profile(uuid)   from anon, authenticated;
revoke execute on function public.trg_profiles_allocate()  from anon, authenticated;
