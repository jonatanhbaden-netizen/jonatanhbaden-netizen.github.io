import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';

const jobId = new URLSearchParams(location.search).get('id');
const feil = document.getElementById('feil');

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
  }
}

document.getElementById('betal').addEventListener('click', async (e) => {
  const knapp = e.currentTarget;
  knapp.disabled = true;
  knapp.textContent = 'Publiserer …';
  feil.textContent = '';

  // Publishing fires the recompute trigger, so the shortlist is populated
  // by the time the next page loads.
  const { error } = await supabase.from('jobs')
    .update({ status: 'published', published_at: new Date().toISOString() })
    .eq('id', jobId);

  if (error) {
    feil.textContent = `Klarte ikke å publisere: ${error.message}`;
    knapp.disabled = false;
    knapp.textContent = 'Betal 5 000 kr og publiser';
    return;
  }
  location.href = `./stilling.html?id=${jobId}`;
});
