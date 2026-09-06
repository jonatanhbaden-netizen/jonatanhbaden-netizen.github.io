// Stripe calls this when a checkout completes. Signature is verified with
// STRIPE_WEBHOOK_SECRET; there is no user JWT on a webhook.
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

async function gyldigSignatur(payload: string, header: string | null, secret: string): Promise<boolean> {
  if (!header) return false;
  const deler = Object.fromEntries(header.split(',').map((p) => p.split('=') as [string, string]));
  if (!deler.t || !deler.v1) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${deler.t}.${payload}`));
  const hex = [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
  return hex === deler.v1;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get('STRIPE_WEBHOOK_SECRET');
  if (!secret) return json({ error: 'STRIPE_WEBHOOK_SECRET mangler' }, 500);

  const payload = await req.text();
  if (!(await gyldigSignatur(payload, req.headers.get('stripe-signature'), secret))) {
    return json({ error: 'Ugyldig signatur' }, 400);
  }

  const event = JSON.parse(payload);
  if (event.type !== 'checkout.session.completed') return json({ ignored: event.type });

  const session = event.data.object;
  const jobId = session.metadata?.job_id;
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  await admin.from('payments')
    .update({ status: 'betalt', paid_at: new Date().toISOString() })
    .eq('session_id', session.id);
  if (jobId) {
    await admin.from('jobs')
      .update({ status: 'published', published_at: new Date().toISOString() })
      .eq('id', jobId).eq('status', 'draft');
  }
  return json({ ok: true });
});
