import { supabase } from '/shared/supabase.js';

const feil = document.getElementById('feil');
const ok = document.getElementById('ok');
const send = document.getElementById('send');

document.getElementById('skjema').addEventListener('submit', async (e) => {
  e.preventDefault();
  feil.textContent = '';
  send.disabled = true;
  const { error } = await supabase.auth.resetPasswordForEmail(
    document.getElementById('epost').value.trim(),
    { redirectTo: `${location.origin}/konto/nytt-passord.html` },
  );
  if (error) { feil.textContent = `Klarte ikke å sende: ${error.message}`; send.disabled = false; return; }
  ok.textContent = 'Hvis e-posten finnes hos oss, har du nå fått en lenke. Sjekk innboksen.';
});
