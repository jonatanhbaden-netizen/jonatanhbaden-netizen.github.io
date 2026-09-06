import { supabase } from '/shared/supabase.js';
import { hentRolle } from '/shared/auth.js';

const feil = document.getElementById('feil');
const ok = document.getElementById('ok');
const send = document.getElementById('send');

// The recovery link signs the user in via the URL fragment; supabase-js
// picks that up on load. Without a session there is nothing to update.
const { data: { session } } = await supabase.auth.getSession();
if (!session) {
  feil.textContent = 'Lenken er brukt eller utløpt. Be om en ny fra «Glemt passord».';
  send.disabled = true;
}

document.getElementById('skjema').addEventListener('submit', async (e) => {
  e.preventDefault();
  feil.textContent = '';
  send.disabled = true;
  const { error } = await supabase.auth.updateUser({ password: document.getElementById('passord').value });
  if (error) { feil.textContent = `Klarte ikke å lagre: ${error.message}`; send.disabled = false; return; }
  ok.textContent = 'Passordet er lagret. Sender deg videre …';
  const { rolle } = await hentRolle();
  location.href = rolle === 'arbeidsgiver' ? '/employer/dashboard.html' : '/kandidat/matcher.html';
});
