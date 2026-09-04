import { loggUt } from '../auth.js';
import { esc } from '../format.js';

/**
 * Renders the signed-in top bar into <header class="topp">.
 * lenker: [{ href, tekst }], aktiv: href of the current page.
 */
export function tegnTopp({ vert, lenker = [], aktiv = '', undertittel = '' }) {
  const header = document.querySelector('.topp .innhold');
  header.innerHTML = `
    <a class="merke" href="${esc(vert)}">Jobbo<span class="merke-punkt" aria-hidden="true"></span></a>
    <nav>
      ${lenker.map((l) => `<a href="${esc(l.href)}"${l.href === aktiv ? ' aria-current="page"' : ''}>${esc(l.tekst)}</a>`).join('')}
      ${undertittel ? `<span class="svak">${esc(undertittel)}</span>` : ''}
      <button class="knapp knapp-3" type="button" id="logg-ut">Logg ut</button>
    </nav>`;
  document.getElementById('logg-ut').addEventListener('click', () => loggUt(vert));
}
