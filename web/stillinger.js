import { supabase } from '/shared/supabase.js';
import { esc, siden, UTDANNING_TEKST } from '/shared/format.js';
import { hentEtiketter } from '/shared/ferdigheter.js';

const { data: stillinger, error } = await supabase
  .from('jobs')
  .select('id, title, kommune, published_at, required_skills, education_min, companies(name)')
  .eq('status', 'published')
  .order('published_at', { ascending: false });

const liste = document.getElementById('liste');
if (error) {
  document.getElementById('feil').textContent = `Klarte ikke å hente stillingene: ${error.message}`;
} else if (!stillinger.length) {
  liste.innerHTML = '<div class="tom"><h3>Ingen stillinger ute akkurat nå</h3></div>';
} else {
  const etiketter = await hentEtiketter();
  liste.innerHTML = stillinger.map((s) => `
    <article class="kort stilling">
      <div class="rad-mellom">
        <h2>${esc(s.title)}</h2>
        <span class="svak">${esc(siden(s.published_at))}</span>
      </div>
      <p class="svak">${esc(s.companies?.name ?? '')} · ${esc(s.kommune)} · ${esc(UTDANNING_TEKST[s.education_min] ?? '')}</p>
      ${s.required_skills.length ? `<div class="merker">${s.required_skills.map((f) => `<span class="merke-valg" style="cursor: default">${esc(etiketter.get(f) ?? f)}</span>`).join('')}</div>` : ''}
    </article>`).join('');
}
