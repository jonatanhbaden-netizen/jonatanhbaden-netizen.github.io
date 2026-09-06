import { supabase } from '/shared/supabase.js';
import { hentRolle } from '/shared/auth.js';
import { tegnTopp } from '/shared/components/topp.js';
import { esc, siden } from '/shared/format.js';

const feil = document.getElementById('feil');
const ok = document.getElementById('ok');

const res = await hentRolle();
if (!res.session) location.href = '/kandidat/index.html';

const kandidat = res.rolle === 'kandidat';
tegnTopp({
  vert: kandidat ? '/kandidat/matcher.html' : '/employer/dashboard.html',
  lenker: kandidat
    ? [{ href: '/kandidat/matcher.html', tekst: 'Matcher' }, { href: '/kandidat/soknader.html', tekst: 'Søknader' }, { href: '/kandidat/profil.html', tekst: 'Profil' }]
    : [{ href: '/employer/dashboard.html', tekst: 'Stillinger' }],
  aktiv: '/konto/index.html',
});
document.getElementById('hvem').textContent = res.session.user.email;

const { data: varsler } = await supabase.from('notifications')
  .select('subject, body, path, status, created_at').order('created_at', { ascending: false }).limit(30);
const VARSEL_STATUS = { venter: 'venter på e-post', sendt: 'sendt', feilet: 'feilet' };
document.getElementById('varsler').innerHTML = varsler?.length
  ? varsler.map((v) => `<li>
      <div class="rad-mellom"><strong>${esc(v.subject)}</strong><span class="svak">${esc(siden(v.created_at))} · ${esc(VARSEL_STATUS[v.status] ?? v.status)}</span></div>
      <span class="tekst" style="font-size: var(--t-sm)">${esc(v.body)}</span>
      <a class="svak" href="${esc(v.path)}">Åpne</a>
    </li>`).join('')
  : '<li class="svak">Ingen varsler ennå.</li>';

document.getElementById('passord-skjema').addEventListener('submit', async (e) => {
  e.preventDefault();
  feil.textContent = ''; ok.textContent = '';
  const { error } = await supabase.auth.updateUser({ password: document.getElementById('passord').value });
  if (error) { feil.textContent = `Klarte ikke å lagre: ${error.message}`; return; }
  ok.textContent = 'Passordet er endret.';
  document.getElementById('passord').value = '';
});

document.getElementById('eksporter').addEventListener('click', async () => {
  feil.textContent = ''; ok.textContent = '';
  const { data, error } = await supabase.rpc('export_my_data');
  if (error) { feil.textContent = `Klarte ikke å hente dataene: ${error.message}`; return; }
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `jobbo-${new Date().toISOString().slice(0, 10)}.json`;
  a.click();
  URL.revokeObjectURL(a.href);
  ok.textContent = 'Filen er lastet ned.';
});

const bekreft = document.getElementById('bekreft');
const slett = document.getElementById('slett');
bekreft.addEventListener('input', () => { slett.disabled = bekreft.value.trim() !== 'SLETT'; });

slett.addEventListener('click', async () => {
  feil.textContent = '';
  slett.disabled = true;
  const { error } = await supabase.rpc('delete_my_account');
  if (error) { feil.textContent = `Klarte ikke å slette: ${esc(error.message)}`; slett.disabled = false; return; }
  await supabase.auth.signOut();
  location.href = '/?slettet=1';
});
