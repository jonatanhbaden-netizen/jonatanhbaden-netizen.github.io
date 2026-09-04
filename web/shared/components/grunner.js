import { esc } from '../format.js';

/** Renders the match reasons. A score is never shown without them. */
export function tegnGrunner(reasons, { maks = 0 } = {}) {
  const liste = Array.isArray(reasons) ? reasons : [];
  const vist = maks ? liste.slice(0, maks) : liste;
  const rest = liste.length - vist.length;
  return `<ul class="grunner">
    ${vist.map((g) => `<li class="grunn ${g.ok ? 'grunn-ja' : 'grunn-nei'}">${esc(g.text)}</li>`).join('')}
    ${rest > 0 ? `<li class="grunn" style="color: var(--ink-3)">+${rest} til</li>` : ''}
  </ul>`;
}

/** The score block. `kvalifisert` drives the green treatment. */
export function tegnScore(score, kvalifisert = score >= 60) {
  return `<span class="score ${kvalifisert ? 'score-ja' : 'score-nei'}">
    <span class="score-tall">${score}</span>
    <span class="score-merkelapp">match</span>
  </span>`;
}

/** Discrete slots, never a percentage bar. */
export function tegnPlasser(fylt, totalt, { sma = false } = {}) {
  let ut = `<span class="plasser ${sma ? 'plass-sma' : ''}" role="img" aria-label="${fylt} av ${totalt}">`;
  for (let i = 0; i < totalt; i += 1) {
    ut += `<span class="plass ${i < fylt ? 'plass-fylt' : ''}"></span>`;
  }
  return `${ut}</span>`;
}
