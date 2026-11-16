// Testa as bibliotecas de verdade (Wikisource e Internet Archive) do jeito que o app usa.
const ok = [], falhas = [];
const conf = (c, m) => (c ? ok : falhas).push(m);
const get = async u => { const r = await fetch(u, { headers: { 'User-Agent': 'Paginas-teste/1.0' } }); if (!r.ok) throw new Error(r.status + ' ' + u); return r; };
const json = async u => (await get(u)).json();
try {
  const base = 'https://pt.wikisource.org/w/api.php';
  const s = await json(`${base}?action=query&format=json&list=search&srnamespace=0&srlimit=30&srprop=&srsearch=Iracema`);
  const tit = s.query.search.map(x => x.title).filter(t => !t.includes('/'));
  console.log('Wikisource busca:', tit.slice(0, 8).join(' | '));
  conf(tit.includes('Iracema'), 'Wikisource acha "Iracema"');
  const rv = await json(`${base}?action=query&format=json&prop=revisions&rvprop=content&rvslots=main&titles=${encodeURIComponent(tit.slice(0, 6).join('|'))}`);
  const pg = Object.values(rv.query.pages).find(p => p.title === 'Iracema');
  const wt = pg && pg.revisions[0].slots.main['*'];
  const m = String(wt).slice(0, 6000).match(/\|\s*(?:autor|author)\s*=\s*(?:\[\[\s*(?:Autor|Author)\s*:\s*)?([^|\]\n}]+)/i) || String(wt).match(/\[\[\s*(?:Autor|Author)\s*:\s*([^|\]]+)/i);
  console.log('Wikisource autor:', m && m[1], '| início do cabeçalho:', String(wt).slice(0, 160).replace(/\n/g, ' '));
  conf(m && /Alencar/.test(m[1]), 'Wikisource: autor no cabeçalho');
  const p = await json(`${base}?action=parse&format=json&prop=text&disableeditsection=1&redirects=1&page=Iracema`);
  const html = p.parse.text['*'];
  const links = [...html.matchAll(/href="([^"]+)"/g)].map(x => { try { return decodeURIComponent(x[1]); } catch (e) { return x[1]; } }).filter(h => h.startsWith('/wiki/Iracema/'));
  console.log('Wikisource capítulos:', links.length, links.slice(0, 5).join(' '));
  conf(links.length >= 5, 'Wikisource: sumário com capítulos');
  if (links[0]) {
    const c = await json(`${base}?action=parse&format=json&prop=text&disableeditsection=1&redirects=1&page=${encodeURIComponent(links[0].slice(6).split('#')[0])}`);
    const t = c.parse.text['*'].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');
    console.log('Wikisource capítulo 1:', t.slice(0, 300));
    conf(t.length > 800, 'Wikisource: texto do capítulo');
  }
} catch (e) { falhas.push('Wikisource: ' + e.message); }
try {
  const q = '(title:(Iracema) OR creator:(Iracema)) AND mediatype:texts AND language:(por) AND NOT collection:(inlibrary OR printdisabled OR lendinglibrary OR gutenberg)';
  const s = await json('https://archive.org/advancedsearch.php?q=' + encodeURIComponent(q) + '&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=language&fl[]=downloads&fl[]=year&rows=24&page=1&sort[]=downloads+desc&output=json');
  const docs = s.response.docs;
  console.log('Internet Archive busca:', s.response.numFound, docs.slice(0, 5).map(d => d.identifier + ' [' + d.title + ']').join(' | '));
  conf(docs.length > 0, 'Internet Archive acha livros em português');
  let achou = false;
  for (const d of docs.slice(0, 6)) {
    const md = await json('https://archive.org/metadata/' + encodeURIComponent(d.identifier));
    const f = (md.files || []).find(x => /_djvu\.txt$/i.test(x.name)) || (md.files || []).find(x => x.format === 'DjVuTXT');
    const restrito = md.is_dark || String((md.metadata || {})['access-restricted-item']) === 'true';
    console.log('  ', d.identifier, '| texto:', f ? f.name : 'não', '| restrito:', restrito);
    if (f && !restrito) {
      const t = await (await get('https://archive.org/download/' + encodeURIComponent(d.identifier) + '/' + f.name.split('/').map(encodeURIComponent).join('/'))).text();
      console.log('   texto baixado:', t.length, 'letras:', t.slice(0, 200).replace(/\s+/g, ' '));
      achou = t.length > 2000; break;
    }
  }
  conf(achou, 'Internet Archive: texto livre baixado');
} catch (e) { falhas.push('Internet Archive: ' + e.message); }
console.log('\nOK:', ok.join(' · '));
if (falhas.length) { console.log('FALHAS:', falhas.join(' · ')); process.exitCode = 1; } else console.log('TESTE DAS FONTES OK');
