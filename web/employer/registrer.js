import { supabase } from '/shared/supabase.js';
import { hentRolle } from '/shared/auth.js';
import { registrer } from '/shared/registrering.js';

const { rolle } = await hentRolle();
if (rolle === 'arbeidsgiver') location.href = './dashboard.html';
if (rolle === 'kandidat') location.href = '/kandidat/matcher.html';

registrer({
  supabase,
  redirect: '/employer/dashboard.html',
  meta: () => ({
    rolle: 'arbeidsgiver',
    firma: document.getElementById('firma').value.trim(),
    org_nr: document.getElementById('org-nr').value.replace(/\s/g, ''),
    kommune: document.getElementById('kommune').value,
    bransje: document.getElementById('bransje').value,
    navn: document.getElementById('navn').value.trim(),
  }),
});
