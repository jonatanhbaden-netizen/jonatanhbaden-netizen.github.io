// Starts a Stripe Checkout session for a draft job. Without STRIPE_SECRET_KEY
// it answers { mode: 'demo' } and the client publishes directly.
import { createClient } from 'npm:@supabase/supabase-js@2';
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = Deno.env.get('SUPABASE_URL')!;
  const { job_id, return_url } = await req.json();
  if (!job_id || !return_url) return json({ error: 'job_id og return_url mangler' }, 400);

  // The caller's own JWT: RLS lets an employer read a draft only for their company.
  const bruker = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: job } = await bruker.from('jobs')
    .select('id, title, price_nok, status').eq('id', job_id).maybeSingle();
  if (!job) return json({ error: 'Fant ikke stillingen' }, 404);
  if (job.status === 'published') return json({ mode: 'published' });

  const key = Deno.env.get('STRIPE_SECRET_KEY');
  if (!key) return json({ mode: 'demo' });

  const body = new URLSearchParams({
    mode: 'payment',
    'line_items[0][quantity]': '1',
    'line_items[0][price_data][currency]': 'nok',
    'line_items[0][price_data][unit_amount]': String(job.price_nok * 100),
    'line_items[0][price_data][product_data][name]': `Stillingsannonse på Jobbo: ${job.title}`,
    success_url: `${return_url}?id=${job.id}&session_id={CHECKOUT_SESSION_ID}`,
    cancel_url: `${return_url}?id=${job.id}`,
    'metadata[job_id]': job.id,
  });
  const r = await fetch('https://api.stripe.com/v1/checkout/sessions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });
  const session = await r.json();
  if (!r.ok) return json({ error: session.error?.message ?? 'Stripe avviste forespørselen' }, 502);

  const admin = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  await admin.from('payments').insert({
    job_id: job.id, provider: 'stripe', session_id: session.id, amount_nok: job.price_nok,
  });
  return json({ url: session.url });
});
