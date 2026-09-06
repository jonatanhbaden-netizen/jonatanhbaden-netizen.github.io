/**
 * Shared sign-up flow. The role and its fields travel as user metadata;
 * the database trigger handle_new_user() turns them into a profile or a
 * company + employer row. Nothing about the account is created client-side.
 */
export function registrer({ supabase, redirect, meta }) {
  const feil = document.getElementById('feil');
  const ok = document.getElementById('ok');
  const send = document.getElementById('send');

  document.getElementById('skjema').addEventListener('submit', async (e) => {
    e.preventDefault();
    feil.textContent = '';
    ok.textContent = '';
    send.disabled = true;
    send.textContent = 'Oppretter …';

    const { data, error } = await supabase.auth.signUp({
      email: document.getElementById('epost').value.trim(),
      password: document.getElementById('passord').value,
      options: { data: meta(), emailRedirectTo: `${location.origin}${redirect}` },
    });

    if (error) {
      feil.textContent = error.message.includes('already registered')
        ? 'Det finnes allerede en konto med denne e-posten. Logg inn i stedet.'
        : `Klarte ikke å opprette kontoen: ${error.message}`;
      send.disabled = false;
      send.textContent = 'Opprett konto';
      return;
    }

    if (data.session) { location.href = redirect; return; }

    // No session means confirmation is on. The database confirms new accounts
    // itself, so a plain login works; if it does not, the e-mail is the way in.
    const { error: innFeil } = await supabase.auth.signInWithPassword({
      email: document.getElementById('epost').value.trim(),
      password: document.getElementById('passord').value,
    });
    if (!innFeil) { location.href = redirect; return; }
    ok.textContent = 'Kontoen er opprettet. Sjekk e-posten din og trykk på bekreftelseslenken for å logge inn.';
    send.textContent = 'Sendt';
  });
}
