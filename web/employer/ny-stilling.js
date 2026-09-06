import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { esc, dato, UTDANNING_TEKST, SPRAK_TEKST } from '/shared/format.js';
import { hentSynonymer, filtrer } from '/shared/ferdigheter.js';

const feil = document.getElementById('feil');
const pakrevd = new Set();
const onsket = new Set();
let ferdigheter = [];
let synonymer = new Map();
let steg = 1;

// ?id= means we are editing an existing job with the same wizard.
const jobId = new URLSearchParams(location.search).get('id');
let eksisterende = null;

const res = await krevRolle('arbeidsgiver', './index.html');
if (res) {
  tegnTopp({
    vert: './dashboard.html',
    lenker: [{ href: './dashboard.html', tekst: 'Stillinger' }],
    undertittel: res.arbeidsgiver.name,
  });

  document.getElementById('kommune').value = res.arbeidsgiver.companies.kommune;

  const { data } = await supabase.from('skills').select('name, label, category').order('category').order('label');
  ferdigheter = data ?? [];
  synonymer = await hentSynonymer();

  if (jobId) {
    const { data: j } = await supabase.from('jobs').select('*').eq('id', jobId).maybeSingle();
    if (!j) { feil.textContent = 'Fant ikke stillingen.'; }
    else {
      eksisterende = j;
      document.getElementById('overskrift').textContent = 'Rediger stilling';
      document.getElementById('lagre').textContent = j.status === 'published' ? 'Lagre endringer' : 'Til betaling';
      document.getElementById('tittel').value = j.title;
      document.getElementById('beskrivelse').value = j.description;
      document.getElementById('kommune').value = j.kommune;
      document.getElementById('oppstart').value = j.start_date ?? '';
      document.getElementById('utdanning').value = j.education_min;
      document.getElementById('erfaring-min').value = j.experience_min;
      document.getElementById('erfaring-maks').value = j.experience_max;
      document.getElementById('norsk').value = j.norsk_min;
      document.getElementById('engelsk').value = j.engelsk_min;
      document.getElementById('sprak-absolutt').checked = j.language_required;
      document.getElementById('godta').checked = true;
      j.required_skills.forEach((s) => pakrevd.add(s));
      j.nice_skills.forEach((s) => onsket.add(s));
    }
  }
  tegnFerdigheter();
  tegnOnskede();
}

function tegnFerdigheter() {
  const treff = filtrer(ferdigheter, synonymer, document.getElementById('sok').value);
  const grupper = {};
  treff.forEach((f) => { (grupper[f.category] ??= []).push(f); });

  document.getElementById('ferdighetsliste').innerHTML = Object.entries(grupper)
    .map(([kat, liste]) => `
      <p class="kategori">${esc(kat)}</p>
      <div class="merker">
        ${liste.map((f) => `<button class="merke-valg" type="button" data-ferdighet="${esc(f.name)}"
            aria-pressed="${pakrevd.has(f.name)}">${esc(f.label)}</button>`).join('')}
      </div>`).join('');

  document.querySelectorAll('[data-ferdighet]').forEach((k) => {
    k.addEventListener('click', () => {
      const navn = k.dataset.ferdighet;
      if (pakrevd.has(navn)) pakrevd.delete(navn); else pakrevd.add(navn);
      onsket.delete(navn);
      k.setAttribute('aria-pressed', String(pakrevd.has(navn)));
      tegnValgte();
      tegnOnskede();
    });
  });
  tegnValgte();
}

function tegnValgte() {
  const boks = document.getElementById('valgte-pakrevd');
  boks.innerHTML = pakrevd.size
    ? [...pakrevd].map((n) => {
        const f = ferdigheter.find((x) => x.name === n);
        return `<button class="merke-valg" type="button" aria-pressed="true" data-fjern="${esc(n)}">${esc(f?.label ?? n)} ✕</button>`;
      }).join('')
    : '<span class="svak">Ingen valgt ennå</span>';

  boks.querySelectorAll('[data-fjern]').forEach((k) => {
    k.addEventListener('click', () => {
      pakrevd.delete(k.dataset.fjern);
      tegnFerdigheter();
      tegnOnskede();
    });
  });
}

function tegnOnskede() {
  const generelle = ferdigheter.filter((f) => f.category === 'generelt' && !pakrevd.has(f.name));
  document.getElementById('onskede').innerHTML = generelle.map((f) =>
    `<button class="merke-valg" type="button" data-onsket="${esc(f.name)}"
      aria-pressed="${onsket.has(f.name)}">${esc(f.label)}</button>`).join('');

  document.querySelectorAll('[data-onsket]').forEach((k) => {
    k.addEventListener('click', () => {
      const navn = k.dataset.onsket;
      if (onsket.has(navn)) onsket.delete(navn); else onsket.add(navn);
      k.setAttribute('aria-pressed', String(onsket.has(navn)));
    });
  });
}

document.getElementById('sok').addEventListener('input', tegnFerdigheter);

function visSteg(n) {
  steg = n;
  [1, 2, 3].forEach((i) => { document.getElementById(`steg-${i}`).hidden = i !== n; });
  document.querySelectorAll('#spor li').forEach((li, i) => {
    li.toggleAttribute('aria-current', i + 1 === n);
    if (i + 1 === n) li.setAttribute('aria-current', 'step');
    li.dataset.ferdig = i + 1 < n ? 'ja' : 'nei';
  });
  document.getElementById('forrige').hidden = n === 1;
  document.getElementById('neste').hidden = n === 3;
  document.getElementById('lagre').hidden = n !== 3;
  if (n === 3) tegnOppsummering();
  feil.textContent = '';
}

function tegnOppsummering() {
  const navn = (n) => ferdigheter.find((f) => f.name === n)?.label ?? n;
  const rad = (t, v) => `<dt>${esc(t)}</dt><dd>${v}</dd>`;
  document.getElementById('oppsummering').innerHTML = [
    rad('Stilling', esc(document.getElementById('tittel').value)),
    rad('Sted', esc(document.getElementById('kommune').value)),
    rad('Oppstart', document.getElementById('oppstart').value
      ? esc(dato(document.getElementById('oppstart').value)) : 'Etter avtale'),
    rad('Påkrevde ferdigheter', pakrevd.size
      ? [...pakrevd].map((n) => `<span class="merke-valg" style="cursor:default">${esc(navn(n))}</span>`).join(' ')
      : '<span class="svak">Ingen</span>'),
    rad('Ønskede ferdigheter', onsket.size
      ? [...onsket].map((n) => `<span class="merke-valg" style="cursor:default">${esc(navn(n))}</span>`).join(' ')
      : '<span class="svak">Ingen</span>'),
    rad('Utdanning', esc(UTDANNING_TEKST[document.getElementById('utdanning').value])),
    rad('Erfaring', `${esc(document.getElementById('erfaring-min').value)}–${esc(document.getElementById('erfaring-maks').value)} år`),
    rad('Språk', `Norsk: ${esc(SPRAK_TEKST[document.getElementById('norsk').value])}, engelsk: ${esc(SPRAK_TEKST[document.getElementById('engelsk').value])}${document.getElementById('sprak-absolutt').checked ? ' (absolutt krav)' : ''}`),
    rad('Garanterte intervjuer', '10'),
    ...(eksisterende?.status === 'published' ? [] : [rad('Pris', '5 000 kr — Finn tar 10 000 kr for det samme')]),
  ].join('');
}

document.getElementById('neste').addEventListener('click', () => {
  if (steg === 1 && !document.getElementById('tittel').value.trim()) {
    feil.textContent = 'Stillingen trenger en tittel før du går videre.';
    return;
  }
  visSteg(steg + 1);
});

document.getElementById('forrige').addEventListener('click', () => visSteg(steg - 1));

document.getElementById('skjema').addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!document.getElementById('godta').checked) {
    feil.textContent = 'Du må godta intervjugarantien før stillingen kan legges ut.';
    return;
  }

  const knapp = document.getElementById('lagre');
  knapp.disabled = true;
  knapp.textContent = 'Lagrer …';

  const felter = {
    title: document.getElementById('tittel').value.trim(),
    description: document.getElementById('beskrivelse').value.trim(),
    required_skills: [...pakrevd],
    nice_skills: [...onsket],
    education_min: document.getElementById('utdanning').value,
    experience_min: Number(document.getElementById('erfaring-min').value) || 0,
    experience_max: Number(document.getElementById('erfaring-maks').value) || 99,
    kommune: document.getElementById('kommune').value,
    norsk_min: document.getElementById('norsk').value,
    engelsk_min: document.getElementById('engelsk').value,
    language_required: document.getElementById('sprak-absolutt').checked,
    start_date: document.getElementById('oppstart').value || null,
  };

  // Editing keeps the status; the update trigger recomputes every match.
  const { data, error } = eksisterende
    ? await supabase.from('jobs').update(felter).eq('id', jobId).select('id, status').single()
    : await supabase.from('jobs').insert({ ...felter, company_id: res.arbeidsgiver.company_id, status: 'draft' }).select('id, status').single();

  if (error) {
    feil.textContent = `Klarte ikke å lagre stillingen: ${error.message}`;
    knapp.disabled = false;
    knapp.textContent = eksisterende?.status === 'published' ? 'Lagre endringer' : 'Til betaling';
    return;
  }
  location.href = data.status === 'published' ? `./stilling.html?id=${data.id}` : `./betaling.html?id=${data.id}`;
});

visSteg(1);
