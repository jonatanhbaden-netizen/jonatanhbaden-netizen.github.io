import { supabase } from './supabase.js';

/** A login is either an employer or a candidate, never both. */
export async function hentRolle() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return { session: null, rolle: null };

  const { data: arbeidsgiver } = await supabase
    .from('employer_users')
    .select('id, name, email, company_id, companies(name, kommune, industry)')
    .eq('id', session.user.id)
    .maybeSingle();

  if (arbeidsgiver) return { session, rolle: 'arbeidsgiver', arbeidsgiver };

  const { data: profil } = await supabase
    .from('profiles').select('*').eq('id', session.user.id).maybeSingle();

  if (profil) return { session, rolle: 'kandidat', profil };
  return { session, rolle: null };
}

/** Sends the visitor to the right app, or to login if signed out. */
export async function krevRolle(forventet, innloggingsside) {
  const res = await hentRolle();
  if (!res.session) { location.href = innloggingsside; return null; }
  if (res.rolle !== forventet) {
    location.href = res.rolle === 'arbeidsgiver' ? '/employer/dashboard.html' : '/kandidat/matcher.html';
    return null;
  }
  return res;
}

export async function loggUt(til = '/') {
  await supabase.auth.signOut();
  location.href = til;
}
