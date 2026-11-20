// Testa o quiz da Trilha com a IA de verdade e o texto real de "A Cartomante" (Wikisource).
// Usa o mesmo prompt do Paginas.bat. Imprime as perguntas para conferir se a IA acerta os fatos.
import { readFileSync } from 'node:fs';
let url = process.env.IA_PROXY_URL || '', tok = process.env.IA_PROXY_TOKEN || '';
if (!url) { console.log('sem IA_PROXY_URL: pulando'); process.exit(0); }
if (!/^https?:\/\//.test(url)) url = 'https://' + url;
url = url.replace(/\/+$/, '');
const bat = readFileSync(new URL('../Paginas.bat', import.meta.url), 'utf8');
const m = bat.match(/\$sys = '(Você cria quizzes[^\n]*)'\r?\n/);
if (!m) throw new Error('prompt do quiz não encontrado no Paginas.bat');
const sys = m[1].replace(/''/g, "'");
const ua = { 'User-Agent': 'Paginas-teste/1.0 (github actions)' };
const pg = await (await fetch('https://pt.wikisource.org/w/api.php?action=parse&page=A_Cartomante&prop=text&format=json&redirects=1&formatversion=2', { headers: ua })).json();
let tx = String(pg.parse && pg.parse.text || '').replace(/<style[\s\S]*?<\/style>/g, '').replace(/<(p|br|div)[^>]*>/g, '\n').replace(/<[^>]+>/g, '').replace(/&#?\w+;/g, ' ').replace(/[ \t]+/g, ' ').replace(/\n{2,}/g, '\n\n').trim();
console.log('texto da Cartomante:', tx.length, 'letras. Começo:', tx.slice(0, 200).replace(/\n/g, ' '));
if (tx.length > 20000) tx = tx.slice(0, 10000) + '\n[…]\n' + tx.slice(-10000);
const usr = 'Livros que a pessoa leu:\n\n### A Cartomante — Machado de Assis\nTRECHOS DO LIVRO:\n' + tx + '\n\nCrie exatamente 6 perguntas no total. Esta é a tentativa 1 (código teste): faça perguntas diferentes das que faria numa tentativa anterior.';
const r = await fetch(url + '/chat', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-App-Token': tok, 'X-App-Versao': 'paginas-teste' }, body: JSON.stringify({ sistema: sys, mensagens: [{ role: 'user', content: usr }] }) });
const j = await r.json().catch(() => ({}));
console.log('HTTP', r.status, j.erro || '');
const t = String(j.texto || '');
const q = JSON.parse(t.slice(t.indexOf('{'), t.lastIndexOf('}') + 1)).q;
q.forEach((x, i) => console.log(`\nQ${i + 1}. ${x.p}\n` + x.o.map((o, k) => `   ${k === x.c ? '✓' : ' '} ${o}`).join('\n')));
console.log('\nválidas:', q.filter(x => x.p && x.o && x.o.length === 5 && x.c >= 0 && x.c < 5).length, 'de', q.length);
