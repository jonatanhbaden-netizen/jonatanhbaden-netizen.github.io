import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnGrunner, tegnScore, tegnPlasser } from '/shared/components/grunner.js';
import { esc, tall, siden, dato, STATUS_TEKST } from '/shared/format.js';

const TID = new Intl.DateTimeFormat('nb-NO', { weekday: 'short', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });

const jobId = new URLSearchParams(location.search).get('id');
const feil = document.getElementById('feil');
const dialog = document.getElementById('intervju-dialog');
let aktivSoknad = null;
let intervjuer = new Map();

const res = await krevRolle('arbeidsgiver', './index.html');
if (res) {
  tegnTopp({
    vert: './dashboard.html',
    lenker: [{ href: './dashboard.html', tekst: 'Stillinger' }],
    undertittel: res.arbeidsgiver.name,
  });
  await tegn();
}

async function tegn() {
  const { data: stat, error: statFeil } = await supabase
    .from('job_stats').select('*').eq('job_id', jobId).maybeSingle();

  if (statFeil || !stat) {
    feil.textContent = 'Fant ikke stillingen.';
    return;
  }

  document.title = `${stat.title} — Jobbo`;
  document.getElementById('tittel').textContent = stat.title;
  document.getElementById('oppsummering').innerHTML = `
    <span><span class="opp-tall">${tall(stat.qualified_count)}</span> kvalifiserte matchet</span>
    <span><span class="opp-tall">${tall(stat.application_count)}</span> har søkt</span>
    <span class="dempet">du ser de ${tall(stat.shortlist_cap)} beste</span>`;

  const lukket = stat.status === 'closed';
  document.getElementById('stillingsvalg').innerHTML = lukket
    ? '<span class="status">Lukket</span>'
    : `<a class="knapp knapp-2 knapp-liten" href="./ny-stilling.html?id=${jobId}">Rediger</a>
       <button class="knapp knapp-3 knapp-liten" type="button" id="lukk">Lukk stillingen</button>`;
  document.getElementById('lukk')?.addEventListener('click', async () => {
    if (!confirm('Lukke stillingen? Søkerne beholder søknadene sine, men ingen nye kan søke.')) return;
    const { error } = await supabase.from('jobs').update({ status: 'closed' }).eq('id', jobId);
    if (error) { feil.textContent = `Klarte ikke å lukke: ${error.message}`; return; }
    await tegn();
  });
  document.getElementById('lite-kvalifiserte').textContent =
    !lukket && Number(stat.qualified_count) < 3
      ? `Bare ${tall(stat.qualified_count)} kandidater i basen er kvalifisert for denne stillingen. Færre krav gir flere søkere — rediger stillingen og senk gjerne ett av dem.`
      : '';

  document.getElementById('garanti').innerHTML = `
    ${tegnPlasser(Number(stat.booked_interviews), Number(stat.guaranteed_interviews))}
    <span><strong>${tall(stat.booked_interviews)} av ${tall(stat.guaranteed_interviews)}</strong> garanterte intervjuer booket</span>
    <span class="svak vokser" style="text-align: right">Du har forpliktet deg til å intervjue inntil ${tall(stat.guaranteed_interviews)} kandidater herfra</span>`;

  const { data: sokere, error: sokerFeil } = await supabase
    .from('job_shortlist').select('*').eq('job_id', jobId).order('rank');

  if (sokerFeil) {
    feil.textContent = `Klarte ikke å hente søkerne: ${sokerFeil.message}`;
    return;
  }

  const { data: iv } = await supabase.from('interviews')
    .select('id, application_id, proposed_times, scheduled_at, status, location')
    .in('application_id', sokere.map((s) => s.application_id));
  intervjuer = new Map((iv ?? []).filter((i) => i.status !== 'avlyst').map((i) => [i.application_id, i]));

  const shortlist = sokere.filter((s) => s.on_shortlist);
  const venteliste = sokere.filter((s) => !s.on_shortlist);

  document.getElementById('shortlist').innerHTML = shortlist.length
    ? shortlist.map(rad).join('')
    : '<li><div class="tom"><h3>Ingen søkere ennå</h3><p class="tekst">Kvalifiserte kandidater ser stillingen blant sine matcher. Søknadene kommer inn her.</p></div></li>';

  const seksjon = document.getElementById('venteliste-seksjon');
  if (venteliste.length) {
    seksjon.hidden = false;
    const knapp = document.getElementById('vis-venteliste');
    knapp.textContent = `Venteliste (${venteliste.length})`;
    document.getElementById('venteliste').innerHTML = venteliste.map(rad).join('');
  } else {
    seksjon.hidden = true;
  }

  bindHandlinger();
}

function intervjuTekst(i) {
  if (!i) return '';
  if (i.status === 'bekreftet') return `<span class="svak" style="color: var(--ja)">Intervju ${esc(TID.format(new Date(i.scheduled_at)))}${i.location ? ` · ${esc(i.location)}` : ''}</span>`;
  return `<span class="svak">Foreslått ${i.proposed_times.length} tidspunkt${i.proposed_times.length === 1 ? '' : 'er'} — venter på kandidaten</span>`;
}

function rad(s) {
  const navn = `${s.first_name} ${s.last_name}`;
  const i = intervjuer.get(s.application_id);
  return `<li>
    <div class="rad-kandidat">
      <span class="rangnr">${s.rank}</span>
      <div class="stabel-2">
        <a href="./kandidat.html?id=${s.profile_id}&stilling=${jobId}" class="rad-navn">${esc(navn)}</a>
        <span class="svak">${esc(s.kommune ?? '')} · søkte ${esc(siden(s.created_at))}</span>
        ${intervjuTekst(i)}
      </div>
      <div class="stabel-2" style="justify-items: end">
        ${tegnScore(s.score)}
        <span class="status status-${esc(s.status)}">${esc(STATUS_TEKST[s.status] ?? s.status)}</span>
      </div>
      <div class="rad-grunner stabel-2">
        ${tegnGrunner(s.reasons, { maks: 4 })}
        <div class="handlinger">
          ${s.status === 'sendt' ? `<button class="knapp knapp-2 knapp-liten" data-status="sett" data-id="${s.application_id}">Marker som sett</button>` : ''}
          ${!i && s.status !== 'tilbud' && s.status !== 'avslag' ? `<button class="knapp knapp-liten" data-intervju="${s.application_id}" data-navn="${esc(navn)}">Foreslå intervju</button>` : ''}
          ${i ? `<button class="knapp knapp-3 knapp-liten" data-avlys="${i.id}">Avlys intervju</button>` : ''}
          ${s.status === 'intervju' ? `<button class="knapp knapp-liten" data-status="tilbud" data-id="${s.application_id}">Gi tilbud</button>` : ''}
          ${s.status !== 'avslag' ? `<button class="knapp knapp-3 knapp-liten" data-status="avslag" data-id="${s.application_id}">Avslå</button>` : ''}
        </div>
      </div>
    </div>
  </li>`;
}

function bindHandlinger() {
  document.querySelectorAll('[data-status]').forEach((k) => {
    k.addEventListener('click', async () => {
      feil.textContent = '';
      k.disabled = true;
      const { error } = await supabase
        .from('applications')
        .update({ status: k.dataset.status })
        .eq('id', k.dataset.id);
      if (error) { feil.textContent = `Klarte ikke å oppdatere: ${error.message}`; k.disabled = false; return; }
      await tegn();
    });
  });

  document.querySelectorAll('[data-intervju]').forEach((k) => {
    k.addEventListener('click', () => {
      aktivSoknad = k.dataset.intervju;
      document.getElementById('intervju-navn').textContent = `Kandidat: ${k.dataset.navn}`;
      [1, 2, 3].forEach((n) => {
        const om = new Date(Date.now() + (n + 2) * 86400000);
        om.setHours(10 + n, 0, 0, 0);
        document.getElementById(`tid-${n}`).value = lokalIso(om);
      });
      dialog.showModal();
    });
  });

  document.querySelectorAll('[data-avlys]').forEach((k) => {
    k.addEventListener('click', async () => {
      if (!confirm('Avlyse intervjuet? Kandidaten får beskjed.')) return;
      const { error } = await supabase.from('interviews').update({ status: 'avlyst' }).eq('id', k.dataset.avlys);
      if (error) { feil.textContent = `Klarte ikke å avlyse: ${error.message}`; return; }
      await tegn();
    });
  });

  const vis = document.getElementById('vis-venteliste');
  if (vis) {
    vis.addEventListener('click', () => {
      const liste = document.getElementById('venteliste');
      const apen = !liste.hidden;
      liste.hidden = apen;
      vis.setAttribute('aria-expanded', String(!apen));
    });
  }
}

// datetime-local wants local time without a zone.
function lokalIso(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`;
}

dialog.addEventListener('close', async () => {
  if (dialog.returnValue !== 'book' || !aktivSoknad) return;
  const tider = [1, 2, 3]
    .map((n) => document.getElementById(`tid-${n}`).value)
    .filter(Boolean)
    .map((t) => new Date(t).toISOString());
  if (!tider.length) return;

  feil.textContent = '';
  const { error: iFeil } = await supabase.from('interviews')
    .insert({ application_id: aktivSoknad, proposed_times: tider, status: 'foreslatt',
              location: document.getElementById('sted').value.trim() || null, notes: 'Førstegangsintervju' });
  if (iFeil) { feil.textContent = `Klarte ikke å booke: ${iFeil.message}`; return; }

  const { error: sFeil } = await supabase.from('applications')
    .update({ status: 'intervju' }).eq('id', aktivSoknad);
  if (sFeil) { feil.textContent = `Intervjuet ble booket, men statusen ble ikke oppdatert: ${sFeil.message}`; }

  aktivSoknad = null;
  await tegn();
});
