# Code

- Vanilla JS ES modules. No framework, no build step.
- No inline event handlers. Bind with `addEventListener` in a module.
- Semantic HTML: `<main>`, `<section>`, `<nav>`, `<article>`.
- Every image needs descriptive `alt` text.
- Supabase client is created once in `web/shared/supabase.js` and imported.
- Only the anon key ever appears in `web/`. The service-role key is local-only.
