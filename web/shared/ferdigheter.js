import { supabase } from './supabase.js';

let bufret = null;

/** Skill name -> human label. Fetched once per page load. */
export async function hentEtiketter() {
  if (bufret) return bufret;
  const { data } = await supabase.from('skills').select('name, label');
  bufret = new Map((data ?? []).map((f) => [f.name, f.label]));
  return bufret;
}
