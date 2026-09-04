import { supabase } from '/shared/supabase.js';
import { hentRolle } from '/shared/auth.js';

const feil = document.getElementById('feil');
const send = document.getElementById('send');

const { rolle } = await hentRolle();
if (rolle === 'kandidat') location.href = './matcher.html';
if (rolle === 'arbeidsgiver') location.href = '/employer/dashboard.html';

document.getElementById('skjema').addEventListener('submit', async (e) => {
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
  if (res.rolle !== 'kandidat') {
    feil.textContent = 'Denne kontoen er en arbeidsgiverkonto. Logg inn på arbeidsgiversiden i stedet.';
    await supabase.auth.signOut();
    send.disabled = false;
    send.textContent = 'Logg inn';
    return;
  }
  location.href = './matcher.html';
});
