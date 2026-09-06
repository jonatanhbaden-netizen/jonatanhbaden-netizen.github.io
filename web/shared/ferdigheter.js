import { supabase } from './supabase.js';

let bufret = null;
let synonymer = null;

/** Skill name -> human label. Fetched once per page load. */
export async function hentEtiketter() {
  if (bufret) return bufret;
  const { data } = await supabase.from('skills').select('name, label');
  bufret = new Map((data ?? []).map((f) => [f.name, f.label]));
  return bufret;
}

/** synonym -> skill name, so «js» finds JavaScript. */
export async function hentSynonymer() {
  if (synonymer) return synonymer;
  const { data } = await supabase.from('skill_synonyms').select('synonym, skill');
  synonymer = new Map((data ?? []).map((s) => [s.synonym, s.skill]));
  return synonymer;
}

/** Filters the vocabulary on label, name or any synonym. */
export function filtrer(ferdigheter, synonymer, sok) {
  const q = sok.trim().toLowerCase();
  if (!q) return ferdigheter;
  const viaSynonym = new Set();
  synonymer.forEach((skill, syn) => { if (syn.includes(q)) viaSynonym.add(skill); });
  return ferdigheter.filter((f) =>
    f.label.toLowerCase().includes(q) || f.name.includes(q) || viaSynonym.has(f.name));
}
