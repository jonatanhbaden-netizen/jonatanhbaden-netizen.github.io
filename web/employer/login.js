import { supabase } from '/shared/supabase.js';
import { hentRolle } from '/shared/auth.js';

const skjema = document.getElementById('skjema');
const feil = document.getElementById('feil');
const send = document.getElementById('send');

// Already signed in? Go straight where you belong.
const { rolle } = await hentRolle();
if (rolle === 'arbeidsgiver') location.href = './dashboard.html';
if (rolle === 'kandidat') location.href = '/kandidat/matcher.html';

skjema.addEventListener('submit', async (e) => {
  e.preventDefault();
  feil.textContent = '';
  send.disabled = true;
  send.textContent = 'Logger inn …';

  const { error } = await supabase.auth.signInWithPassword({
    email: document.getElementById('epost').value.trim(),
    password: document.getElementById('passord').value,
  });

  if (error) {
    feil.textContent = 'Fant ingen konto med den e-posten og det passordet. Sjekk at begge er riktige.';
    send.disabled = false;
    send.textContent = 'Logg inn';
    return;
  }

  const res = await hentRolle();
  if (res.rolle !== 'arbeidsgiver') {
    feil.textContent = 'Denne kontoen er en jobbsøkerkonto. Logg inn på jobbsøkersiden i stedet.';
    await supabase.auth.signOut();
    send.disabled = false;
    send.textContent = 'Logg inn';
    return;
  }
  location.href = './dashboard.html';
});
