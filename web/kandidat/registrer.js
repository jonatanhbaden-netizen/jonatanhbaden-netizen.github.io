import { supabase } from '/shared/supabase.js';
import { hentRolle } from '/shared/auth.js';
import { registrer } from '/shared/registrering.js';

const { rolle } = await hentRolle();
if (rolle === 'kandidat') location.href = './matcher.html';
if (rolle === 'arbeidsgiver') location.href = '/employer/dashboard.html';

registrer({
  supabase,
  redirect: '/kandidat/matcher.html',
  meta: () => ({
    rolle: 'kandidat',
    fornavn: document.getElementById('fornavn').value.trim(),
    etternavn: document.getElementById('etternavn').value.trim(),
  }),
});
