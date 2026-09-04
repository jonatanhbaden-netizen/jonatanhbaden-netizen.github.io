import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnCv } from '/shared/cv.js';
import { esc } from '/shared/format.js';

const feil = document.getElementById('feil');
const ok = document.getElementById('ok');
const valgte = new Set();
let ferdigheter = [];
let erfaring = [];
let utdanning = [];
let profil = null;
let etiketter = new Map();

const res = await krevRolle('kandidat', './index.html');
if (res) {
  profil = res.profil;
  tegnTopp({
    vert: './matcher.html',
    lenker: [
      { href: './matcher.html', tekst: 'Matcher' },
      { href: './soknader.html', tekst: 'Søknader' },
      { href: './profil.html', tekst: 'Profil' },
    ],
    aktiv: './profil.html',
  });

  const { data } = await supabase.from('skills').select('name, label, category').order('category').order('label');
  ferdigheter = data ?? [];
  etiketter = new Map(ferdigheter.map((f) => [f.name, f.label]));

  fyllInn();
  tegnFerdigheter();
  tegnPoster();
  oppdaterForhandsvisning();
}

function fyllInn() {
  document.getElementById('fornavn').value = profil.first_name ?? '';
  document.getElementById('etternavn').value = profil.last_name ?? '';
  document.getElementById('telefon').value = profil.phone ?? '';
  document.getElementById('kommune').value = profil.kommune ?? 'Oslo';
  document.getElementById('om').value = profil.about ?? '';
  document.getElementById('hoyeste').value = profil.highest_education ?? 'grunnskole';
  document.getElementById('norsk').value = profil.norsk ?? 'ingen';
  document.getElementById('engelsk').value = profil.engelsk ?? 'ingen';
  document.getElementById('tilgjengelig').value = profil.available_from ?? '';
  (profil.skills ?? []).forEach((s) => valgte.add(s));
  erfaring = Array.isArray(profil.experience) ? [...profil.experience] : [];
  utdanning = Array.isArray(profil.education) ? [...profil.education] : [];

  const andre = new Set(profil.acceptable_kommuner ?? []);
  [...document.getElementById('andre-kommuner').options].forEach((o) => { o.selected = andre.has(o.value); });
}

function tegnFerdigheter() {
  const sok = document.getElementById('sok').value.trim().toLowerCase();
  const treff = ferdigheter.filter((f) => !sok || f.label.toLowerCase().includes(sok));
  const grupper = {};
  treff.forEach((f) => { (grupper[f.category] ??= []).push(f); });

  document.getElementById('ferdighetsliste').innerHTML = Object.entries(grupper).map(([kat, liste]) => `
    <p class="kat-tittel">${esc(kat)}</p>
    <div class="merker">
      ${liste.map((f) => `<button class="merke-valg" type="button" data-ferdighet="${esc(f.name)}"
          aria-pressed="${valgte.has(f.name)}">${esc(f.label)}</button>`).join('')}
    </div>`).join('');

  document.querySelectorAll('[data-ferdighet]').forEach((k) => {
    k.addEventListener('click', () => {
      const navn = k.dataset.ferdighet;
      if (valgte.has(navn)) valgte.delete(navn); else valgte.add(navn);
      k.setAttribute('aria-pressed', String(valgte.has(navn)));
      tegnValgte();
      oppdaterForhandsvisning();
    });
  });
  tegnValgte();
}

function tegnValgte() {
  const boks = document.getElementById('valgte');
  boks.innerHTML = valgte.size
    ? [...valgte].map((n) => {
        const f = ferdigheter.find((x) => x.name === n);
        return `<button class="merke-valg" type="button" aria-pressed="true" data-fjern="${esc(n)}">${esc(f?.label ?? n)} ✕</button>`;
      }).join('')
    : '<span class="svak">Ingen valgt ennå</span>';

  boks.querySelectorAll('[data-fjern]').forEach((k) => {
    k.addEventListener('click', () => {
      valgte.delete(k.dataset.fjern);
      tegnFerdigheter();
      oppdaterForhandsvisning();
    });
  });
}

function postRad(post, i, type) {
  const erErfaring = type === 'erfaring';
  return `<div class="post-rad" data-type="${type}" data-i="${i}">
    <div class="to-kolonner">
      <label>${erErfaring ? 'Stilling' : 'Grad eller linje'}
        <input data-felt="title" value="${esc(post.title ?? '')}"></label>
      <label>${erErfaring ? 'Arbeidsgiver' : 'Skole'}
        <input data-felt="${erErfaring ? 'company' : 'institution'}" value="${esc(post.company ?? post.institution ?? '')}"></label>
      <label>Fra <input type="date" data-felt="from" value="${esc(post.from ?? '')}"></label>
      <label>Til <input type="date" data-felt="to" value="${esc(post.to ?? '')}"></label>
    </div>
    <div class="rad-mellom">
      <span class="svak">${erErfaring ? 'La «Til» stå tom hvis du jobber der nå' : ''}</span>
      <button class="knapp knapp-3 knapp-liten" type="button" data-slett>Fjern</button>
    </div>
  </div>`;
}

function tegnPoster() {
  document.getElementById('erfaringsliste').innerHTML = erfaring.length
    ? erfaring.map((p, i) => postRad(p, i, 'erfaring')).join('')
    : '<p class="svak">Ingen erfaring lagt inn ennå.</p>';
  document.getElementById('utdanningsliste').innerHTML = utdanning.length
    ? utdanning.map((p, i) => postRad(p, i, 'utdanning')).join('')
    : '<p class="svak">Ingen utdanning lagt inn ennå.</p>';

  document.querySelectorAll('.post-rad').forEach((rad) => {
    const liste = rad.dataset.type === 'erfaring' ? erfaring : utdanning;
    const i = Number(rad.dataset.i);

    rad.querySelectorAll('[data-felt]').forEach((inp) => {
      inp.addEventListener('input', () => {
        liste[i][inp.dataset.felt] = inp.value || null;
        oppdaterForhandsvisning();
      });
    });

    rad.querySelector('[data-slett]').addEventListener('click', () => {
      liste.splice(i, 1);
      tegnPoster();
      oppdaterForhandsvisning();
    });
  });
}

document.getElementById('legg-til-erfaring').addEventListener('click', () => {
  erfaring.push({ title: '', company: '', from: '', to: null, description: '' });
  tegnPoster();
});
document.getElementById('legg-til-utdanning').addEventListener('click', () => {
  utdanning.push({ title: '', institution: '', from: '', to: '', description: '' });
  tegnPoster();
});
document.getElementById('sok').addEventListener('input', tegnFerdigheter);

function samle() {
  return {
    first_name: document.getElementById('fornavn').value.trim(),
    last_name: document.getElementById('etternavn').value.trim(),
    phone: document.getElementById('telefon').value.trim() || null,
    kommune: document.getElementById('kommune').value,
    about: document.getElementById('om').value.trim() || null,
    highest_education: document.getElementById('hoyeste').value,
    norsk: document.getElementById('norsk').value,
    engelsk: document.getElementById('engelsk').value,
    available_from: document.getElementById('tilgjengelig').value || null,
    acceptable_kommuner: [...document.getElementById('andre-kommuner').selectedOptions].map((o) => o.value),
    skills: [...valgte],
    experience: erfaring.filter((e) => e.title || e.company),
    education: utdanning.filter((u) => u.title || u.institution),
  };
}

function oppdaterForhandsvisning() {
  document.getElementById('forhandsvisning').innerHTML = tegnCv({ ...profil, ...samle() }, { etiketter });
}

document.getElementById('skjema').addEventListener('input', oppdaterForhandsvisning);

document.getElementById('skjema').addEventListener('submit', async (e) => {
  e.preventDefault();
  feil.textContent = '';
  ok.textContent = '';
  const knapp = document.getElementById('lagre');
  knapp.disabled = true;
  knapp.textContent = 'Lagrer …';

  // Saving fires the recompute trigger, so matches are ready immediately after.
  const { error } = await supabase.from('profiles')
    .update({ ...samle(), updated_at: new Date().toISOString() })
    .eq('id', res.session.user.id);

  knapp.disabled = false;
  knapp.textContent = 'Lagre profilen';

  if (error) { feil.textContent = `Klarte ikke å lagre: ${error.message}`; return; }
  ok.textContent = 'Profilen er lagret. Matchene dine er oppdatert.';
});
