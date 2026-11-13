// Servidor social do Páginas (Cloudflare Worker + banco D1).
// Contas pelo Google, tempo de leitura contado pelo relógio do servidor, rankings, amigos, posts e comunidades.
// Publicado automaticamente pelo GitHub Actions (veja LEIA-ME.md).

const MIN_PULSO = 50;        // segundos mínimos entre dois pulsos de leitura
const MAX_PULSO = 150;       // depois disso, conta como pausa (não credita)
const CREDITO_MAX = 90;      // no máximo 90 s creditados por pulso
const TETO_DIA = 8 * 3600;   // no máximo 8 h de leitura contadas por dia
const DIA_VALIDO = 5 * 60;   // um dia conta na sequência com pelo menos 5 min lidos
const OCULTAR_COM = 3;       // denúncias para esconder um post ou comentário
const TIPOS = ['texto', 'resenha', 'frase', 'pagina', 'pergunta', 'progresso', 'conquista'];

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
  'Access-Control-Max-Age': '86400',
};
const json = (dados, status = 200) => new Response(JSON.stringify(dados), { status, headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8' } });
class Erro extends Error { constructor(msg, status = 400) { super(msg); this.status = status; } }
const agora = () => Math.floor(Date.now() / 1000);
const novoId = (p) => p + crypto.randomUUID().replace(/-/g, '').slice(0, 16);
const limpa = (s, max) => String(s == null ? '' : s).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, '').trim().slice(0, max);
async function sha(t) {
  const b = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(t));
  return [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, '0')).join('');
}
function diaDe(ts, tz) { return new Date((ts + tz * 60) * 1000).toISOString().slice(0, 10); }
function diaMenos(dia, n) { const d = new Date(dia + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() - n); return d.toISOString().slice(0, 10); }

async function corpo(req) {
  try { const t = await req.text(); return t ? JSON.parse(t) : {}; } catch (e) { throw new Erro('Pedido inválido.'); }
}
async function usuarioDaSessao(req, env) {
  const h = req.headers.get('Authorization') || '';
  const tk = h.startsWith('Bearer ') ? h.slice(7).trim() : '';
  if (!tk) throw new Erro('Entre com sua conta Google.', 401);
  const s = await env.DB.prepare('SELECT u.* FROM sessoes s JOIN usuarios u ON u.id = s.usuario WHERE s.token = ?').bind(await sha(tk)).first();
  if (!s) throw new Erro('Sua sessão expirou. Entre de novo.', 401);
  return s;
}
function publico(u) {
  if (!u) return null;
  return { id: u.id, nome: u.nome, foto: u.foto || '', bio: u.bio || '', cidade: u.cidade || '', estado: u.estado || '', pais: u.pais || '',
    streak: u.streak || 0, melhor: u.melhor || 0, horas: Math.round((u.total_seg || 0) / 360) / 10, nivel: u.nivel || 1, conquistas: u.conquistas || 0,
    lendo: u.lendo || '' };
}
async function limite(env, tabela, coluna, usuario, segundos, max, msg) {
  const r = await env.DB.prepare(`SELECT COUNT(*) n FROM ${tabela} WHERE ${coluna} = ? AND criado > ?`).bind(usuario, agora() - segundos).first();
  if ((r && r.n) >= max) throw new Erro(msg, 429);
}

// ---------- sequência (streak) calculada só com o que o servidor contou ----------
async function atualizaSequencia(env, u, hoje) {
  const r = await env.DB.prepare('SELECT dia FROM dias WHERE usuario = ? AND segundos >= ? AND dia <= ? ORDER BY dia DESC LIMIT 400').bind(u.id, DIA_VALIDO, hoje).all();
  const dias = new Set((r.results || []).map(x => x.dia));
  let d = dias.has(hoje) ? hoje : diaMenos(hoje, 1), n = 0;
  while (dias.has(d)) { n++; d = diaMenos(d, 1); }
  return n;
}
async function sequenciaAtual(env, u) {
  // a sequência guardada vale até ontem; se a pessoa parou, zera na leitura
  const hoje = diaDe(agora(), u.tz);
  if (u.ultimo_dia === hoje || u.ultimo_dia === diaMenos(hoje, 1)) return u.streak || 0;
  return 0;
}

// ---------- rotas ----------
const rotas = [];
const rota = (metodo, padrao, fn, aberta) => rotas.push({ metodo, re: new RegExp('^' + padrao.replace(/:(\w+)/g, '(?<$1>[^/]+)') + '$'), fn, aberta });

rota('GET', '/', async () => ({ ok: true, app: 'paginas-social' }), true);

rota('POST', '/auth/google', async (req, env, p, b) => {
  const at = limpa(b.access_token, 4096);
  if (!at) throw new Erro('Faltou o acesso do Google.');
  const g = await fetch('https://openidconnect.googleapis.com/v1/userinfo', { headers: { Authorization: 'Bearer ' + at } });
  if (!g.ok) throw new Erro('O Google não confirmou sua conta. Entre de novo.', 401);
  const gi = await g.json();
  if (!gi.sub) throw new Erro('O Google não confirmou sua conta.', 401);
  const cf = req.cf || {};
  const tz = Math.max(-720, Math.min(840, parseInt(b.tz, 10) || -180));
  const t = agora();
  let u = await env.DB.prepare('SELECT * FROM usuarios WHERE google_sub = ?').bind(gi.sub).first();
  if (!u) {
    const id = novoId('u');
    await env.DB.prepare('INSERT INTO usuarios (id, google_sub, email, nome, foto, cidade, estado, pais, tz, criado, visto) VALUES (?,?,?,?,?,?,?,?,?,?,?)')
      .bind(id, gi.sub, limpa(gi.email, 200), limpa(gi.name || (gi.email || 'Leitor').split('@')[0], 40), limpa(gi.picture, 500),
        limpa(cf.city, 80), limpa(cf.region, 80), limpa(cf.country, 4), tz, t, t).run();
    u = await env.DB.prepare('SELECT * FROM usuarios WHERE id = ?').bind(id).first();
  } else {
    // a localização vem da rede (Cloudflare), não do que a pessoa digita: é o que vale nos rankings regionais
    await env.DB.prepare('UPDATE usuarios SET email = ?, foto = ?, cidade = COALESCE(NULLIF(?, \'\'), cidade), estado = COALESCE(NULLIF(?, \'\'), estado), pais = COALESCE(NULLIF(?, \'\'), pais), tz = ?, visto = ? WHERE id = ?')
      .bind(limpa(gi.email, 200), limpa(gi.picture, 500), limpa(cf.city, 80), limpa(cf.region, 80), limpa(cf.country, 4), tz, t, u.id).run();
    u = await env.DB.prepare('SELECT * FROM usuarios WHERE id = ?').bind(u.id).first();
  }
  const token = crypto.randomUUID() + crypto.randomUUID();
  await env.DB.prepare('INSERT INTO sessoes (token, usuario, criado) VALUES (?,?,?)').bind(await sha(token), u.id, t).run();
  return { token, eu: { ...publico(u), streak: await sequenciaAtual(env, u) } };
}, true);

rota('GET', '/eu', async (req, env, p, b, u) => ({ eu: { ...publico(u), streak: await sequenciaAtual(env, u) } }));

rota('POST', '/perfil', async (req, env, p, b, u) => {
  const nome = limpa(b.nome, 40) || u.nome, bio = b.bio == null ? u.bio : limpa(b.bio, 160);
  const nivel = Math.max(1, Math.min(999, parseInt(b.nivel, 10) || u.nivel || 1));
  const conq = Math.max(0, Math.min(999, parseInt(b.conquistas, 10) || u.conquistas || 0));
  const lendo = b.lendo == null ? u.lendo : limpa(b.lendo, 160);
  await env.DB.prepare('UPDATE usuarios SET nome = ?, bio = ?, nivel = ?, conquistas = ?, lendo = ? WHERE id = ?').bind(nome, bio, nivel, conq, lendo, u.id).run();
  return { ok: true };
});

rota('POST', '/sair', async (req, env) => {
  const tk = (req.headers.get('Authorization') || '').slice(7).trim();
  await env.DB.prepare('DELETE FROM sessoes WHERE token = ?').bind(await sha(tk)).run();
  return { ok: true };
});

rota('DELETE', '/eu', async (req, env, p, b, u) => {
  const id = u.id;
  const posts = (await env.DB.prepare('SELECT id, comunidade FROM posts WHERE autor = ?').bind(id).all()).results || [];
  const st = [
    env.DB.prepare('DELETE FROM curtidas WHERE usuario = ? OR post IN (SELECT id FROM posts WHERE autor = ?)').bind(id, id),
    env.DB.prepare('DELETE FROM comentarios WHERE autor = ? OR post IN (SELECT id FROM posts WHERE autor = ?)').bind(id, id),
    env.DB.prepare('DELETE FROM posts WHERE autor = ?').bind(id),
    env.DB.prepare('UPDATE comunidades SET membros = membros - 1 WHERE id IN (SELECT comunidade FROM membros WHERE usuario = ?)').bind(id),
    env.DB.prepare('DELETE FROM membros WHERE usuario = ?').bind(id),
    env.DB.prepare('DELETE FROM seguir WHERE seguidor = ? OR seguido = ?').bind(id, id),
    env.DB.prepare('DELETE FROM bloqueios WHERE usuario = ? OR bloqueado = ?').bind(id, id),
    env.DB.prepare('DELETE FROM denuncias WHERE usuario = ?').bind(id),
    env.DB.prepare('DELETE FROM dias WHERE usuario = ?').bind(id),
    env.DB.prepare('DELETE FROM leituras WHERE usuario = ?').bind(id),
    env.DB.prepare('DELETE FROM sessoes WHERE usuario = ?').bind(id),
    env.DB.prepare('DELETE FROM usuarios WHERE id = ?').bind(id),
  ];
  for (const x of posts) if (x.comunidade) st.push(env.DB.prepare('UPDATE comunidades SET posts = posts - 1 WHERE id = ?').bind(x.comunidade));
  await env.DB.batch(st);
  return { ok: true };
});

// ---------- leitura contada pelo servidor ----------
rota('POST', '/leitura/inicio', async (req, env, p, b, u) => {
  const t = agora(), id = novoId('l');
  await env.DB.batch([
    env.DB.prepare('UPDATE leituras SET ativa = 0 WHERE usuario = ? AND ativa = 1').bind(u.id),
    env.DB.prepare('INSERT INTO leituras (id, usuario, livro, autor, inicio, ultimo) VALUES (?,?,?,?,?,?)').bind(id, u.id, limpa(b.livro, 160), limpa(b.autor, 120), t, t),
    env.DB.prepare('UPDATE usuarios SET lendo = ? WHERE id = ?').bind(limpa(b.livro, 160), u.id),
  ]);
  return { sid: id, intervalo: 60 };
});

async function pulso(env, u, b, final) {
  const s = await env.DB.prepare('SELECT * FROM leituras WHERE id = ? AND usuario = ?').bind(limpa(b.sid, 40), u.id).first();
  if (!s || !s.ativa) throw new Erro('Sessão de leitura encerrada. Abra o livro de novo.', 409);
  const t = agora(), gap = t - s.ultimo;
  if (gap < MIN_PULSO && !final) return { creditado: 0, cedo: true };
  let cred = gap <= MAX_PULSO ? Math.min(gap, CREDITO_MAX) : 0;
  if (final && gap < MIN_PULSO) cred = Math.min(gap, CREDITO_MAX);
  const hoje = diaDe(t, u.tz);
  const d = await env.DB.prepare('SELECT segundos FROM dias WHERE usuario = ? AND dia = ?').bind(u.id, hoje).first();
  const ja = d ? d.segundos : 0;
  cred = Math.max(0, Math.min(cred, TETO_DIA - ja));
  const st = [env.DB.prepare('UPDATE leituras SET ultimo = ?, segundos = segundos + ?, ativa = ? WHERE id = ?').bind(t, cred, final ? 0 : 1, s.id)];
  if (cred > 0) {
    st.push(env.DB.prepare('INSERT INTO dias (usuario, dia, segundos) VALUES (?,?,?) ON CONFLICT(usuario, dia) DO UPDATE SET segundos = segundos + excluded.segundos').bind(u.id, hoje, cred));
    st.push(env.DB.prepare('UPDATE usuarios SET total_seg = total_seg + ?, visto = ? WHERE id = ?').bind(cred, t, u.id));
  }
  await env.DB.batch(st);
  let streak = await sequenciaAtual(env, u);
  if (cred > 0 && ja < DIA_VALIDO && ja + cred >= DIA_VALIDO) {
    streak = await atualizaSequencia(env, u, hoje);
    await env.DB.prepare('UPDATE usuarios SET streak = ?, melhor = MAX(melhor, ?), ultimo_dia = ? WHERE id = ?').bind(streak, streak, hoje, u.id).run();
  }
  return { creditado: cred, hoje: ja + cred, streak };
}
rota('POST', '/leitura/pulso', async (req, env, p, b, u) => pulso(env, u, b, false));
rota('POST', '/leitura/fim', async (req, env, p, b, u) => pulso(env, u, b, true));

// ---------- rankings ----------
rota('GET', '/ranking', async (req, env, p, b, u, q) => {
  const tipo = q.get('tipo') === 'streak' ? 'streak' : 'tempo';
  const periodo = ['semana', 'mes', 'total'].includes(q.get('periodo')) ? q.get('periodo') : 'semana';
  const escopo = ['global', 'pais', 'estado', 'cidade', 'amigos'].includes(q.get('escopo')) ? q.get('escopo') : 'global';
  const where = [], args = [];
  if (escopo === 'pais') { where.push('u.pais = ?'); args.push(u.pais); }
  if (escopo === 'estado') { where.push('u.pais = ? AND u.estado = ?'); args.push(u.pais, u.estado); }
  if (escopo === 'cidade') { where.push('u.pais = ? AND u.estado = ? AND u.cidade = ?'); args.push(u.pais, u.estado, u.cidade); }
  if (escopo === 'amigos') { where.push('(u.id = ? OR u.id IN (SELECT seguido FROM seguir WHERE seguidor = ?))'); args.push(u.id, u.id); }
  const hoje = diaDe(agora(), u.tz), ontem = diaMenos(hoje, 1);
  let sql, sargs;
  if (tipo === 'streak') {
    // a sequência só vale se a pessoa leu hoje ou ontem
    sql = `SELECT u.*, u.streak AS valor FROM usuarios u WHERE u.streak > 0 AND u.ultimo_dia >= ?${where.length ? ' AND ' + where.join(' AND ') : ''} ORDER BY u.streak DESC, u.total_seg DESC LIMIT 50`;
    sargs = [ontem, ...args];
  } else if (periodo === 'total') {
    sql = `SELECT u.*, u.total_seg AS valor FROM usuarios u WHERE u.total_seg > 0${where.length ? ' AND ' + where.join(' AND ') : ''} ORDER BY u.total_seg DESC LIMIT 50`;
    sargs = args;
  } else {
    const desde = diaMenos(hoje, periodo === 'semana' ? 6 : 29);
    sql = `SELECT u.*, t.valor FROM (SELECT usuario, SUM(segundos) valor FROM dias WHERE dia >= ? GROUP BY usuario) t JOIN usuarios u ON u.id = t.usuario${where.length ? ' WHERE ' + where.join(' AND ') : ''} ORDER BY t.valor DESC LIMIT 50`;
    sargs = [desde, ...args];
  }
  const r = (await env.DB.prepare(sql).bind(...sargs).all()).results || [];
  const lista = r.map((x, i) => ({ pos: i + 1, valor: x.valor, usuario: publico(x) }));
  let eu = lista.find(x => x.usuario.id === u.id) || null;
  if (!eu) {
    // posição de quem não aparece no top 50
    let meu = 0;
    if (tipo === 'streak') meu = u.ultimo_dia >= ontem ? u.streak : 0;
    else if (periodo === 'total') meu = u.total_seg;
    else { const x = await env.DB.prepare('SELECT SUM(segundos) v FROM dias WHERE usuario = ? AND dia >= ?').bind(u.id, diaMenos(hoje, periodo === 'semana' ? 6 : 29)).first(); meu = (x && x.v) || 0; }
    eu = { pos: null, valor: meu, usuario: publico(u) };
  }
  const local = { cidade: u.cidade, estado: u.estado, pais: u.pais };
  return { tipo, periodo, escopo, lista, eu, local };
});

// ---------- pessoas e amizades ----------
rota('GET', '/usuarios', async (req, env, p, b, u, q) => {
  const termo = limpa(q.get('q'), 40);
  let r;
  if (termo.length >= 2) r = await env.DB.prepare('SELECT * FROM usuarios WHERE nome LIKE ? AND id != ? ORDER BY total_seg DESC LIMIT 20').bind('%' + termo + '%', u.id).all();
  else r = await env.DB.prepare(`SELECT * FROM usuarios WHERE id != ? AND id NOT IN (SELECT seguido FROM seguir WHERE seguidor = ?)
      ORDER BY (pais = ? AND estado = ?) DESC, total_seg DESC LIMIT 12`).bind(u.id, u.id, u.pais, u.estado).all();
  const segue = new Set(((await env.DB.prepare('SELECT seguido FROM seguir WHERE seguidor = ?').bind(u.id).all()).results || []).map(x => x.seguido));
  return { usuarios: (r.results || []).map(x => ({ ...publico(x), eu_sigo: segue.has(x.id) })) };
});

rota('GET', '/usuarios/:id', async (req, env, p, b, u) => {
  const x = await env.DB.prepare('SELECT * FROM usuarios WHERE id = ?').bind(p.id).first();
  if (!x) throw new Erro('Pessoa não encontrada.', 404);
  const [a, c, s, bl] = await Promise.all([
    env.DB.prepare('SELECT COUNT(*) n FROM seguir WHERE seguido = ?').bind(x.id).first(),
    env.DB.prepare('SELECT COUNT(*) n FROM seguir WHERE seguidor = ?').bind(x.id).first(),
    env.DB.prepare('SELECT 1 x FROM seguir WHERE seguidor = ? AND seguido = ?').bind(u.id, x.id).first(),
    env.DB.prepare('SELECT 1 x FROM bloqueios WHERE usuario = ? AND bloqueado = ?').bind(u.id, x.id).first(),
  ]);
  const posts = await listaPosts(env, u, 'p.autor = ?', [x.id], null, 20);
  return { usuario: { ...publico(x), streak: await sequenciaAtual(env, x), seguidores: a.n, seguindo: c.n, eu_sigo: !!s, bloqueado: !!bl, eu: x.id === u.id }, posts };
});

rota('GET', '/usuarios/:id/:lista', async (req, env, p, b, u) => {
  if (!['seguidores', 'seguindo'].includes(p.lista)) throw new Erro('Não encontrado.', 404);
  const sql = p.lista === 'seguidores'
    ? 'SELECT u.* FROM seguir s JOIN usuarios u ON u.id = s.seguidor WHERE s.seguido = ? ORDER BY s.criado DESC LIMIT 200'
    : 'SELECT u.* FROM seguir s JOIN usuarios u ON u.id = s.seguido WHERE s.seguidor = ? ORDER BY s.criado DESC LIMIT 200';
  const r = await env.DB.prepare(sql).bind(p.id).all();
  const segue = new Set(((await env.DB.prepare('SELECT seguido FROM seguir WHERE seguidor = ?').bind(u.id).all()).results || []).map(x => x.seguido));
  return { usuarios: (r.results || []).map(x => ({ ...publico(x), eu_sigo: segue.has(x.id) })) };
});

rota('POST', '/seguir/:id', async (req, env, p, b, u) => {
  if (p.id === u.id) throw new Erro('Você não pode seguir a si mesmo.');
  const x = await env.DB.prepare('SELECT id FROM usuarios WHERE id = ?').bind(p.id).first();
  if (!x) throw new Erro('Pessoa não encontrada.', 404);
  await limite(env, 'seguir', 'seguidor', u.id, 3600, 200, 'Muitas pessoas seguidas em pouco tempo. Tente mais tarde.');
  await env.DB.prepare('INSERT OR IGNORE INTO seguir (seguidor, seguido, criado) VALUES (?,?,?)').bind(u.id, p.id, agora()).run();
  return { ok: true, eu_sigo: true };
});
rota('DELETE', '/seguir/:id', async (req, env, p, b, u) => {
  await env.DB.prepare('DELETE FROM seguir WHERE seguidor = ? AND seguido = ?').bind(u.id, p.id).run();
  return { ok: true, eu_sigo: false };
});
rota('POST', '/bloquear/:id', async (req, env, p, b, u) => {
  if (p.id === u.id) throw new Erro('Não dá para bloquear a si mesmo.');
  await env.DB.batch([
    env.DB.prepare('INSERT OR IGNORE INTO bloqueios (usuario, bloqueado) VALUES (?,?)').bind(u.id, p.id),
    env.DB.prepare('DELETE FROM seguir WHERE (seguidor = ? AND seguido = ?) OR (seguidor = ? AND seguido = ?)').bind(u.id, p.id, p.id, u.id),
  ]);
  return { ok: true, bloqueado: true };
});
rota('DELETE', '/bloquear/:id', async (req, env, p, b, u) => {
  await env.DB.prepare('DELETE FROM bloqueios WHERE usuario = ? AND bloqueado = ?').bind(u.id, p.id).run();
  return { ok: true, bloqueado: false };
});

// ---------- posts ----------
async function listaPosts(env, u, cond, args, antes, lim) {
  const w = [cond, 'p.oculto = 0', 'p.autor NOT IN (SELECT bloqueado FROM bloqueios WHERE usuario = ?)'];
  const a = [...args, u.id];
  if (antes) { w.push('p.criado < ?'); a.push(antes); }
  const r = await env.DB.prepare(`SELECT p.*, u.nome a_nome, u.foto a_foto, u.nivel a_nivel, c.nome c_nome, c.emoji c_emoji,
      EXISTS (SELECT 1 FROM curtidas k WHERE k.post = p.id AND k.usuario = ?) curti
      FROM posts p JOIN usuarios u ON u.id = p.autor LEFT JOIN comunidades c ON c.id = p.comunidade
      WHERE ${w.join(' AND ')} ORDER BY p.criado DESC LIMIT ?`).bind(u.id, ...a, lim).all();
  return (r.results || []).map(x => ({
    id: x.id, tipo: x.tipo, texto: x.texto, livro: x.livro, livro_autor: x.livro_autor, gid: x.gid, pagina: x.pagina, nota: x.nota,
    criado: x.criado, curtidas: x.curtidas, comentarios: x.comentarios, curti: !!x.curti, meu: x.autor === u.id,
    autor: { id: x.autor, nome: x.a_nome, foto: x.a_foto || '', nivel: x.a_nivel || 1 },
    comunidade: x.comunidade ? { id: x.comunidade, nome: x.c_nome, emoji: x.c_emoji } : null,
  }));
}

rota('GET', '/feed', async (req, env, p, b, u, q) => {
  const antes = parseInt(q.get('antes'), 10) || null;
  const posts = await listaPosts(env, u,
    '(p.autor = ? OR p.autor IN (SELECT seguido FROM seguir WHERE seguidor = ?) OR p.comunidade IN (SELECT comunidade FROM membros WHERE usuario = ?))',
    [u.id, u.id, u.id], antes, 30);
  return { posts };
});
rota('GET', '/descobrir', async (req, env, p, b, u, q) => {
  const antes = parseInt(q.get('antes'), 10) || null;
  return { posts: await listaPosts(env, u, "p.comunidade = ''", [], antes, 30) };
});

rota('POST', '/posts', async (req, env, p, b, u) => {
  const tipo = TIPOS.includes(b.tipo) ? b.tipo : 'texto';
  const texto = limpa(b.texto, 2000);
  if (texto.length < 2) throw new Erro('Escreva alguma coisa antes de publicar.');
  await limite(env, 'posts', 'autor', u.id, 3600, 20, 'Você publicou muitas vezes na última hora. Tente mais tarde.');
  const cm = limpa(b.comunidade, 40);
  if (cm) {
    const m = await env.DB.prepare('SELECT 1 x FROM membros WHERE comunidade = ? AND usuario = ?').bind(cm, u.id).first();
    if (!m) throw new Erro('Entre na comunidade para publicar nela.', 403);
  }
  const id = novoId('p'), t = agora();
  const st = [env.DB.prepare('INSERT INTO posts (id, autor, tipo, texto, livro, livro_autor, gid, pagina, nota, comunidade, criado) VALUES (?,?,?,?,?,?,?,?,?,?,?)')
    .bind(id, u.id, tipo, texto, limpa(b.livro, 160), limpa(b.livro_autor, 120), limpa(b.gid, 20), Math.max(0, parseInt(b.pagina, 10) || 0),
      Math.max(0, Math.min(5, parseInt(b.nota, 10) || 0)), cm, t)];
  if (cm) st.push(env.DB.prepare('UPDATE comunidades SET posts = posts + 1 WHERE id = ?').bind(cm));
  await env.DB.batch(st);
  return { post: (await listaPosts(env, u, 'p.id = ?', [id], null, 1))[0] };
});

rota('DELETE', '/posts/:id', async (req, env, p, b, u) => {
  const x = await env.DB.prepare('SELECT * FROM posts WHERE id = ?').bind(p.id).first();
  if (!x || x.autor !== u.id) throw new Erro('Só quem publicou pode apagar.', 403);
  const st = [env.DB.prepare('DELETE FROM posts WHERE id = ?').bind(p.id), env.DB.prepare('DELETE FROM curtidas WHERE post = ?').bind(p.id), env.DB.prepare('DELETE FROM comentarios WHERE post = ?').bind(p.id)];
  if (x.comunidade) st.push(env.DB.prepare('UPDATE comunidades SET posts = posts - 1 WHERE id = ?').bind(x.comunidade));
  await env.DB.batch(st);
  return { ok: true };
});

rota('POST', '/posts/:id/curtir', async (req, env, p, b, u) => {
  const x = await env.DB.prepare('SELECT id FROM posts WHERE id = ? AND oculto = 0').bind(p.id).first();
  if (!x) throw new Erro('Post não encontrado.', 404);
  const ja = await env.DB.prepare('SELECT 1 x FROM curtidas WHERE post = ? AND usuario = ?').bind(p.id, u.id).first();
  if (ja) await env.DB.batch([env.DB.prepare('DELETE FROM curtidas WHERE post = ? AND usuario = ?').bind(p.id, u.id), env.DB.prepare('UPDATE posts SET curtidas = curtidas - 1 WHERE id = ?').bind(p.id)]);
  else await env.DB.batch([env.DB.prepare('INSERT INTO curtidas (post, usuario) VALUES (?,?)').bind(p.id, u.id), env.DB.prepare('UPDATE posts SET curtidas = curtidas + 1 WHERE id = ?').bind(p.id)]);
  const n = await env.DB.prepare('SELECT curtidas FROM posts WHERE id = ?').bind(p.id).first();
  return { curti: !ja, curtidas: n.curtidas };
});

rota('GET', '/posts/:id/comentarios', async (req, env, p, b, u) => {
  const r = await env.DB.prepare(`SELECT c.*, u.nome a_nome, u.foto a_foto FROM comentarios c JOIN usuarios u ON u.id = c.autor
      WHERE c.post = ? AND c.oculto = 0 AND c.autor NOT IN (SELECT bloqueado FROM bloqueios WHERE usuario = ?) ORDER BY c.criado LIMIT 200`).bind(p.id, u.id).all();
  return { comentarios: (r.results || []).map(c => ({ id: c.id, texto: c.texto, criado: c.criado, meu: c.autor === u.id, autor: { id: c.autor, nome: c.a_nome, foto: c.a_foto || '' } })) };
});
rota('POST', '/posts/:id/comentarios', async (req, env, p, b, u) => {
  const texto = limpa(b.texto, 500);
  if (texto.length < 1) throw new Erro('Escreva o comentário.');
  const x = await env.DB.prepare('SELECT id FROM posts WHERE id = ? AND oculto = 0').bind(p.id).first();
  if (!x) throw new Erro('Post não encontrado.', 404);
  await limite(env, 'comentarios', 'autor', u.id, 3600, 60, 'Muitos comentários na última hora. Tente mais tarde.');
  const id = novoId('c');
  await env.DB.batch([
    env.DB.prepare('INSERT INTO comentarios (id, post, autor, texto, criado) VALUES (?,?,?,?,?)').bind(id, p.id, u.id, texto, agora()),
    env.DB.prepare('UPDATE posts SET comentarios = comentarios + 1 WHERE id = ?').bind(p.id),
  ]);
  return { ok: true, id };
});
rota('DELETE', '/comentarios/:id', async (req, env, p, b, u) => {
  const c = await env.DB.prepare('SELECT * FROM comentarios WHERE id = ?').bind(p.id).first();
  if (!c) throw new Erro('Comentário não encontrado.', 404);
  const dono = await env.DB.prepare('SELECT autor FROM posts WHERE id = ?').bind(c.post).first();
  if (c.autor !== u.id && !(dono && dono.autor === u.id)) throw new Erro('Você não pode apagar este comentário.', 403);
  await env.DB.batch([env.DB.prepare('DELETE FROM comentarios WHERE id = ?').bind(p.id), env.DB.prepare('UPDATE posts SET comentarios = comentarios - 1 WHERE id = ?').bind(c.post)]);
  return { ok: true };
});

rota('POST', '/denunciar', async (req, env, p, b, u) => {
  const alvo = limpa(b.alvo, 40);
  const tabela = alvo.startsWith('p') ? 'posts' : alvo.startsWith('c') ? 'comentarios' : '';
  if (!tabela) throw new Erro('Nada para denunciar.');
  const r = await env.DB.prepare('INSERT OR IGNORE INTO denuncias (alvo, usuario, motivo, criado) VALUES (?,?,?,?)').bind(alvo, u.id, limpa(b.motivo, 200), agora()).run();
  if (r.meta && r.meta.changes) {
    await env.DB.prepare(`UPDATE ${tabela} SET denuncias = denuncias + 1, oculto = CASE WHEN denuncias + 1 >= ? THEN 1 ELSE oculto END WHERE id = ?`).bind(OCULTAR_COM, alvo).run();
  }
  return { ok: true };
});

// ---------- comunidades ----------
const comunidadePub = (c, membro) => ({ id: c.id, nome: c.nome, descricao: c.descricao, tema: c.tema, emoji: c.emoji, membros: c.membros, posts: c.posts, eu_membro: !!membro, dono: c.dono });
rota('GET', '/comunidades', async (req, env, p, b, u, q) => {
  const termo = limpa(q.get('q'), 40), minhas = q.get('minhas') === '1';
  let r;
  if (minhas) r = await env.DB.prepare('SELECT c.* FROM membros m JOIN comunidades c ON c.id = m.comunidade WHERE m.usuario = ? ORDER BY c.membros DESC LIMIT 100').bind(u.id).all();
  else if (termo.length >= 2) r = await env.DB.prepare('SELECT * FROM comunidades WHERE nome LIKE ? OR tema LIKE ? OR descricao LIKE ? ORDER BY membros DESC LIMIT 40').bind('%' + termo + '%', '%' + termo + '%', '%' + termo + '%').all();
  else r = await env.DB.prepare('SELECT * FROM comunidades ORDER BY membros DESC, posts DESC LIMIT 40').all();
  const meus = new Set(((await env.DB.prepare('SELECT comunidade FROM membros WHERE usuario = ?').bind(u.id).all()).results || []).map(x => x.comunidade));
  return { comunidades: (r.results || []).map(c => comunidadePub(c, meus.has(c.id))) };
});
rota('POST', '/comunidades', async (req, env, p, b, u) => {
  const nome = limpa(b.nome, 60);
  if (nome.length < 3) throw new Erro('Dê um nome com pelo menos 3 letras.');
  await limite(env, 'comunidades', 'dono', u.id, 86400, 5, 'Você já criou 5 comunidades hoje. Tente amanhã.');
  const igual = await env.DB.prepare('SELECT id FROM comunidades WHERE lower(nome) = lower(?)').bind(nome).first();
  if (igual) throw new Erro('Já existe uma comunidade com esse nome. Procure por ela e entre.');
  const id = novoId('g'), t = agora();
  await env.DB.batch([
    env.DB.prepare('INSERT INTO comunidades (id, nome, descricao, tema, emoji, dono, criado, membros) VALUES (?,?,?,?,?,?,?,1)')
      .bind(id, nome, limpa(b.descricao, 300), limpa(b.tema, 60), limpa(b.emoji, 8) || '📚', u.id, t),
    env.DB.prepare('INSERT INTO membros (comunidade, usuario, criado) VALUES (?,?,?)').bind(id, u.id, t),
  ]);
  return { comunidade: comunidadePub(await env.DB.prepare('SELECT * FROM comunidades WHERE id = ?').bind(id).first(), true) };
});
rota('GET', '/comunidades/:id', async (req, env, p, b, u, q) => {
  const c = await env.DB.prepare('SELECT * FROM comunidades WHERE id = ?').bind(p.id).first();
  if (!c) throw new Erro('Comunidade não encontrada.', 404);
  const m = await env.DB.prepare('SELECT 1 x FROM membros WHERE comunidade = ? AND usuario = ?').bind(c.id, u.id).first();
  const posts = await listaPosts(env, u, 'p.comunidade = ?', [c.id], parseInt(q.get('antes'), 10) || null, 30);
  return { comunidade: comunidadePub(c, m), posts };
});
rota('POST', '/comunidades/:id/entrar', async (req, env, p, b, u) => {
  const c = await env.DB.prepare('SELECT id FROM comunidades WHERE id = ?').bind(p.id).first();
  if (!c) throw new Erro('Comunidade não encontrada.', 404);
  const r = await env.DB.prepare('INSERT OR IGNORE INTO membros (comunidade, usuario, criado) VALUES (?,?,?)').bind(p.id, u.id, agora()).run();
  if (r.meta && r.meta.changes) await env.DB.prepare('UPDATE comunidades SET membros = membros + 1 WHERE id = ?').bind(p.id).run();
  return { ok: true, eu_membro: true };
});
rota('POST', '/comunidades/:id/sair', async (req, env, p, b, u) => {
  const r = await env.DB.prepare('DELETE FROM membros WHERE comunidade = ? AND usuario = ?').bind(p.id, u.id).run();
  if (r.meta && r.meta.changes) await env.DB.prepare('UPDATE comunidades SET membros = membros - 1 WHERE id = ?').bind(p.id).run();
  return { ok: true, eu_membro: false };
});

export default {
  async fetch(req, env) {
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });
    const url = new URL(req.url);
    try {
      for (const r of rotas) {
        if (r.metodo !== req.method) continue;
        const m = url.pathname.replace(/\/+$/, '').match(r.re) || (url.pathname === '/' ? '/'.match(r.re) : null);
        if (!m) continue;
        const params = Object.fromEntries(Object.entries(m.groups || {}).map(([k, v]) => [k, decodeURIComponent(v)]));
        const b = req.method === 'POST' ? await corpo(req) : {};
        const u = r.aberta ? null : await usuarioDaSessao(req, env);
        return json(await r.fn(req, env, params, b, u, url.searchParams));
      }
      return json({ erro: 'Não encontrado.' }, 404);
    } catch (e) {
      if (e instanceof Erro) return json({ erro: e.message }, e.status);
      console.error(e);
      return json({ erro: 'Erro no servidor. Tente de novo.' }, 500);
    }
  },
};
