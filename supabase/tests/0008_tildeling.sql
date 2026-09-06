-- pgTAP for 0008_tildeling. Kjøres etter run_allocation() via execute_sql.
begin;
select plan(5);

-- 1. Ingen stilling over eksponeringstaket
select is(
  (select count(*) from (
     select a.job_id
     from public.allocations a join public.jobs j on j.id = a.job_id
     group by a.job_id, j.shortlist_cap
     having count(*) > j.shortlist_cap * 2
              - (select count(*) from public.applications x where x.job_id = a.job_id)
  ) x),
  0::bigint, 'ingen stilling over cap');

-- 2. Ingen kandidat over 5 (aktive søknader + ventende tildelinger)
select is(
  (select count(*) from (
     select p.id
     from public.profiles p
     where (select count(*) from public.applications a
             where a.profile_id = p.id and a.status in ('sendt','sett','intervju'))
         + (select count(*) from public.allocations a where a.profile_id = p.id) > 5
  ) x),
  0::bigint, 'ingen kandidat over 5');

-- 3. Stabilitet: ingen blokkerende par. Et par (c, j) blokkerer hvis begge
--    ville foretrukket hverandre framfor det de fikk.
select is(
  (select count(*)
   from public.match_scores m
   join public.jobs j        on j.id = m.job_id and j.status = 'published'
   join public.job_cutoffs k on k.job_id = m.job_id
   where m.score >= 60
     and not exists (select 1 from public.allocations a
                     where a.job_id = m.job_id and a.profile_id = m.profile_id)
     and not exists (select 1 from public.applications a
                     where a.job_id = m.job_id and a.profile_id = m.profile_id)
     -- kandidaten vil heller ha j
     and (public.free_slots(m.profile_id) > 0
          or m.score > (select min(a.score) from public.allocations a
                        where a.profile_id = m.profile_id))
     -- stillingen vil heller ha c
     and (k.holders < k.cap or (k.cap > 0 and m.score > k.cutoff_score))),
  0::bigint, 'ingen blokkerende par — fordelingen er stabil');

-- 4. Gulv: en stilling under 3 har ingen kvalifisert kandidat med ledig plass igjen
select is(
  (select count(*)
   from public.job_cutoffs k
   join public.match_scores m on m.job_id = k.job_id and m.score >= 60
   where k.holders < 3 and k.cap >= 3
     and public.free_slots(m.profile_id) > 0
     and not exists (select 1 from public.allocations a
                     where a.job_id = m.job_id and a.profile_id = m.profile_id)
     and not exists (select 1 from public.applications a
                     where a.job_id = m.job_id and a.profile_id = m.profile_id)),
  0::bigint, 'gulvet er fylt der det finnes kandidater');

-- 5. Søknad uten tildeling avvises
select throws_ok(
  $$ insert into public.applications (job_id, profile_id)
     select m.job_id, m.profile_id
     from public.match_scores m
     join public.jobs j on j.id = m.job_id and j.status = 'published'
     where m.score >= 60
       and not exists (select 1 from public.allocations a
                       where a.job_id = m.job_id and a.profile_id = m.profile_id)
       and not exists (select 1 from public.applications a
                       where a.job_id = m.job_id and a.profile_id = m.profile_id)
     limit 1 $$,
  'Du kan bare søke på stillinger du har fått tildelt');

select * from finish();
rollback;
