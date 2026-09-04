import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnScore, tegnPlasser } from '/shared/components/grunner.js';
import { MAKS_AKTIVE_SOKNADER } from '/shared/config.js';
import { esc, siden, STATUS_TEKST } from '/shared/format.js';

const AKTIVE = ['sendt', 'sett', 'intervju'];
const LOPET = ['sendt', 'sett', 'intervju', 'tilbud'];

const res = await krevRolle('kandidat', './index.html');
if (res) {
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
      </article>`).join('');
  }
}

function lopet(status) {
  const na = LOPET.indexOf(status);
  return LOPET.map((steg, i) => `
    <span class="lopet-steg" data-na="${i === na ? 'ja' : 'nei'}" data-passert="${i < na ? 'ja' : 'nei'}">
      ${esc(STATUS_TEKST[steg])}
    </span>${i < LOPET.length - 1 ? '<span class="lopet-pil" aria-hidden="true">›</span>' : ''}`).join('');
}
