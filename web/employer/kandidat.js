import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnGrunner, tegnScore } from '/shared/components/grunner.js';
import { tegnCv } from '/shared/cv.js';
import { hentEtiketter } from '/shared/ferdigheter.js';
import { esc, STATUS_TEKST } from '/shared/format.js';

const params = new URLSearchParams(location.search);
const profilId = params.get('id');
const jobId = params.get('stilling');
const feil = document.getElementById('feil');

const res = await krevRolle('arbeidsgiver', './index.html');
if (res) {
  tegnTopp({
    vert: './dashboard.html',
    lenker: [{ href: './dashboard.html', tekst: 'Stillinger' }],
    undertittel: res.arbeidsgiver.name,
  });
  document.getElementById('tilbake').href = jobId ? `./stilling.html?id=${jobId}` : './dashboard.html';
  await tegn();
}

async function tegn() {
  const { data: profil, error } = await supabase
    .from('profiles').select('*').eq('id', profilId).maybeSingle();

  if (error || !profil) {
    feil.textContent = 'Du har ikke tilgang til denne profilen. Arbeidsgivere ser bare kandidater som har søkt på en av stillingene deres.';
    return;
  }

  document.title = `${profil.first_name} ${profil.last_name} — Jobbo`;
  document.getElementById('cv').innerHTML = tegnCv(profil, { etiketter: await hentEtiketter() });

  const { data: rad } = await supabase
    .from('job_shortlist').select('*')
    .eq('job_id', jobId).eq('profile_id', profilId).maybeSingle();

  const panel = document.getElementById('panel');
  if (!rad) { panel.innerHTML = ''; return; }

  panel.innerHTML = `
    <div class="kort stabel">
      <div class="rad-mellom">
        <h3 style="font-size: var(--t-base)">Match på denne stillingen</h3>
        ${tegnScore(rad.score)}
      </div>
      ${tegnGrunner(rad.reasons)}
      <div class="rad-mellom" style="border-top: var(--kant); padding-top: var(--s-3)">
        <span class="svak">Status</span>
        <span class="status status-${esc(rad.status)}">${esc(STATUS_TEKST[rad.status] ?? rad.status)}</span>
      </div>
      <div class="stabel-2">
        ${rad.status === 'sendt' ? `<button class="knapp knapp-2 knapp-full" data-status="sett">Marker som sett</button>` : ''}
        ${rad.status !== 'tilbud' ? `<button class="knapp knapp-full" data-status="intervju">Sett til intervju</button>` : ''}
        ${rad.status === 'intervju' ? `<button class="knapp knapp-full" data-status="tilbud">Gi tilbud</button>` : ''}
        ${rad.status !== 'avslag' ? `<button class="knapp knapp-3" data-status="avslag">Avslå</button>` : ''}
      </div>
    </div>`;

  panel.querySelectorAll('[data-status]').forEach((k) => {
    k.addEventListener('click', async () => {
      k.disabled = true;
      const { error: oppFeil } = await supabase.from('applications')
        .update({ status: k.dataset.status }).eq('id', rad.application_id);
      if (oppFeil) { feil.textContent = `Klarte ikke å oppdatere: ${oppFeil.message}`; k.disabled = false; return; }
      await tegn();
    });
  });
}
