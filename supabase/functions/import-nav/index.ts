// Imports Oslo-area listings from Arbeidsplassen (NAV) into jobs under a
// system company, so candidates get matched against the whole market.
// Applications to these go to the source URL; Jobbo only counts the slot.
//
// Needs NAV_API_TOKEN (free, from arbeidsplassen.nav.no/api). The feed shape
// follows pam-stilling-feed v1 (JSON Feed); verify against a live token before
// trusting the field names.
import { createClient } from 'npm:@supabase/supabase-js@2';
const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

const KOMMUNER = ['Oslo', 'Bærum', 'Asker', 'Lillestrøm', 'Lørenskog', 'Nordre Follo',
  'Ullensaker', 'Rælingen', 'Nesodden', 'Drammen'];

function tilKommune(m: string | undefined): string | null {
  if (!m) return null;
  const n = m.toLowerCase();
  return KOMMUNER.find((k) => k.toLowerCase() === n) ?? null;
}

function stripHtml(s: string): string {
  return s.replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim();
}

// Whole-word hits on labels and synonyms, most specific (longest) first.
function finnFerdigheter(tekst: string, ordbok: { term: string; skill: string }[]): string[] {
  const t = ` ${tekst.toLowerCase()} `;
  const treff = new Set<string>();
  for (const { term, skill } of ordbok) {
    if (term.length < 3) continue;
    if (t.includes(` ${term} `) || t.includes(` ${term},`) || t.includes(` ${term}.`)) treff.add(skill);
    if (treff.size >= 5) break;
  }
  return [...treff];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const token = Deno.env.get('NAV_API_TOKEN');
  if (!token) return json({ skipped: 'NAV_API_TOKEN mangler' });

  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  let { data: firma } = await admin.from('companies').select('id').eq('name', 'Arbeidsplassen (NAV)').maybeSingle();
  if (!firma) {
    ({ data: firma } = await admin.from('companies')
      .insert({ name: 'Arbeidsplassen (NAV)', kommune: 'Oslo', industry: 'import' }).select('id').single());
  }

  const [{ data: skills }, { data: syn }] = await Promise.all([
    admin.from('skills').select('name, label'),
    admin.from('skill_synonyms').select('synonym, skill'),
  ]);
  const ordbok = [
    ...(skills ?? []).map((s) => ({ term: s.label.toLowerCase(), skill: s.name })),
    ...(syn ?? []).map((s) => ({ term: s.synonym.toLowerCase(), skill: s.skill })),
  ].sort((a, b) => b.term.length - a.term.length);

  const r = await fetch('https://pam-stilling-feed.nav.no/api/v1/feed', {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/json' },
  });
  if (!r.ok) return json({ error: `NAV svarte ${r.status}` }, 502);
  const feed = await r.json();

  let importert = 0, hoppet = 0;
  for (const item of feed.items ?? []) {
    const e = item._feed_entry ?? {};
    const kommune = tilKommune(e.municipal);
    if (!kommune) { hoppet += 1; continue; }

    const tekst = stripHtml(item.content_text ?? item.content_html ?? '');
    const rad = {
      company_id: firma!.id,
      title: e.title ?? item.title ?? 'Uten tittel',
      description: `${e.businessName ? `${e.businessName}. ` : ''}${tekst.slice(0, 2000)}`,
      required_skills: finnFerdigheter(`${item.title} ${tekst}`, ordbok),
      kommune,
      status: e.status === 'ACTIVE' ? 'published' : 'closed',
      published_at: e.sistEndret ?? new Date().toISOString(),
      source: 'nav',
      external_url: item.url,
      external_id: e.uuid ?? item.id,
      price_nok: 0,
    };
    const { error } = await admin.from('jobs').upsert(rad, { onConflict: 'external_id' });
    if (error) hoppet += 1; else importert += 1;
  }
  return json({ importert, hoppet });
});
