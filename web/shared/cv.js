import { esc, periode, dato, UTDANNING_TEKST, SPRAK_TEKST } from './format.js';

const somListe = (v) => (Array.isArray(v) ? v : []);

/** Renders a profile as a CV. Same markup everywhere the CV appears. */
export function tegnCv(p, { etiketter } = {}) {
  const utdanning = somListe(p.education);
  const erfaring = somListe(p.experience);
  const ferdigheter = somListe(p.skills);

  return `
    <header class="cv-hode">
      <span class="cv-navn">${esc(`${p.first_name} ${p.last_name}`.trim()) || 'Uten navn'}</span>
      <div class="cv-kontakt">
        ${p.email ? `<span>${esc(p.email)}</span>` : ''}
        ${p.phone ? `<span>${esc(p.phone)}</span>` : ''}
        ${p.kommune ? `<span>${esc(p.kommune)}</span>` : ''}
      </div>
    </header>

    ${p.about ? `<p class="tekst">${esc(p.about)}</p>` : ''}

    <section class="cv-seksjon">
      <h3>Erfaring</h3>
      ${erfaring.length ? erfaring.map((e) => `
        <div class="cv-post">
          <span class="cv-post-tittel">${esc(e.title ?? '')}</span>
          <span class="cv-post-sted">${esc(e.company ?? '')}</span>
          <span class="cv-post-tid">${esc(periode(e.from, e.to))}</span>
          ${e.description ? `<p class="tekst" style="font-size: var(--t-sm)">${esc(e.description)}</p>` : ''}
        </div>`).join('')
        : '<p class="cv-tom">Ingen erfaring lagt inn ennå.</p>'}
    </section>

    <section class="cv-seksjon">
      <h3>Utdanning</h3>
      ${utdanning.length ? utdanning.map((u) => `
        <div class="cv-post">
          <span class="cv-post-tittel">${esc(u.title ?? '')}</span>
          <span class="cv-post-sted">${esc(u.institution ?? '')}</span>
          <span class="cv-post-tid">${esc(periode(u.from, u.to))}</span>
        </div>`).join('')
        : '<p class="cv-tom">Ingen utdanning lagt inn ennå.</p>'}
    </section>

    <section class="cv-seksjon">
      <h3>Ferdigheter</h3>
      ${ferdigheter.length
        ? `<ul class="merker" style="list-style: none; margin: 0; padding: 0">
             ${ferdigheter.map((f) => `<li class="merke-valg" style="cursor: default">${esc(etiketter?.get(f) ?? f)}</li>`).join('')}
           </ul>`
        : '<p class="cv-tom">Ingen ferdigheter valgt ennå.</p>'}
    </section>

    <section class="cv-seksjon">
      <h3>Om kandidaten</h3>
      <dl class="cv-fakta">
        <div><dt>Høyeste utdanning</dt><dd>${esc(UTDANNING_TEKST[p.highest_education] ?? '—')}</dd></div>
        <div><dt>Norsk</dt><dd>${esc(SPRAK_TEKST[p.norsk] ?? '—')}</dd></div>
        <div><dt>Engelsk</dt><dd>${esc(SPRAK_TEKST[p.engelsk] ?? '—')}</dd></div>
        <div><dt>Tilgjengelig fra</dt><dd>${p.available_from ? esc(dato(p.available_from)) : 'Nå'}</dd></div>
        ${somListe(p.acceptable_kommuner).length
          ? `<div><dt>Åpen for jobb i</dt><dd>${esc(somListe(p.acceptable_kommuner).join(', '))}</dd></div>` : ''}
      </dl>
    </section>`;
}
