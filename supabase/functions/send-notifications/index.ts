// Drains the notifications outbox through Resend. Called by pg_cron every
// five minutes with the anon key. Without RESEND_API_KEY nothing is sent and
// the rows stay 'venter'.
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

  const key = Deno.env.get('RESEND_API_KEY');
  if (!key) return json({ skipped: 'RESEND_API_KEY mangler' });

  const fra = Deno.env.get('EMAIL_FROM') ?? 'Jobbo <onboarding@resend.dev>';
  const site = (Deno.env.get('SITE_URL') ?? '').replace(/\/$/, '');
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  const { data: kø } = await admin.from('notifications')
    .select('id, email, subject, body, path').eq('status', 'venter')
    .order('created_at').limit(50);

  let sendt = 0, feilet = 0;
  for (const n of kø ?? []) {
    const r = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: fra, to: [n.email], subject: n.subject,
        text: `${n.body}\n\n${site}${n.path}\n\n— Jobbo`,
      }),
    });
    if (r.ok) {
      sendt += 1;
      await admin.from('notifications').update({ status: 'sendt', sent_at: new Date().toISOString() }).eq('id', n.id);
    } else {
      feilet += 1;
      await admin.from('notifications').update({ status: 'feilet', error: (await r.text()).slice(0, 500) }).eq('id', n.id);
    }
  }
  return json({ sendt, feilet });
});
