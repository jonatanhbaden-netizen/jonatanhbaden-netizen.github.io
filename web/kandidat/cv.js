import { krevRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { tegnCv } from '/shared/cv.js';
import { hentEtiketter } from '/shared/ferdigheter.js';

const res = await krevRolle('kandidat', './index.html');
if (res) {
  tegnTopp({
    vert: './matcher.html',
    lenker: [
      { href: './matcher.html', tekst: 'Matcher' },
      { href: './soknader.html', tekst: 'Søknader' },
      { href: './profil.html', tekst: 'Profil' },
    ],
  });
  document.getElementById('cv').innerHTML = tegnCv(res.profil, { etiketter: await hentEtiketter() });
  document.getElementById('skriv-ut').addEventListener('click', () => window.print());
}
