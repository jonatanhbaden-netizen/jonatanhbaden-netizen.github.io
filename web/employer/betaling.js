import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';

const params = new URLSearchParams(location.search);
const jobId = params.get('id');
const sessionId = params.get('session_id');
const feil = document.getElementById('feil');
const knapp = document.getElementById('betal');

const res = await krevRolle('arbeidsgiver', './index.html');
if (res) {
  tegnTopp({
    vert: './dashboard.html',
    lenker: [{ href: './dashboard.html', tekst: 'Stillinger' }],
    undertittel: res.arbeidsgiver.name,
  });

  const { data: stilling } = await supabase
    .from('jobs').select('title, kommune, status').eq('id', jobId).maybeSingle();

  if (!stilling) {
    feil.textContent = 'Fant ikke stillingen.';
  } else if (stilling.status === 'published') {
    location.href = `./stilling.html?id=${jobId}`;
  } else {
    document.getElementById('stillingsnavn').textContent = `${stilling.title} — ${stilling.kommune}`;
    if (sessionId) await ventPaaBetaling();
  }
}

// Back from Stripe: the webhook publishes the job. Poll until it has.
async function ventPaaBetaling() {
  knapp.disabled = true;
  knapp.textContent = 'Betalingen behandles …';
  for (let i = 0; i < 20; i += 1) {
    const { data } = await supabase.from('jobs').select('status').eq('id', jobId).maybeSingle();
    if (data?.status === 'published') { location.href = `./stilling.html?id=${jobId}`; return; }
    await new Promise((r) => setTimeout(r, 1500));
  }
  feil.textContent = 'Vi har ikke fått bekreftelse fra betalingen ennå. Stillingen publiseres automatisk så snart den kommer — sjekk igjen om et øyeblikk.';
  knapp.disabled = false;
  knapp.textContent = 'Prøv igjen';
}

knapp.addEventListener('click', async () => {
  knapp.disabled = true;
  knapp.textContent = 'Går til betaling …';
  feil.textContent = '';

  const { data, error } = await supabase.functions.invoke('create-checkout', {
    body: { job_id: jobId, return_url: `${location.origin}/employer/betaling.html` },
  });

  if (error || data?.error) {
    feil.textContent = `Klarte ikke å starte betalingen: ${data?.error ?? error.message}`;
    knapp.disabled = false;
    knapp.textContent = 'Betal 5 000 kr og publiser';
    return;
  }
  if (data.url) { location.href = data.url; return; }
  if (data.mode === 'published') { location.href = `./stilling.html?id=${jobId}`; return; }

  // No payment provider configured: publish directly, as in the demo.
  knapp.textContent = 'Publiserer …';
  const { error: pubFeil } = await supabase.from('jobs')
    .update({ status: 'published', published_at: new Date().toISOString() })
    .eq('id', jobId);
  if (pubFeil) {
    feil.textContent = `Klarte ikke å publisere: ${pubFeil.message}`;
    knapp.disabled = false;
    knapp.textContent = 'Betal 5 000 kr og publiser';
    return;
  }
  location.href = `./stilling.html?id=${jobId}`;
});
