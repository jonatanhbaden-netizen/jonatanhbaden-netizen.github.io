import { supabase } from '/shared/supabase.js';
import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnGrunner, tegnScore, tegnPlasser } from '/shared/components/grunner.js';
import { MAKS_AKTIVE_SOKNADER } from '/shared/config.js';
import { esc, dato } from '/shared/format.js';

const feil = document.getElementById('feil');
const ok = document.getElementById('ok');
const AKTIVE = ['sendt', 'sett', 'intervju'];

const res = await krevRolle('kandidat', './index.html');
if (res) {
  tegnTopp({
    vert: './matcher.html',
    lenker: [
      { href: './matcher.html', tekst: 'Matcher' },
      { href: './soknader.html', tekst: 'Søknader' },
      { href: './profil.html', tekst: 'Profil' },
    ],
    aktiv: './matcher.html',
  });
  await tegn();
}

async function tegn() {
  const { count: aktive } = await supabase
    .from('applications')
    .select('id', { count: 'exact', head: true })
    .in('status', AKTIVE);

  const brukt = aktive ?? 0;
  document.getElementById('kvote').innerHTML = `
    ${tegnPlasser(brukt, MAKS_AKTIVE_SOKNADER)}
    <span class="plasser-tekst"><strong>${brukt} av ${MAKS_AKTIVE_SOKNADER}</strong> aktive søknader</span>
    <a class="svak vokser" style="text-align: right" href="./soknader.html">Se søknadene dine</a>`;

  const antallFulle = await tegnFulle();

  const { data: matcher, error } = await supabase.from('my_matches').select('*');
  const liste = document.getElementById('liste');

  if (error) {
    liste.innerHTML = `<p class="melding melding-feil">Klarte ikke å hente matchene: ${esc(error.message)}</p>`;
    return;
  }

  if (!matcher.length) {
    // Three different reasons for an empty list, three different messages.
    const tomProfil = brukt === 0 && antallFulle === 0;
    const altFullt = brukt === 0 && antallFulle > 0;
    liste.innerHTML = `<div class="tom">
      <h3>${tomProfil ? 'Fyll ut profilen for å få matcher' : altFullt ? 'Stillingene du passer til er fulle akkurat nå' : 'Ingen nye matcher akkurat nå'}</h3>
      <p class="tekst">${tomProfil
        ? 'Vi trenger ferdighetene og erfaringen din for å finne jobber du faktisk er kvalifisert til.'
        : altFullt
        ? 'Hver stilling viser seg for et begrenset antall kandidater. Du får plass så snart noen faller fra, eller når fordelingen kjøres på nytt hver natt. Flere ferdigheter i profilen gir deg flere stillinger å konkurrere om.'
        : 'Du har søkt på de jobbene som passer deg best. Nye stillinger dukker opp her når de legges ut.'}</p>
      ${tomProfil || altFullt ? '<a class="knapp" href="./profil.html">' + (tomProfil ? 'Fyll ut profilen' : 'Utvid profilen') + '</a>' : ''}
    </div>`;
    return;
  }

  liste.innerHTML = matcher.map((m) => `
    <article class="kort matchkort">
      <div class="rad-mellom">
        <div>
          <h2>${esc(m.title)}</h2>
          <p class="firma">${esc(m.company_name)} · ${esc(m.kommune)}</p>
        </div>
        ${tegnScore(m.score)}
      </div>
      <p class="tekst">${esc((m.description ?? '').slice(0, 220))}${(m.description ?? '').length > 220 ? '…' : ''}</p>
      <div class="stabel-2">
        <span class="derfor">Derfor passer du</span>
        ${tegnGrunner(m.reasons)}
      </div>
      <div class="rad-mellom">
        <span class="svak">${m.start_date ? `Oppstart ${esc(dato(m.start_date))}` : 'Oppstart etter avtale'}</span>
        <button class="knapp" data-sok="${m.job_id}" data-tittel="${esc(m.title)}" ${m.external_url ? `data-ekstern="${esc(m.external_url)}"` : ''}>${m.external_url ? 'Søk hos Arbeidsplassen' : 'Søk på jobben'}</button>
      </div>
    </article>`).join('');

  document.querySelectorAll('[data-sok]').forEach((k) => {
    k.addEventListener('click', async () => {
      feil.textContent = '';
      ok.textContent = '';
      k.disabled = true;
      k.textContent = 'Sender …';

      const { error: sokFeil } = await supabase.from('applications')
        .insert({ job_id: k.dataset.sok, profile_id: res.session.user.id });

      if (sokFeil) {
        // The database rules speak Norwegian; show what they said.
        feil.textContent = sokFeil.message.replace(/^.*?:\s*/, '');
        k.disabled = false;
        k.textContent = 'Søk på jobben';
        return;
      }
      // Imported jobs take the application at the source; we only count the slot.
      if (k.dataset.ekstern) window.open(k.dataset.ekstern, '_blank', 'noopener');
      ok.textContent = k.dataset.ekstern
        ? `Plassen er registrert. Fullfør søknaden på ${k.dataset.tittel} hos Arbeidsplassen i fanen som åpnet.`
        : `Søknaden på ${k.dataset.tittel} er sendt.`;
      await tegn();
    });
  });
}

// Forklaringen til den som ikke kom med: terskelen stillingen endte på.
async function tegnFulle() {
  const seksjon = document.getElementById('fulle');
  const { data: fulle } = await supabase.from('my_missed').select('*');
  seksjon.hidden = !fulle?.length;
  if (!fulle?.length) return 0;
  document.getElementById('fulle-liste').innerHTML = fulle.map((f) => `
    <li class="rad-mellom">
      <span><strong>${esc(f.title)}</strong> <span class="svak">· ${esc(f.company_name)}</span></span>
      <span class="svak">${f.cutoff_score > 0
        ? `Laveste på lista ${f.cutoff_score} · din ${f.score}`
        : `Har fått alle søkerne den kan ta · din ${f.score}`}</span>
    </li>`).join('');
  return fulle.length;
}
