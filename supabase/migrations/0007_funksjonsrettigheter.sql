-- Supabase's linter flagged that every SECURITY DEFINER function is reachable
-- as a REST endpoint (/rest/v1/rpc/<name>). None of these are meant to be
-- called by a client: they are trigger bodies and internal recompute helpers.
-- Revoking EXECUTE does not affect triggers — permission is checked when the
-- trigger is created, not each time it fires.
--
-- current_company_id() is the exception: RLS policy expressions are evaluated
-- with the caller's privileges, so `authenticated` must keep EXECUTE or every
-- employer policy breaks. Only `anon` loses it, and no policy targets anon.
revoke execute on function public.current_company_id()                    from anon;
revoke execute on function public.enforce_application_rules()             from anon, authenticated;
revoke execute on function public.recompute_job_matches(uuid)             from anon, authenticated;
revoke execute on function public.recompute_profile_matches(uuid)         from anon, authenticated;
revoke execute on function public.trg_jobs_recompute()                    from anon, authenticated;
revoke execute on function public.trg_profiles_recompute()                from anon, authenticated;
revoke execute on function public.touch_application()                     from anon, authenticated;

-- Pin the search_path on the pure helpers so a rogue schema earlier in a
-- caller's search_path cannot shadow the functions they call.
alter function public.education_rank(education_level)          set search_path = public;
alter function public.education_label(education_level)         set search_path = public;
alter function public.language_label(language_level)           set search_path = public;
alter function public.total_experience_years(jsonb)            set search_path = public;
alter function public.nb_num(numeric)                          set search_path = public;
alter function public.compute_match(public.jobs, public.profiles) set search_path = public;
alter function public.compute_match(uuid, uuid)                set search_path = public;
alter function public.touch_application()                      set search_path = public;
