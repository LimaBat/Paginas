import fs from 'node:fs';
import { criarD1 } from './d1.mjs';
const W = (await import(new URL('../worker.js', import.meta.url))).default;
const env = { DB: criarD1(fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8')) };
// Google falso
const contas = { ana: { sub: '1', email: 'ana@x', name: 'Ana', picture: '' }, beto: { sub: '2', email: 'b@x', name: 'Beto', picture: '' }, caio: { sub: '3', email: 'c@x', name: 'Caio' } };
const _f = globalThis.fetch;
globalThis.fetch = async (u, o) => { const t = o.headers.Authorization.slice(7); return contas[t] ? new Response(JSON.stringify(contas[t])) : new Response('{}', { status: 401 }); };
let relogio = 1_800_000_000; Date.now = () => relogio * 1000;
const anda = s => { relogio += s; };
async function chama(met, path, body, tk, cf) {
  const req = new Request('https://x.dev' + path, { method: met, headers: tk ? { Authorization: 'Bearer ' + tk } : {}, body: body ? JSON.stringify(body) : undefined });
  if (cf) Object.defineProperty(req, 'cf', { value: cf });
  const r = await W.fetch(req, env); const tx = await r.text(); return { s: r.status, j: tx ? JSON.parse(tx) : {} };
}
const ok = (c, m) => { if (!c) { console.log('FALHOU:', m); process.exitCode = 1; } else console.log('ok -', m); };
const SP = { city: 'Campinas', region: 'São Paulo', country: 'BR' }, RJ = { city: 'Niterói', region: 'Rio de Janeiro', country: 'BR' };
const A = await chama('POST', '/auth/google', { access_token: 'ana', tz: -180 }, null, SP);
const B = await chama('POST', '/auth/google', { access_token: 'beto', tz: -180 }, null, SP);
const C = await chama('POST', '/auth/google', { access_token: 'caio', tz: -180 }, null, RJ);
ok(A.s === 200 && A.j.token && A.j.eu.cidade === 'Campinas', 'login com Google e cidade pela rede');
ok((await chama('POST', '/auth/google', { access_token: 'falso' })).s === 401, 'token Google falso recusado');
ok((await chama('GET', '/eu', null, 'inventado')).s === 401, 'sessão inventada recusada');
const ta = A.j.token, tb = B.j.token, tc = C.j.token;
// leitura: Ana lê 10 min com pulsos de 60 s
let s = (await chama('POST', '/leitura/inicio', { livro: 'Dom Casmurro', autor: 'Machado' }, ta)).j.sid;
for (let i = 0; i < 10; i++) { anda(60); await chama('POST', '/leitura/pulso', { sid: s }, ta); }
let p = await chama('POST', '/leitura/pulso', { sid: s }, ta);
ok(p.j.cedo, 'pulso rápido demais não conta');
anda(60); p = await chama('POST', '/leitura/pulso', { sid: s }, ta);
ok(p.j.hoje === 660 && p.j.streak === 1, 'leitura contada pelo servidor (11 min) e sequência 1: ' + JSON.stringify(p.j));
anda(1000); p = await chama('POST', '/leitura/pulso', { sid: s }, ta);
ok(p.j.creditado === 0, 'pausa longa não credita');
// tentativa de forjar: pulsos sem esperar
s = (await chama('POST', '/leitura/inicio', { livro: 'X' }, tb)).j.sid;
for (let i = 0; i < 50; i++) await chama('POST', '/leitura/pulso', { sid: s }, tb);
ok((await chama('GET', '/eu', null, tb)).j.eu.horas === 0, 'pulsos em rajada não somam tempo');
anda(70); await chama('POST', '/leitura/pulso', { sid: s }, tb);
// sessão antiga fica inválida ao abrir outra
const s2 = (await chama('POST', '/leitura/inicio', { livro: 'Y' }, tb)).j.sid;
ok((await chama('POST', '/leitura/pulso', { sid: s }, tb)).s === 409, 'só uma leitura ativa por conta');
// teto diário
s = (await chama('POST', '/leitura/inicio', { livro: 'Z' }, tc)).j.sid;
for (let i = 0; i < 400; i++) { anda(90); await chama('POST', '/leitura/pulso', { sid: s }, tc); }
const caio = (await chama('GET', '/eu', null, tc)).j.eu;
ok(caio.horas <= 8, 'teto de 8 h por dia: ' + caio.horas);
// dia seguinte, sequência 2 para Ana
anda(86400); s = (await chama('POST', '/leitura/inicio', { livro: 'Dom Casmurro' }, ta)).j.sid;
for (let i = 0; i < 6; i++) { anda(60); p = await chama('POST', '/leitura/pulso', { sid: s }, ta); }
ok(p.j.streak === 2, 'sequência de 2 dias: ' + p.j.streak);
// rankings
let r = await chama('GET', '/ranking?tipo=tempo&periodo=semana&escopo=global', null, ta);
ok(r.j.lista[0].usuario.nome === 'Caio' && r.j.lista.length === 3, 'ranking global semanal');
r = await chama('GET', '/ranking?tipo=tempo&periodo=semana&escopo=cidade', null, ta);
ok(r.j.lista.every(x => x.usuario.cidade === 'Campinas') && r.j.lista.length === 2, 'ranking da cidade');
r = await chama('GET', '/ranking?tipo=streak&escopo=estado', null, ta);
ok(r.j.lista[0].usuario.nome === 'Ana' && r.j.lista[0].valor === 2, 'ranking de sequência no estado');
r = await chama('GET', '/ranking?tipo=tempo&periodo=total&escopo=amigos', null, ta);
ok(r.j.lista.length === 1, 'ranking de amigos só comigo antes de seguir');
// seguir
const idB = B.j.eu.id, idA = A.j.eu.id, idC = C.j.eu.id;
await chama('POST', '/seguir/' + idB, {}, ta); await chama('POST', '/seguir/' + idC, {}, ta);
r = await chama('GET', '/ranking?tipo=tempo&periodo=total&escopo=amigos', null, ta);
ok(r.j.lista.length === 3, 'ranking de amigos depois de seguir');
const perfil = await chama('GET', '/usuarios/' + idB, null, ta);
ok(perfil.j.usuario.seguidores === 1 && perfil.j.usuario.eu_sigo, 'perfil mostra seguidores');
ok((await chama('GET', '/usuarios?q=bet', null, ta)).j.usuarios[0].nome === 'Beto', 'buscar pessoas');
// posts
let post = await chama('POST', '/posts', { tipo: 'frase', texto: 'Capitu, olhos de ressaca.', livro: 'Dom Casmurro', livro_autor: 'Machado' }, tb);
ok(post.s === 200 && post.j.post.autor.nome === 'Beto', 'publicar frase');
let f = await chama('GET', '/feed', null, ta);
ok(f.j.posts.length === 1, 'feed mostra quem eu sigo');
ok((await chama('GET', '/feed', null, tc)).j.posts.length === 0, 'feed não mostra quem não sigo');
const pid = post.j.post.id;
ok((await chama('POST', '/posts/' + pid + '/curtir', {}, ta)).j.curtidas === 1, 'curtir');
ok((await chama('POST', '/posts/' + pid + '/curtir', {}, ta)).j.curtidas === 0, 'descurtir');
await chama('POST', '/posts/' + pid + '/comentarios', { texto: 'Lindo!' }, ta);
ok((await chama('GET', '/posts/' + pid + '/comentarios', null, tc)).j.comentarios.length === 1, 'comentar');
ok((await chama('DELETE', '/posts/' + pid, null, ta)).s === 403, 'não apaga post dos outros');
// denúncias escondem
const extras = ['d', 'e', 'f'].map((n, i) => { contas[n] = { sub: '9' + i, name: n }; return n; });
const tks = []; for (const n of extras) tks.push((await chama('POST', '/auth/google', { access_token: n }, null, SP)).j.token);
for (const t of tks) await chama('POST', '/denunciar', { alvo: pid }, t);
ok((await chama('GET', '/feed', null, ta)).j.posts.length === 0, '3 denúncias escondem o post');
// bloqueio
const p2 = (await chama('POST', '/posts', { texto: 'oi pessoal' }, tb)).j.post.id;
await chama('POST', '/bloquear/' + idB, {}, ta);
ok((await chama('GET', '/descobrir', null, ta)).j.posts.every(x => x.autor.id !== idB), 'bloqueio esconde posts');
// comunidades
let cm = await chama('POST', '/comunidades', { nome: 'Machado de Assis', descricao: 'Fãs do bruxo', emoji: '🎩' }, tc);
ok(cm.s === 200 && cm.j.comunidade.membros === 1, 'criar comunidade');
const gid = cm.j.comunidade.id;
ok((await chama('POST', '/comunidades', { nome: 'machado de assis' }, ta)).s === 400, 'nome repetido recusado');
ok((await chama('POST', '/posts', { texto: 'quero participar', comunidade: gid }, ta)).s === 403, 'precisa entrar para publicar');
await chama('POST', '/comunidades/' + gid + '/entrar', {}, ta);
await chama('POST', '/posts', { tipo: 'pergunta', texto: 'Capitu traiu?', comunidade: gid }, ta);
const det = await chama('GET', '/comunidades/' + gid, null, tc);
ok(det.j.comunidade.membros === 2 && det.j.posts.length === 1, 'comunidade com 2 membros e 1 post');
ok((await chama('GET', '/feed', null, tc)).j.posts.some(x => x.comunidade && x.comunidade.id === gid), 'posts da comunidade no feed dos membros');
ok((await chama('GET', '/comunidades?q=bruxo', null, ta)).j.comunidades.length === 1, 'buscar comunidades');
// limites e apagar conta
for (let i = 0; i < 20; i++) await chama('POST', '/posts', { texto: 'spam ' + i }, tc);
ok((await chama('POST', '/posts', { texto: 'mais' }, tc)).s === 429, 'limite de posts por hora');
ok((await chama('DELETE', '/eu', null, tc)).s === 200 && (await chama('GET', '/eu', null, tc)).s === 401, 'apagar conta remove tudo');
ok((await chama('GET', '/comunidades/' + gid, null, ta)).j.comunidade.membros === 1, 'contagem de membros após apagar conta');
ok((await chama('OPTIONS', '/feed')).s === 204, 'CORS');
console.log(process.exitCode ? 'TESTE DO SERVIDOR SOCIAL FALHOU' : 'TESTE DO SERVIDOR SOCIAL OK');
