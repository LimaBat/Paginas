-- Banco do servidor social do Páginas (Cloudflare D1). Pode rodar de novo sem apagar nada.
CREATE TABLE IF NOT EXISTS usuarios (
  id TEXT PRIMARY KEY, google_sub TEXT UNIQUE NOT NULL, email TEXT, nome TEXT NOT NULL, foto TEXT DEFAULT '', bio TEXT DEFAULT '',
  cidade TEXT DEFAULT '', estado TEXT DEFAULT '', pais TEXT DEFAULT '', tz INTEGER DEFAULT -180,
  streak INTEGER DEFAULT 0, melhor INTEGER DEFAULT 0, total_seg INTEGER DEFAULT 0, ultimo_dia TEXT DEFAULT '',
  nivel INTEGER DEFAULT 1, conquistas INTEGER DEFAULT 0, lendo TEXT DEFAULT '', criado INTEGER, visto INTEGER);
CREATE INDEX IF NOT EXISTS u_nome ON usuarios(nome);
CREATE INDEX IF NOT EXISTS u_local ON usuarios(pais, estado, cidade);
CREATE TABLE IF NOT EXISTS sessoes (token TEXT PRIMARY KEY, usuario TEXT NOT NULL, criado INTEGER);
CREATE INDEX IF NOT EXISTS s_usuario ON sessoes(usuario);
CREATE TABLE IF NOT EXISTS leituras (id TEXT PRIMARY KEY, usuario TEXT NOT NULL, livro TEXT, autor TEXT, inicio INTEGER, ultimo INTEGER, segundos INTEGER DEFAULT 0, ativa INTEGER DEFAULT 1);
CREATE INDEX IF NOT EXISTS l_usuario ON leituras(usuario, ativa);
CREATE TABLE IF NOT EXISTS dias (usuario TEXT NOT NULL, dia TEXT NOT NULL, segundos INTEGER DEFAULT 0, PRIMARY KEY (usuario, dia));
CREATE INDEX IF NOT EXISTS d_dia ON dias(dia);
CREATE TABLE IF NOT EXISTS seguir (seguidor TEXT NOT NULL, seguido TEXT NOT NULL, criado INTEGER, PRIMARY KEY (seguidor, seguido));
CREATE INDEX IF NOT EXISTS sg_seguido ON seguir(seguido);
CREATE TABLE IF NOT EXISTS bloqueios (usuario TEXT NOT NULL, bloqueado TEXT NOT NULL, PRIMARY KEY (usuario, bloqueado));
CREATE TABLE IF NOT EXISTS posts (
  id TEXT PRIMARY KEY, autor TEXT NOT NULL, tipo TEXT NOT NULL, texto TEXT NOT NULL, livro TEXT DEFAULT '', livro_autor TEXT DEFAULT '', gid TEXT DEFAULT '',
  pagina INTEGER DEFAULT 0, nota INTEGER DEFAULT 0, comunidade TEXT DEFAULT '', criado INTEGER, curtidas INTEGER DEFAULT 0, comentarios INTEGER DEFAULT 0,
  denuncias INTEGER DEFAULT 0, oculto INTEGER DEFAULT 0);
CREATE INDEX IF NOT EXISTS p_autor ON posts(autor, criado);
CREATE INDEX IF NOT EXISTS p_comunidade ON posts(comunidade, criado);
CREATE INDEX IF NOT EXISTS p_criado ON posts(criado);
CREATE TABLE IF NOT EXISTS curtidas (post TEXT NOT NULL, usuario TEXT NOT NULL, PRIMARY KEY (post, usuario));
CREATE TABLE IF NOT EXISTS comentarios (id TEXT PRIMARY KEY, post TEXT NOT NULL, autor TEXT NOT NULL, texto TEXT NOT NULL, criado INTEGER, denuncias INTEGER DEFAULT 0, oculto INTEGER DEFAULT 0);
CREATE INDEX IF NOT EXISTS c_post ON comentarios(post, criado);
CREATE TABLE IF NOT EXISTS denuncias (alvo TEXT NOT NULL, usuario TEXT NOT NULL, motivo TEXT, criado INTEGER, PRIMARY KEY (alvo, usuario));
CREATE TABLE IF NOT EXISTS comunidades (id TEXT PRIMARY KEY, nome TEXT NOT NULL, descricao TEXT DEFAULT '', tema TEXT DEFAULT '', emoji TEXT DEFAULT '📚', dono TEXT, criado INTEGER, membros INTEGER DEFAULT 0, posts INTEGER DEFAULT 0);
CREATE INDEX IF NOT EXISTS cm_membros ON comunidades(membros);
CREATE TABLE IF NOT EXISTS membros (comunidade TEXT NOT NULL, usuario TEXT NOT NULL, criado INTEGER, PRIMARY KEY (comunidade, usuario));
CREATE INDEX IF NOT EXISTS m_usuario ON membros(usuario);
