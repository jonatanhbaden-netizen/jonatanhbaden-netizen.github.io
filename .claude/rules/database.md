# Database

- Migrations live in `supabase/migrations/` and are append-only once applied.
- Enum values, error messages and `reasons` text are Norwegian bokmal.
  Table, column and function names are English.
- Every table has RLS enabled. No table is left open.
- Views that must respect RLS are declared `with (security_invoker = on)`.
- Functions that bypass RLS are `security definer` and MUST set `search_path = public`.
- Kvalifisert threshold is 60: in the applications trigger and in `my_matches`.
