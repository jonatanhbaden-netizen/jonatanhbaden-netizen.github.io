const DATO = new Intl.DateTimeFormat('nb-NO', { day: '2-digit', month: 'short', year: 'numeric' });
const DATO_KORT = new Intl.DateTimeFormat('nb-NO', { day: '2-digit', month: '2-digit', year: 'numeric' });
const TALL = new Intl.NumberFormat('nb-NO');

export const dato = (v) => (v ? DATO.format(new Date(v)) : '');
export const datoKort = (v) => (v ? DATO_KORT.format(new Date(v)) : '');
export const tall = (n) => TALL.format(n ?? 0);
export const kroner = (n) => `${TALL.format(n ?? 0)} kr`;

export function siden(v) {
  if (!v) return '';
  const dager = Math.floor((Date.now() - new Date(v)) / 86400000);
  if (dager <= 0) return 'i dag';
  if (dager === 1) return 'i går';
  if (dager < 7) return `for ${dager} dager siden`;
  const uker = Math.floor(dager / 7);
  return uker === 1 ? 'for en uke siden' : `for ${uker} uker siden`;
}

export const STATUS_TEKST = {
  sendt: 'Sendt',
  sett: 'Sett av arbeidsgiver',
  intervju: 'Intervju',
  tilbud: 'Tilbud',
  avslag: 'Avslag',
};

export const UTDANNING_TEKST = {
  grunnskole: 'Grunnskole',
  videregaende: 'Videregående',
  fagbrev: 'Fagbrev',
  bachelor: 'Bachelorgrad',
  master: 'Mastergrad',
  phd: 'Doktorgrad',
};

export const SPRAK_TEKST = {
  ingen: 'Ingen',
  grunnleggende: 'Grunnleggende',
  god: 'God',
  flytende: 'Flytende',
  morsmal: 'Morsmål',
};

export function periode(fra, til) {
  const f = fra ? new Date(fra).getFullYear() : '';
  const t = til ? new Date(til).getFullYear() : 'nå';
  return `${f} – ${t}`;
}

/** Escapes text before it goes into innerHTML. */
export function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}
