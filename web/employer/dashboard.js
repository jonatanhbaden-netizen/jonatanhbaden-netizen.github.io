import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnPlasser } from '/shared/components/grunner.js';
import { esc, tall, siden } from '/shared/format.js';

const res = await krevRolle('arbeidsgiver', './index.html');
if (res) {
  const firma = res.arbeidsgiver.companies;

  tegnTopp({
    vert: './dashboard.html',
    lenker: [{ href: './dashboard.html', tekst: 'Stillinger' }],
    aktiv: './dashboard.html',
    undertittel: res.arbeidsgiver.name,
  });

  document.getElementById('firma').textContent = firma.name;
  document.getElementById('undertekst').textContent = `${firma.kommune} · stillingene dine på Jobbo`;

  const { data: stillinger, error } = await supabase
    .from('job_stats')
    .select('*')
    .eq('company_id', res.arbeidsgiver.company_id)
    .order('published_at', { ascending: false, nullsFirst: false });

  const liste = document.getElementById('liste');

  if (error) {
    liste.innerHTML = `<p class="melding melding-feil">Klarte ikke å hente stillingene: ${esc(error.message)}</p>`;
  } else if (!stillinger.length) {
    liste.innerHTML = `<div class="tom">
      <h3>Ingen stillinger ennå</h3>
      <p class="tekst">Legg ut den første stillingen, så finner Jobbo kvalifiserte søkere til den.</p>
      <a class="knapp" href="./ny-stilling.html">Legg ut ny stilling</a>
    </div>`;
  } else {
    liste.innerHTML = stillinger.map((s) => {
      const utkast = s.status !== 'published';
      const maal = `${utkast ? './betaling.html' : './stilling.html'}?id=${s.job_id}`;
      return `<a class="kort stillingskort" href="${maal}">
        <div class="rad-mellom">
          <h3>${esc(s.title)}</h3>
          ${utkast
            ? '<span class="utkast-merke">Utkast — ikke publisert</span>'
            : `<span class="svak">Publisert ${esc(siden(s.published_at))}</span>`}
        </div>
        ${utkast
          ? '<p class="tekst">Stillingen er ikke publisert ennå. Fullfør betalingen for å åpne den for søkere.</p>'
          : `<div class="rad-mellom">
              <div class="trakt">
                <div class="trakt-steg">
                  <span class="trakt-tall">${tall(s.qualified_count)}</span>
                  <span class="trakt-navn">kvalifiserte matchet</span>
                </div>
                <div class="trakt-steg">
                  <span class="trakt-tall">${tall(s.application_count)}</span>
                  <span class="trakt-navn">har søkt</span>
                </div>
                <div class="trakt-steg">
                  <span class="trakt-tall">${tall(s.interview_count)}</span>
                  <span class="trakt-navn">til intervju</span>
                </div>
              </div>
              <div class="stabel-2" style="justify-items: end">
                ${tegnPlasser(Number(s.booked_interviews), Number(s.guaranteed_interviews), { sma: true })}
                <span class="plasser-tekst">${tall(s.booked_interviews)} av ${tall(s.guaranteed_interviews)} garanterte intervjuer booket</span>
              </div>
            </div>`}
      </a>`;
    }).join('');
  }
}
