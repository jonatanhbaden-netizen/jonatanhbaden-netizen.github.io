import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnScore, tegnPlasser } from '/shared/components/grunner.js';
import { MAKS_AKTIVE_SOKNADER } from '/shared/config.js';
import { esc, siden, STATUS_TEKST } from '/shared/format.js';

const TID = new Intl.DateTimeFormat('nb-NO', { weekday: 'long', day: '2-digit', month: 'long', hour: '2-digit', minute: '2-digit' });

const AKTIVE = ['sendt', 'sett', 'intervju'];
const LOPET = ['sendt', 'sett', 'intervju', 'tilbud'];

const feil = document.getElementById('feil');

const res = await krevRolle('kandidat', './index.html');
if (res) await tegn();

async function tegn() {
  tegnTopp({
    vert: './matcher.html',
    lenker: [
      { href: './matcher.html', tekst: 'Matcher' },
      { href: './soknader.html', tekst: 'Søknader' },
      { href: './profil.html', tekst: 'Profil' },
    ],
    aktiv: './soknader.html',
  });

  const { data: soknader, error } = await supabase
    .from('applications')
    .select('id, status, score_at_apply, created_at, jobs(title, kommune, companies(name))')
    .order('created_at', { ascending: false });

  const { data: iv } = await supabase.from('interviews')
    .select('id, application_id, proposed_times, scheduled_at, status, location');
  const intervjuer = new Map((iv ?? []).filter((i) => i.status !== 'avlyst').map((i) => [i.application_id, i]));

  const liste = document.getElementById('liste');
  const brukt = (soknader ?? []).filter((s) => AKTIVE.includes(s.status)).length;

  document.getElementById('kvote').innerHTML = `
    ${tegnPlasser(brukt, MAKS_AKTIVE_SOKNADER)}
    <span class="plasser-tekst"><strong>${brukt} av ${MAKS_AKTIVE_SOKNADER}</strong> aktive søknader</span>
    <a class="svak vokser" style="text-align: right" href="./matcher.html">Se nye matcher</a>`;

  if (error) {
    liste.innerHTML = `<p class="melding melding-feil">Klarte ikke å hente søknadene: ${esc(error.message)}</p>`;
  } else if (!soknader.length) {
    liste.innerHTML = `<div class="tom">
      <h3>Ingen søknader ennå</h3>
      <p class="tekst">Når du søker på en jobb fra matchene dine, følger du den herfra.</p>
      <a class="knapp" href="./matcher.html">Se matchene dine</a>
    </div>`;
  } else {
    liste.innerHTML = soknader.map((s) => `
      <article class="kort soknad">
        <div class="rad-mellom">
          <div>
            <h2 style="font-size: var(--t-md)">${esc(s.jobs.title)}</h2>
            <p class="svak">${esc(s.jobs.companies.name)} · ${esc(s.jobs.kommune)} · sendt ${esc(siden(s.created_at))}</p>
          </div>
          ${tegnScore(s.score_at_apply)}
        </div>
        ${s.status === 'avslag'
          ? '<p><span class="status status-avslag">Avslag</span></p>'
          : `<div class="lopet">${lopet(s.status)}</div>`}
        ${intervju(intervjuer.get(s.id))}
      </article>`).join('');
  }

  document.querySelectorAll('[data-bekreft]').forEach((k) => {
    k.addEventListener('click', async () => {
      feil.textContent = '';
      k.disabled = true;
      const { error: bFeil } = await supabase.rpc('confirm_interview', { p_id: k.dataset.bekreft, p_time: k.dataset.tid });
      if (bFeil) { feil.textContent = bFeil.message.replace(/^.*?:\s*/, ''); k.disabled = false; return; }
      await tegn();
    });
  });
}

function intervju(i) {
  if (!i) return '';
  if (i.status === 'bekreftet') {
    return `<div class="felt stabel-2">
      <strong>Intervju ${esc(TID.format(new Date(i.scheduled_at)))}</strong>
      ${i.location ? `<span class="svak">${esc(i.location)}</span>` : ''}
    </div>`;
  }
  return `<div class="felt stabel-2">
    <strong>Velg tidspunkt for intervju</strong>
    ${i.location ? `<span class="svak">${esc(i.location)}</span>` : ''}
    <div class="rad">
      ${i.proposed_times.map((t) => `<button class="knapp knapp-2 knapp-liten" type="button" data-bekreft="${i.id}" data-tid="${esc(t)}">${esc(TID.format(new Date(t)))}</button>`).join('')}
    </div>
  </div>`;
}

function lopet(status) {
  const na = LOPET.indexOf(status);
  return LOPET.map((steg, i) => `
    <span class="lopet-steg" data-na="${i === na ? 'ja' : 'nei'}" data-passert="${i < na ? 'ja' : 'nei'}">
      ${esc(STATUS_TEKST[steg])}
    </span>${i < LOPET.length - 1 ? '<span class="lopet-pil" aria-hidden="true">›</span>' : ''}`).join('');
}
