package br.paginas.app;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.GZIPInputStream;
import java.util.zip.InflaterInputStream;

/**
 * Servidor local do Páginas no celular (só 127.0.0.1).
 * Faz exatamente o que a parte em PowerShell do Paginas.bat faz no Windows:
 * mesmos endereços /api/..., mesmos dados (dados.json, livros/, config.json).
 * Não usa nada do Android, para poder ser testado no computador (ferramentas/TesteServidor.java).
 */
public class Servidor {
    public static final int PORTA_PADRAO = 47630;
    static final String MODELO_IA = "claude-haiku-5-5";

    final File pasta, livros, dados, dadosAnt, cfgArq;
    final String html;
    final String token = aleatorio();
    final String chave = aleatorio();   // só quem abre o app (a Activity) conhece: protege a página inicial
    int porta;
    ServerSocket socket;
    final ExecutorService fila = Executors.newCachedThreadPool();
    final Map<String, Object[]> cache = Collections.synchronizedMap(new HashMap<>());
    static final List<String> PARAMS = Arrays.asList("search", "languages", "topic", "page", "sort", "ids");

    // configuração de distribuição (assets/config.json, gerado na publicação por ferramentas/preparar.py)
    final String versao, repo, proxyUrl, proxyToken, gId, gSecret;
    static final String G_AUTH = "https://accounts.google.com/o/oauth2/v2/auth", G_TOKEN = "https://oauth2.googleapis.com/token";
    static final String G_ESCOPO = "openid email profile https://www.googleapis.com/auth/drive.appdata", DRIVE_ARQ = "paginas_dados.json";
    final Map<String, String[]> oauth = Collections.synchronizedMap(new HashMap<>());  // state -> {verificador, hora}
    volatile String gAccess = ""; volatile long gExp = 0;

    public Servidor(File pasta, String htmlModelo, String extraAntesDoFim, Map<?, ?> dist) {
        this.pasta = pasta;
        if (dist == null) dist = new HashMap<>();
        versao = txt(dist.get("versao")).isEmpty() ? "1.0" : txt(dist.get("versao"));
        repo = txt(dist.get("repo"));
        String pu = txt(dist.get("iaProxyUrl")).replaceAll("/+$", "");
        proxyUrl = pu.isEmpty() || pu.matches("(?i)^https?://.*") ? pu : "https://" + pu;
        proxyToken = txt(dist.get("iaProxyToken"));
        gId = txt(dist.get("googleClientId"));
        gSecret = txt(dist.get("googleClientSecret"));
        livros = new File(pasta, "livros");
        livros.mkdirs();
        dados = new File(pasta, "dados.json");
        dadosAnt = new File(pasta, "dados.anterior.json");
        cfgArq = new File(pasta, "config.json");
        String h = htmlModelo.replace("__TOKEN__", token).replace("__VERSAO__", versao).replace("__REPO__", repo).replace("__PLAT__", "android");
        if (extraAntesDoFim != null) {
            int i = h.lastIndexOf("</body>");
            h = i >= 0 ? h.substring(0, i) + extraAntesDoFim + h.substring(i) : h + extraAntesDoFim;
        }
        html = h;
    }

    static String aleatorio() {
        byte[] b = new byte[16];
        new SecureRandom().nextBytes(b);
        StringBuilder s = new StringBuilder();
        for (byte x : b) s.append(String.format("%02x", x));
        return s.toString();
    }

    public String endereco() { return "http://127.0.0.1:" + porta + "/?k=" + chave; }

    /** Abre a porta (tenta algumas se a padrão estiver ocupada) e começa a atender. */
    public void iniciar(int portaPreferida) throws IOException {
        IOException ultimo = null;
        for (int p = portaPreferida; p < portaPreferida + 15; p++) {
            try {
                ServerSocket s = new ServerSocket();
                s.setReuseAddress(true);
                s.bind(new InetSocketAddress(InetAddress.getByName("127.0.0.1"), p), 50);
                socket = s; porta = p; ultimo = null;
                break;
            } catch (IOException e) { ultimo = e; }
        }
        if (ultimo != null || socket == null) throw new IOException("Não foi possível abrir uma porta local.", ultimo);
        Thread t = new Thread(() -> {
            while (!socket.isClosed()) {
                try {
                    Socket c = socket.accept();
                    fila.execute(() -> atender(c));
                } catch (IOException e) { if (socket.isClosed()) break; }
            }
        }, "paginas-servidor");
        t.setDaemon(true);
        t.start();
    }

    public boolean vivo() { return socket != null && !socket.isClosed(); }

    public void parar() {
        try { if (socket != null) socket.close(); } catch (IOException ignorada) { }
        fila.shutdownNow();
    }

    // ------------------------------------------------------------------ HTTP

    static final class Pedido {
        String metodo, caminho, host = "";
        Map<String, String> q = new HashMap<>();
        byte[] corpo = new byte[0];
        String corpoTexto() { return new String(corpo, StandardCharsets.UTF_8); }
    }

    void atender(Socket c) {
        try (Socket s = c) {
            s.setSoTimeout(30000);
            InputStream in = new BufferedInputStream(s.getInputStream());
            OutputStream out = s.getOutputStream();
            Pedido p = lerPedido(in);
            if (p == null) return;
            try { tratar(p, out); }
            catch (Exception e) {
                String m = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
                enviarJson(out, 500, "{\"error\":" + Json.str(m) + "}");
            }
        } catch (IOException ignorada) { }
    }

    static String linha(InputStream in) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        int ch;
        while ((ch = in.read()) != -1) {
            if (ch == '\n') break;
            if (ch != '\r') b.write(ch);
            if (b.size() > 16384) throw new IOException("linha longa");
        }
        if (ch == -1 && b.size() == 0) return null;
        return b.toString("UTF-8");
    }

    static Pedido lerPedido(InputStream in) throws IOException {
        String l = linha(in);
        if (l == null || l.isEmpty()) return null;
        String[] partes = l.split(" ");
        if (partes.length < 2) return null;
        Pedido p = new Pedido();
        p.metodo = partes[0].toUpperCase(Locale.ROOT);
        String alvo = partes[1];
        int qi = alvo.indexOf('?');
        p.caminho = qi >= 0 ? alvo.substring(0, qi) : alvo;
        if (qi >= 0) {
            for (String kv : alvo.substring(qi + 1).split("&")) {
                if (kv.isEmpty()) continue;
                int e = kv.indexOf('=');
                String k = URLDecoder.decode(e >= 0 ? kv.substring(0, e) : kv, "UTF-8");
                String v = e >= 0 ? URLDecoder.decode(kv.substring(e + 1), "UTF-8") : "";
                if (!p.q.containsKey(k)) p.q.put(k, v);
            }
        }
        int tam = 0;
        String h;
        while ((h = linha(in)) != null && !h.isEmpty()) {
            int d = h.indexOf(':');
            if (d < 0) continue;
            String nome = h.substring(0, d).trim().toLowerCase(Locale.ROOT), val = h.substring(d + 1).trim();
            if (nome.equals("host")) p.host = val;
            else if (nome.equals("content-length")) tam = Integer.parseInt(val);
        }
        if (tam > 31_000_000) throw new IOException("corpo grande demais");
        if (tam > 0) {
            byte[] b = new byte[tam];
            int lido = 0;
            while (lido < tam) {
                int n = in.read(b, lido, tam - lido);
                if (n < 0) break;
                lido += n;
            }
            p.corpo = lido == tam ? b : Arrays.copyOf(b, lido);
        }
        return p;
    }

    static void enviar(OutputStream out, int cod, String tipo, byte[] corpo) throws IOException {
        String st = cod == 200 ? "OK" : cod == 204 ? "No Content" : cod == 400 ? "Bad Request" : cod == 403 ? "Forbidden" : cod == 404 ? "Not Found" : cod == 502 ? "Bad Gateway" : "Error";
        String cab = "HTTP/1.1 " + cod + " " + st + "\r\nContent-Type: " + tipo + "\r\nCache-Control: no-store\r\nContent-Length: " + corpo.length + "\r\nConnection: close\r\n\r\n";
        out.write(cab.getBytes(StandardCharsets.ISO_8859_1));
        out.write(corpo);
        out.flush();
    }
    static void enviarTexto(OutputStream out, int cod, String tipo, String t) throws IOException { enviar(out, cod, tipo, t.getBytes(StandardCharsets.UTF_8)); }
    static void enviarJson(OutputStream out, int cod, String j) throws IOException { enviarTexto(out, cod, "application/json; charset=utf-8", j); }

    // ------------------------------------------------------------------ rotas (iguais às do Paginas.bat)

    void tratar(Pedido p, OutputStream out) throws Exception {
        if (!p.host.equals("127.0.0.1:" + porta)) { enviarTexto(out, 403, "text/plain", "proibido"); return; }
        String c = p.caminho;
        if (c.equals("/")) {
            if (!chave.equals(p.q.get("k"))) { enviarTexto(out, 403, "text/plain", "proibido"); return; }
            enviarTexto(out, 200, "text/html; charset=utf-8", html);
            return;
        }
        if (c.equals("/icone.png")) {
            File f = new File(pasta, "icone.png");
            if (f.exists()) enviar(out, 200, "image/png", ler(f)); else enviarJson(out, 404, "{\"error\":\"sem icone\"}");
            return;
        }
        if (c.equals("/oauth/google/callback")) { enviarTexto(out, 200, "text/html; charset=utf-8", googleVolta(p.q)); return; }
        if (!token.equals(p.q.get("t"))) { enviarJson(out, 403, "{\"error\":\"acesso negado\"}"); return; }

        switch (c) {
            case "/api/ping":
            case "/api/bye":
                enviarJson(out, 200, "{\"ok\":true}");
                break;
            case "/api/load":
                if (dados.exists()) enviar(out, 200, "application/json; charset=utf-8", ler(dados));
                else enviarJson(out, 200, "{}");
                break;
            case "/api/save": {
                if (!p.metodo.equals("POST")) { enviarJson(out, 404, "{\"error\":\"nao encontrado\"}"); break; }
                byte[] b = p.corpo;
                if (b.length < 2 || b.length > 30_000_000 || b[0] != '{') { enviarJson(out, 400, "{\"error\":\"dados invalidos\"}"); break; }
                synchronized (this) {
                    File tmp = new File(pasta, "dados.json.tmp");
                    escrever(tmp, b);
                    if (dados.exists()) escrever(dadosAnt, ler(dados));
                    if (!tmp.renameTo(dados)) { escrever(dados, b); tmp.delete(); }
                }
                enviarJson(out, 200, "{\"ok\":true}");
                break;
            }
            case "/api/catalog": {
                StringBuilder u = new StringBuilder("https://gutendex.com/books/?");
                boolean prim = true;
                for (String k : PARAMS) {
                    String v = p.q.get(k);
                    if (v == null || v.isEmpty()) continue;
                    if (!prim) u.append('&');
                    u.append(k).append('=').append(URLEncoder.encode(v, "UTF-8").replace("+", "%20"));
                    prim = false;
                }
                enviar(out, 200, "application/json; charset=utf-8", baixarComCache(u.toString(), 20 * 60_000L));
                break;
            }
            case "/api/cover": {
                String t = p.q.get("title"), a = p.q.get("author");
                if (t == null || t.isEmpty() || t.length() > 200) { enviarJson(out, 400, "{\"error\":\"titulo invalido\"}"); break; }
                String u = "https://openlibrary.org/search.json?limit=5&fields=cover_i,title,author_name&title=" + enc(t);
                if (a != null && !a.isEmpty() && a.length() <= 200) u += "&author=" + enc(a);
                enviar(out, 200, "application/json; charset=utf-8", baixarComCache(u, 12 * 3_600_000L));
                break;
            }
            case "/api/book": {
                String gid = p.q.get("gid");
                if (gid == null || !gid.matches("[0-9]{1,9}")) { enviarJson(out, 400, "{\"error\":\"livro invalido\"}"); break; }
                File f = new File(livros, gid + ".txt");
                if (!f.exists()) {
                    URI uri;
                    try { uri = new URI(p.q.getOrDefault("u", "")); } catch (URISyntaxException e) { uri = null; }
                    if (uri == null || uri.getHost() == null || !("https".equals(uri.getScheme()) || "http".equals(uri.getScheme()))
                            || !uri.getHost().toLowerCase(Locale.ROOT).matches("(.*\\.)?gutenberg\\.org")) {
                        enviarJson(out, 400, "{\"error\":\"endereco de livro nao permitido\"}"); break;
                    }
                    String texto = new String(baixar(uri.toString(), null, null), StandardCharsets.UTF_8);
                    if (!texto.isEmpty() && texto.charAt(0) == '﻿') texto = texto.substring(1);
                    if (texto.length() < 500) throw new IOException("O texto baixado veio vazio.");
                    escrever(f, texto.getBytes(StandardCharsets.UTF_8));
                }
                enviar(out, 200, "text/plain; charset=utf-8", ler(f));
                break;
            }
            case "/api/icon": {
                File f = new File(pasta, "icone.png");
                if (f.exists()) enviar(out, 200, "image/png", ler(f)); else enviarJson(out, 404, "{\"error\":\"sem icone\"}");
                break;
            }
            case "/api/config": {
                Map<String, Object> cfg = lerCfg();
                if (p.metodo.equals("POST")) {
                    Object o = Json.ler(p.corpoTexto());
                    if (o instanceof Map) {
                        Map<?, ?> in = (Map<?, ?>) o;
                        if (in.get("apiKey") != null) {
                            String k = String.valueOf(in.get("apiKey")).trim();
                            if (k.length() > 300) { enviarJson(out, 400, "{\"error\":\"chave invalida\"}"); break; }
                            cfg.put("apiKey", k);
                        }
                        if (in.get("googleClientId") != null) {
                            String g = String.valueOf(in.get("googleClientId")).trim();
                            if (g.length() > 300) { enviarJson(out, 400, "{\"error\":\"client id invalido\"}"); break; }
                            cfg.put("googleClientId", g);
                        }
                        if (in.get("port") != null) {
                            int pp;
                            try { pp = (int) Double.parseDouble(String.valueOf(in.get("port"))); } catch (NumberFormatException e) { pp = 0; }
                            if (pp != 0 && (pp < 1024 || pp > 65535)) { enviarJson(out, 400, "{\"error\":\"use uma porta entre 1024 e 65535\"}"); break; }
                            cfg.put("port", pp);
                        }
                        salvarCfg(cfg);
                    }
                }
                String key = String.valueOf(cfg.get("apiKey"));
                enviarJson(out, 200, "{\"hasKey\":" + !key.isEmpty() + ",\"proxy\":" + !proxyUrl.isEmpty() + ",\"googleClientId\":" + Json.str(String.valueOf(cfg.get("googleClientId")))
                        + ",\"port\":" + cfg.get("port") + "}");
                break;
            }
            case "/api/google/status": enviarJson(out, 200, googleStatus()); break;
            case "/api/google/start": {
                if (gId.isEmpty() || gSecret.isEmpty()) { enviarJson(out, 400, "{\"error\":\"O login com Google não está ativado nesta cópia do programa.\"}"); break; }
                synchronized (oauth) { oauth.values().removeIf(v -> System.currentTimeMillis() - Long.parseLong(v[1]) > 900_000L); }
                String st = aleatorioUrl(24), ver = aleatorioUrl(48);
                String chal = Base64.getUrlEncoder().withoutPadding().encodeToString(java.security.MessageDigest.getInstance("SHA-256").digest(ver.getBytes(StandardCharsets.US_ASCII)));
                oauth.put(st, new String[]{ver, String.valueOf(System.currentTimeMillis())});
                String u = G_AUTH + "?client_id=" + enc(gId) + "&redirect_uri=" + enc(redir()) + "&response_type=code&scope=" + enc(G_ESCOPO)
                        + "&state=" + enc(st) + "&code_challenge=" + enc(chal) + "&code_challenge_method=S256&access_type=offline&prompt=" + enc("consent select_account");
                enviarJson(out, 200, "{\"ok\":true,\"url\":" + Json.str(u) + "}");
                break;
            }
            case "/api/google/finish": {
                String erro = googleTrocar(p.q);
                if (erro != null) enviarJson(out, 400, "{\"error\":" + Json.str(erro) + "}"); else enviarJson(out, 200, googleStatus());
                break;
            }
            case "/api/google/logout": {
                Map<String, Object> cfg = lerCfg();
                String rt = txt(cfg.get("gRefresh"));
                if (!rt.isEmpty()) { try { http("POST", "https://oauth2.googleapis.com/revoke", "application/x-www-form-urlencoded", ("token=" + enc(rt)).getBytes(StandardCharsets.UTF_8), null); } catch (Exception ignorada) { } }
                for (String k : new String[]{"gRefresh", "gEmail", "gName", "gPic"}) cfg.put(k, "");
                salvarCfg(cfg);
                gAccess = "";
                enviarJson(out, 200, googleStatus());
                break;
            }
            case "/api/google/push":
                if (!p.metodo.equals("POST")) { enviarJson(out, 404, "{\"error\":\"nao encontrado\"}"); break; }
                drivePush();
                enviarJson(out, 200, "{\"ok\":true}");
                break;
            case "/api/google/pull": {
                String t = drivePull();
                if (t == null) enviar(out, 204, "application/json", new byte[0]);
                else enviarTexto(out, 200, "application/json; charset=utf-8", t);
                break;
            }
            case "/api/ai":
                if (!p.metodo.equals("POST")) { enviarJson(out, 404, "{\"error\":\"nao encontrado\"}"); break; }
                ia(p, out);
                break;
            default:
                enviarJson(out, 404, "{\"error\":\"nao encontrado\"}");
        }
    }

    void ia(Pedido p, OutputStream out) throws Exception {
        Map<String, Object> cfg = lerCfg();
        String key = String.valueOf(cfg.get("apiKey"));
        if (key.isEmpty() && proxyUrl.isEmpty()) { enviarJson(out, 400, "{\"error\":\"Configure sua chave de IA em Ajustes.\"}"); return; }
        Object o = Json.ler(p.corpoTexto());
        Map<?, ?> in = o instanceof Map ? (Map<?, ?>) o : new HashMap<>();
        String sel = txt(in.get("text")), cx = txt(in.get("context")), bt = txt(in.get("title")), ba = txt(in.get("author"));
        if (sel.length() < 1 || sel.length() > 1500) { enviarJson(out, 400, "{\"error\":\"Trecho invalido (use ate 1500 caracteres).\"}"); return; }
        if (cx.length() > 3000) cx = cx.substring(0, 3000);
        String sys = "Você é um assistente de leitura que ajuda leitores brasileiros a entender trechos de livros. Explique o significado da palavra, expressão ou frase selecionada em português do Brasil, de forma clara e curta (no máximo 120 palavras). Se for uma palavra ou expressão, dê o sentido no contexto e, se for arcaica ou rara, o equivalente atual. Se o trecho estiver em outro idioma, traduza e explique. Se for uma frase, diga o que ela quer dizer e, se ajudar, o recurso literário usado. Não use títulos nem listas longas; pode usar **negrito** para destacar o termo principal.";
        String usr = "Livro: " + bt + " (" + ba + ")\n\nParágrafo de contexto:\n" + cx + "\n\nTrecho selecionado:\n" + sel + "\n\nExplique o significado do trecho selecionado.";
        if (key.isEmpty()) {  // IA do Páginas: o mesmo intermediário (Cloudflare) do Investe.AI; as chaves ficam só lá
            String cp = "{\"sistema\":" + Json.str(sys) + ",\"mensagens\":[{\"role\":\"user\",\"content\":" + Json.str(usr) + "}]}";
            Map<String, String> cab = new HashMap<>();
            cab.put("X-App-Token", proxyToken);
            cab.put("X-App-Versao", "paginas-android-" + versao);
            Resp r;
            try { r = http("POST", proxyUrl + "/chat", "application/json", cp.getBytes(StandardCharsets.UTF_8), cab); }
            catch (IOException e) { enviarJson(out, 502, "{\"error\":\"Não consegui falar com a IA. Confira a internet e tente de novo.\"}"); return; }
            Object jj;
            try { jj = Json.ler(r.texto); } catch (Exception e) { jj = null; }
            Map<?, ?> m = jj instanceof Map ? (Map<?, ?>) jj : new HashMap<>();
            if (r.cod != 200 || txt(m.get("texto")).isEmpty()) {
                String erro = txt(m.get("erro")).isEmpty() ? "A IA não respondeu agora. Tente de novo em instantes." : txt(m.get("erro"));
                enviarJson(out, 502, "{\"error\":" + Json.str(erro) + "}");
                return;
            }
            enviarJson(out, 200, "{\"text\":" + Json.str(txt(m.get("texto"))) + "}");
            return;
        }
        String corpo = "{\"model\":" + Json.str(MODELO_IA) + ",\"max_tokens\":500,\"system\":" + Json.str(sys)
                + ",\"messages\":[{\"role\":\"user\",\"content\":" + Json.str(usr) + "}]}";

        HttpURLConnection c = (HttpURLConnection) new URL("https://api.anthropic.com/v1/messages").openConnection();
        c.setRequestMethod("POST");
        c.setConnectTimeout(30000);
        c.setReadTimeout(60000);
        c.setDoOutput(true);
        c.setRequestProperty("Content-Type", "application/json");
        c.setRequestProperty("x-api-key", key);
        c.setRequestProperty("anthropic-version", "2023-06-01");
        byte[] pb = corpo.getBytes(StandardCharsets.UTF_8);
        c.setFixedLengthStreamingMode(pb.length);
        try (OutputStream os = c.getOutputStream()) { os.write(pb); }
        int cod = c.getResponseCode();
        InputStream is = cod >= 400 ? c.getErrorStream() : c.getInputStream();
        String raw = is == null ? "" : new String(tudo(is), StandardCharsets.UTF_8);
        c.disconnect();
        Object j;
        try { j = Json.ler(raw); } catch (Exception e) { j = null; }
        if (cod != 200) {
            String m = "Erro " + cod + " ao falar com a IA.";
            if (j instanceof Map && ((Map<?, ?>) j).get("error") instanceof Map) {
                Object em = ((Map<?, ?>) ((Map<?, ?>) j).get("error")).get("message");
                if (em != null) m = String.valueOf(em);
            }
            enviarJson(out, 502, "{\"error\":" + Json.str(m) + "}");
            return;
        }
        StringBuilder t = new StringBuilder();
        if (j instanceof Map && ((Map<?, ?>) j).get("content") instanceof List) {
            for (Object b : (List<?>) ((Map<?, ?>) j).get("content")) {
                if (b instanceof Map && "text".equals(((Map<?, ?>) b).get("type"))) {
                    if (t.length() > 0) t.append('\n');
                    t.append(txt(((Map<?, ?>) b).get("text")));
                }
            }
        }
        enviarJson(out, 200, "{\"text\":" + Json.str(t.toString()) + "}");
    }

    // ------------------------------------------------------------------ utilidades

    static String txt(Object o) { return o == null ? "" : String.valueOf(o); }
    static String enc(String s) throws UnsupportedEncodingException { return URLEncoder.encode(s, "UTF-8").replace("+", "%20"); }

    static final String[] CFG_TEXTO = {"apiKey", "googleClientId", "gRefresh", "gEmail", "gName", "gPic"};

    synchronized Map<String, Object> lerCfg() {
        Map<String, Object> c = new LinkedHashMap<>();
        for (String k : CFG_TEXTO) c.put(k, "");
        c.put("port", 0);
        if (cfgArq.exists()) {
            try {
                Object o = Json.ler(new String(ler(cfgArq), StandardCharsets.UTF_8));
                if (o instanceof Map) {
                    Map<?, ?> m = (Map<?, ?>) o;
                    for (String k : CFG_TEXTO) if (m.get(k) != null) c.put(k, String.valueOf(m.get(k)));
                    if (m.get("port") instanceof Number) c.put("port", ((Number) m.get("port")).intValue());
                }
            } catch (Exception ignorada) { }
        }
        return c;
    }

    synchronized void salvarCfg(Map<String, Object> c) throws IOException {
        StringBuilder j = new StringBuilder("{");
        for (String k : CFG_TEXTO) j.append(Json.str(k)).append(':').append(Json.str(txt(c.get(k)))).append(',');
        j.append("\"port\":").append(c.get("port")).append('}');
        escrever(cfgArq, j.toString().getBytes(StandardCharsets.UTF_8));
    }

    // ------------------------------------------------------------------ conta Google e cópia no Google Drive

    String redir() { return "http://127.0.0.1:" + porta + "/oauth/google/callback"; }

    static String aleatorioUrl(int n) {
        byte[] b = new byte[n];
        new SecureRandom().nextBytes(b);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(b);
    }

    String googleStatus() {
        Map<String, Object> c = lerCfg();
        return "{\"available\":" + !(gId.isEmpty() || gSecret.isEmpty()) + ",\"connected\":" + !txt(c.get("gRefresh")).isEmpty()
                + ",\"email\":" + Json.str(txt(c.get("gEmail"))) + ",\"name\":" + Json.str(txt(c.get("gName"))) + ",\"picture\":" + Json.str(txt(c.get("gPic"))) + "}";
    }

    static String pagina(String msg, boolean ok, String extra) {
        String cor = ok ? "#2f7d4f" : "#b4532a";
        return "<!doctype html><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Páginas</title>"
                + "<body style=\"font-family:system-ui,sans-serif;background:#f6f1e7;color:#2b2118;display:grid;place-items:center;height:100vh;margin:0\">"
                + "<div style=\"text-align:center;max-width:440px;padding:24px\"><div style=\"font-size:36px;font-weight:800;color:" + cor + "\">" + (ok ? "Quase lá" : "Não deu certo") + "</div>"
                + "<p style=\"font-size:18px\">" + htmlEsc(msg) + "</p>" + (extra == null ? "" : extra) + "</div></body>";
    }

    static String htmlEsc(String s) { return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;"); }

    /** O navegador do celular volta do Google para cá; devolvemos o login para o app (paginas://login?...). */
    String googleVolta(Map<String, String> q) throws UnsupportedEncodingException {
        String st = q.get("state");
        if (st == null || !oauth.containsKey(st)) return pagina("A sessão de login expirou. Volte ao Páginas e tente de novo.", false, null);
        StringBuilder qs = new StringBuilder();
        for (String k : new String[]{"code", "state", "error"}) {
            String v = q.get(k);
            if (v == null || v.isEmpty()) continue;
            if (qs.length() > 0) qs.append('&');
            qs.append(k).append('=').append(enc(v));
        }
        String alvo = "intent://login?" + qs + "#Intent;scheme=paginas;package=br.paginas.app;end";
        String botao = "<a href=\"" + htmlEsc(alvo) + "\" style=\"display:inline-block;margin-top:12px;padding:14px 26px;border-radius:12px;color:#fff;font-weight:700;text-decoration:none;background:linear-gradient(135deg,#e08a5c,#a0401e)\">Voltar ao Páginas</a>"
                + "<script>setTimeout(function(){location.href=" + Json.str(alvo) + "},300)</script>";
        return pagina("Toque no botão para concluir o login no app.", true, botao);
    }

    /** Troca o código do Google pelos tokens e guarda a conta. Devolve null se deu certo, ou a mensagem de erro. */
    String googleTrocar(Map<String, String> q) {
        String[] st = q.get("state") == null ? null : oauth.remove(q.get("state"));
        if (st == null || System.currentTimeMillis() - Long.parseLong(st[1]) > 900_000L) return "A sessão de login expirou. Tente entrar de novo.";
        if (q.get("error") != null && !q.get("error").isEmpty()) return "Login cancelado ou recusado pelo Google.";
        try {
            String form = "code=" + enc(txt(q.get("code"))) + "&client_id=" + enc(gId) + "&client_secret=" + enc(gSecret) + "&redirect_uri=" + enc(redir())
                    + "&grant_type=authorization_code&code_verifier=" + enc(st[0]);
            Resp r = http("POST", G_TOKEN, "application/x-www-form-urlencoded", form.getBytes(StandardCharsets.UTF_8), null);
            Map<?, ?> j = mapa(r.texto);
            String at = txt(j.get("access_token"));
            if (at.isEmpty()) {
                String e = txt(j.get("error_description")).isEmpty() ? txt(j.get("error")) : txt(j.get("error_description"));
                return "O Google recusou o login: " + (e.isEmpty() ? "erro desconhecido" : e);
            }
            Map<String, String> cab = new HashMap<>();
            cab.put("Authorization", "Bearer " + at);
            Map<?, ?> u = mapa(http("GET", "https://openidconnect.googleapis.com/v1/userinfo", null, null, cab).texto);
            Map<String, Object> c = lerCfg();
            if (!txt(j.get("refresh_token")).isEmpty()) c.put("gRefresh", txt(j.get("refresh_token")));
            if (txt(c.get("gRefresh")).isEmpty()) return "O Google não deu acesso permanente. Tente entrar de novo.";
            c.put("gEmail", txt(u.get("email")));
            c.put("gName", txt(u.get("name")));
            c.put("gPic", txt(u.get("picture")));
            salvarCfg(c);
            gAccess = at;
            gExp = System.currentTimeMillis() + numero(j.get("expires_in"), 3600) * 1000L;
            return null;
        } catch (Exception e) {
            return "Falha ao falar com o Google. Confira a internet e tente de novo.";
        }
    }

    synchronized String acessoGoogle() throws IOException {
        Map<String, Object> c = lerCfg();
        String rt = txt(c.get("gRefresh"));
        if (rt.isEmpty()) throw new IOException("Entre com sua conta Google primeiro.");
        if (!gAccess.isEmpty() && gExp > System.currentTimeMillis() + 60_000L) return gAccess;
        String form = "client_id=" + enc(gId) + "&client_secret=" + enc(gSecret) + "&refresh_token=" + enc(rt) + "&grant_type=refresh_token";
        Resp r = http("POST", G_TOKEN, "application/x-www-form-urlencoded", form.getBytes(StandardCharsets.UTF_8), null);
        Map<?, ?> j = mapa(r.texto);
        if (txt(j.get("access_token")).isEmpty()) {
            if ("invalid_grant".equals(txt(j.get("error")))) {
                for (String k : new String[]{"gRefresh", "gEmail", "gName", "gPic"}) c.put(k, "");
                salvarCfg(c);
                throw new IOException("Sua sessão do Google expirou. Entre de novo em Ajustes.");
            }
            throw new IOException("O Google não liberou o acesso agora (erro " + r.cod + ").");
        }
        gAccess = txt(j.get("access_token"));
        gExp = System.currentTimeMillis() + numero(j.get("expires_in"), 3600) * 1000L;
        return gAccess;
    }

    Map<String, String> bearer(String at) { Map<String, String> h = new HashMap<>(); h.put("Authorization", "Bearer " + at); return h; }

    String driveArquivo(String at) throws IOException {
        Resp r = http("GET", "https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&fields=files(id,modifiedTime)&q=" + enc("name='" + DRIVE_ARQ + "'"), null, null, bearer(at));
        if (r.cod != 200) throw new IOException("Google Drive: erro " + r.cod + " ao procurar seus dados.");
        Object f = mapa(r.texto).get("files");
        if (f instanceof List && !((List<?>) f).isEmpty() && ((List<?>) f).get(0) instanceof Map) return txt(((Map<?, ?>) ((List<?>) f).get(0)).get("id"));
        return "";
    }

    synchronized void drivePush() throws IOException {
        if (!dados.exists()) return;
        String at = acessoGoogle();
        byte[] b = ler(dados);
        String id = driveArquivo(at);
        Resp r;
        if (!id.isEmpty()) r = http("PATCH", "https://www.googleapis.com/upload/drive/v3/files/" + id + "?uploadType=media", "application/json", b, bearer(at));
        else {
            String bd = "pgn" + aleatorio();
            byte[] pre = ("--" + bd + "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n{\"name\":\"" + DRIVE_ARQ + "\",\"parents\":[\"appDataFolder\"]}\r\n--" + bd
                    + "\r\nContent-Type: application/json\r\n\r\n").getBytes(StandardCharsets.UTF_8);
            byte[] pos = ("\r\n--" + bd + "--\r\n").getBytes(StandardCharsets.UTF_8);
            ByteArrayOutputStream tudo = new ByteArrayOutputStream();
            tudo.write(pre); tudo.write(b); tudo.write(pos);
            r = http("POST", "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart", "multipart/related; boundary=" + bd, tudo.toByteArray(), bearer(at));
        }
        if (r.cod != 200) throw new IOException("Google Drive: erro " + r.cod + " ao guardar seus dados.");
    }

    String drivePull() throws IOException {
        String at = acessoGoogle();
        String id = driveArquivo(at);
        if (id.isEmpty()) return null;
        Resp r = http("GET", "https://www.googleapis.com/drive/v3/files/" + id + "?alt=media", null, null, bearer(at));
        if (r.cod != 200) throw new IOException("Google Drive: erro " + r.cod + " ao trazer seus dados.");
        return r.texto;
    }

    static Map<?, ?> mapa(String t) {
        try { Object o = Json.ler(t); if (o instanceof Map) return (Map<?, ?>) o; } catch (Exception ignorada) { }
        return new HashMap<>();
    }
    static long numero(Object o, long padrao) { return o instanceof Number ? ((Number) o).longValue() : padrao; }

    static final class Resp { int cod; String texto; }

    /** Pedido HTTP com corpo e cabeçalhos (IA e Google). */
    static Resp http(String metodo, String url, String tipo, byte[] corpo, Map<String, String> cab) throws IOException {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        try { c.setRequestMethod(metodo); }
        catch (ProtocolException e) { c.setRequestMethod("POST"); c.setRequestProperty("X-HTTP-Method-Override", metodo); }  // PATCH no Java de computador
        c.setConnectTimeout(30000);
        c.setReadTimeout(90000);
        c.setRequestProperty("User-Agent", "Paginas-Android");
        if (cab != null) for (Map.Entry<String, String> e : cab.entrySet()) if (e.getValue() != null && !e.getValue().isEmpty()) c.setRequestProperty(e.getKey(), e.getValue());
        if (corpo != null) {
            c.setDoOutput(true);
            c.setRequestProperty("Content-Type", tipo);
            c.setFixedLengthStreamingMode(corpo.length);
            try (OutputStream os = c.getOutputStream()) { os.write(corpo); }
        }
        int cod = c.getResponseCode();
        InputStream is = cod >= 400 ? c.getErrorStream() : c.getInputStream();
        Resp r = new Resp();
        r.cod = cod;
        r.texto = is == null ? "" : new String(tudo(is), StandardCharsets.UTF_8);
        c.disconnect();
        return r;
    }

    byte[] baixarComCache(String url, long validade) throws IOException {
        Object[] hit = cache.get(url);
        if (hit != null && System.currentTimeMillis() - (Long) hit[0] < validade) return (byte[]) hit[1];
        byte[] b = baixar(url, null, null);
        cache.put(url, new Object[]{System.currentTimeMillis(), b});
        return b;
    }

    /** GET seguindo redirecionamentos (inclusive http -> https, que o Java não segue sozinho). */
    static byte[] baixar(String url, String metodo, byte[] corpo) throws IOException {
        String atual = url;
        for (int i = 0; i < 8; i++) {
            HttpURLConnection c = (HttpURLConnection) new URL(atual).openConnection();
            c.setInstanceFollowRedirects(false);
            c.setConnectTimeout(30000);
            c.setReadTimeout(30000);
            c.setRequestProperty("User-Agent", "Paginas/1.0 (leitor pessoal de livros)");
            c.setRequestProperty("Accept-Encoding", "gzip, deflate");
            int cod = c.getResponseCode();
            if (cod >= 300 && cod < 400 && c.getHeaderField("Location") != null) {
                atual = new URL(new URL(atual), c.getHeaderField("Location")).toString();
                c.disconnect();
                continue;
            }
            if (cod >= 400) { c.disconnect(); throw new IOException("Erro " + cod + " (sem internet ou serviço fora do ar?)"); }
            InputStream is = c.getInputStream();
            String ce = c.getContentEncoding();
            if (ce != null && ce.equalsIgnoreCase("gzip")) is = new GZIPInputStream(is);
            else if (ce != null && ce.equalsIgnoreCase("deflate")) is = new InflaterInputStream(is);
            try { return tudo(is); } finally { c.disconnect(); }
        }
        throw new IOException("Redirecionamentos demais.");
    }

    static byte[] tudo(InputStream is) throws IOException {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] buf = new byte[16384];
        int n;
        while ((n = is.read(buf)) > 0) b.write(buf, 0, n);
        is.close();
        return b.toByteArray();
    }
    static byte[] ler(File f) throws IOException { try (InputStream is = new FileInputStream(f)) { return tudo(is); } }
    static void escrever(File f, byte[] b) throws IOException { try (OutputStream os = new FileOutputStream(f)) { os.write(b); } }

    /** JSON mínimo (o suficiente para config, pedidos da IA e respostas da API). */
    static final class Json {
        final String s; int i;
        Json(String s) { this.s = s; }
        static Object ler(String s) { Json j = new Json(s); j.esp(); Object o = j.valor(); return o; }
        static String str(String v) {
            StringBuilder b = new StringBuilder("\"");
            for (int k = 0; k < v.length(); k++) {
                char ch = v.charAt(k);
                switch (ch) {
                    case '"': b.append("\\\""); break;
                    case '\\': b.append("\\\\"); break;
                    case '\n': b.append("\\n"); break;
                    case '\r': b.append("\\r"); break;
                    case '\t': b.append("\\t"); break;
                    default:
                        if (ch < 0x20 || ch == 0x2028 || ch == 0x2029) b.append(String.format("\\u%04x", (int) ch)); else b.append(ch);
                }
            }
            return b.append('"').toString();
        }
        void esp() { while (i < s.length() && Character.isWhitespace(s.charAt(i))) i++; }
        Object valor() {
            esp();
            if (i >= s.length()) throw new IllegalArgumentException("json vazio");
            char ch = s.charAt(i);
            if (ch == '{') {
                i++; Map<String, Object> m = new LinkedHashMap<>(); esp();
                if (s.charAt(i) == '}') { i++; return m; }
                while (true) {
                    esp(); String k = texto(); esp(); i++; // ':'
                    m.put(k, valor()); esp();
                    char d = s.charAt(i++);
                    if (d == '}') return m;
                }
            }
            if (ch == '[') {
                i++; List<Object> l = new ArrayList<>(); esp();
                if (s.charAt(i) == ']') { i++; return l; }
                while (true) {
                    l.add(valor()); esp();
                    char d = s.charAt(i++);
                    if (d == ']') return l;
                }
            }
            if (ch == '"') return texto();
            if (s.startsWith("true", i)) { i += 4; return Boolean.TRUE; }
            if (s.startsWith("false", i)) { i += 5; return Boolean.FALSE; }
            if (s.startsWith("null", i)) { i += 4; return null; }
            int ini = i;
            while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
            if (ini == i) throw new IllegalArgumentException("json invalido");
            return Double.parseDouble(s.substring(ini, i));
        }
        String texto() {
            if (s.charAt(i) != '"') throw new IllegalArgumentException("json invalido");
            i++;
            StringBuilder b = new StringBuilder();
            while (true) {
                char ch = s.charAt(i++);
                if (ch == '"') return b.toString();
                if (ch != '\\') { b.append(ch); continue; }
                char e = s.charAt(i++);
                switch (e) {
                    case 'n': b.append('\n'); break;
                    case 'r': b.append('\r'); break;
                    case 't': b.append('\t'); break;
                    case 'b': b.append('\b'); break;
                    case 'f': b.append('\f'); break;
                    case 'u': b.append((char) Integer.parseInt(s.substring(i, i + 4), 16)); i += 4; break;
                    default: b.append(e);
                }
            }
        }
    }
}
