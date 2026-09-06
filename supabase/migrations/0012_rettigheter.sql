-- Supabase-linteren regner nå PUBLIC-grantet som «anon kan kalle». Interne
-- SECURITY DEFINER-funksjoner skal ikke være REST-endepunkter i det hele tatt.
-- Unntak: confirm_interview, delete_my_account og export_my_data kalles av
-- innloggede brukere; current_company_id brukes i RLS-uttrykk.
do $$
declare f text;
begin
  foreach f in array array[
    'public.allocate_new_job(uuid)', 'public.allocate_profile(uuid)',
    'public.enforce_application_rules()', 'public.handle_new_user()',
    'public.notify(uuid, text, text, text, text)', 'public.notify_company(uuid, text, text, text)',
    'public.recompute_job_matches(uuid)', 'public.recompute_profile_matches(uuid)',
    'public.run_allocation()', 'public.trg_application_notify()', 'public.trg_interview_notify()',
    'public.trg_jobs_allocate()', 'public.trg_jobs_recompute()', 'public.trg_profiles_allocate()',
    'public.trg_profiles_recompute()', 'public.touch_application()'
  ] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
  end loop;
end $$;

revoke execute on function public.confirm_interview(uuid, timestamptz) from public, anon;
revoke execute on function public.delete_my_account()                   from public, anon;
revoke execute on function public.export_my_data()                      from public, anon;
revoke execute on function public.current_company_id()                  from public, anon;
revoke execute on function public.free_slots(uuid)                      from public, anon;
revoke execute on function public.job_free_cap(uuid)                    from public, anon;

-- pg_net hører hjemme i extensions-skjemaet; net.http_post er uendret.
drop extension if exists pg_net;
create extension pg_net with schema extensions;
