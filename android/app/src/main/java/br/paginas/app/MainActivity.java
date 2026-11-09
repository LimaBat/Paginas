package br.paginas.app;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;
import android.view.WindowInsets;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/** Tela do Páginas: liga o servidor local (Servidor.java) e mostra a mesma interface do Windows num WebView. */
public class MainActivity extends Activity {
    static final String FUNDO = "#f6f1e7";
    static final int ESCOLHER_ARQUIVO = 7;
    static Servidor servidor;            // continua vivo enquanto o processo do app existir
    static volatile String erroServidor;
    WebView web;
    ValueCallback<Uri[]> escolhaPendente;
    String loginPendente;          // volta do login do Google (paginas://login?code=...&state=...)
    volatile boolean paginaPronta;

    /** Ajustes que só existem no celular (vão no fim da página). */
    static final String EXTRA_ANDROID = "<script>\n"
            + "(function(){\n"
            + "  var A = window.PaginasAndroid; if (!A) return;\n"
            + "  try { exportData = function(){ var m = A.salvarBackup(JSON.stringify(state, null, 2), 'paginas-backup-' + todayStr() + '.json'); toast(m); }; } catch (e) {}\n"
            + "  window.paginasSalvar = function(){ try { flushReading(false); } catch (e) {} try { flushSave(); } catch (e) {} try { if (window.Sync) Sync.push(); } catch (e) {} };\n"
            + "  window.paginasVoltar = function(){\n"
            + "    var d = document.getElementById('dlg'); if (d && d.open) { d.close(); return true; }\n"
            + "    var r = document.getElementById('reader');\n"
            + "    if (typeof R !== 'undefined' && R && r && !r.hidden) {\n"
            + "      if ((typeof HS !== 'undefined' && HS.panel) || document.getElementById('rtool')) document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));\n"
            + "      else closeReader();\n"
            + "      return true;\n"
            + "    }\n"
            + "    return false;\n"
            + "  };\n"
            + "})();\n"
            + "</script>\n";

    @Override
    protected void onCreate(Bundle estado) {
        super.onCreate(estado);
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor(FUNDO));
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setSupportMultipleWindows(false);
        s.setMediaPlaybackRequiresUserGesture(true);
        s.setUserAgentString(s.getUserAgentString() + " PaginasAndroid/1");
        web.addJavascriptInterface(new Ponte(), "PaginasAndroid");
        web.setWebViewClient(new WebViewClient() {
            @Override
            public void onPageFinished(WebView v, String url) {
                if (url != null && url.startsWith("http://127.0.0.1")) { paginaPronta = true; entregarLogin(); }
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest req) {
                Uri u = req.getUrl();
                if ("127.0.0.1".equals(u.getHost())) return false;
                try { startActivity(new Intent(Intent.ACTION_VIEW, u)); } catch (Exception e) { Log.w("Paginas", e); }
                return true;  // links de fora abrem no navegador do celular
            }
        });
        web.setWebChromeClient(new WebChromeClient() {  // necessário para confirm() e para "Importar backup"
            @Override
            public boolean onShowFileChooser(WebView v, ValueCallback<Uri[]> cb, FileChooserParams p) {
                if (escolhaPendente != null) escolhaPendente.onReceiveValue(null);
                escolhaPendente = cb;
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                i.setType("*/*");
                try { startActivityForResult(Intent.createChooser(i, "Escolha o backup"), ESCOLHER_ARQUIVO); }
                catch (Exception e) { escolhaPendente = null; return false; }
                return true;
            }
        });

        FrameLayout raiz = new FrameLayout(this);
        raiz.setBackgroundColor(Color.parseColor(FUNDO));
        raiz.addView(web, new FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));
        if (Build.VERSION.SDK_INT >= 30) {  // Android 15 desenha atrás das barras: deixa o espaço delas livre
            raiz.setOnApplyWindowInsetsListener((v, ins) -> {
                android.graphics.Insets b = ins.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                v.setPadding(b.left, b.top, b.right, b.bottom);
                return WindowInsets.CONSUMED;
            });
        }
        setContentView(raiz);
        guardarLogin(getIntent());
        web.loadDataWithBaseURL(null, "<html><body style='background:" + FUNDO + "'></body></html>", "text/html", "utf-8", null);
        abrir();
    }

    void abrir() {
        new Thread(() -> {
            try {
                Servidor sv = ligarServidor();
                runOnUiThread(() -> { paginaPronta = false; web.loadUrl(sv.endereco()); });
            } catch (Throwable t) {
                Log.e("Paginas", "servidor", t);
                String msg = "Não consegui abrir o Páginas. Feche o app e abra de novo. (" + t + ")";
                runOnUiThread(() -> web.loadDataWithBaseURL(null,
                        "<html><body style='font-family:sans-serif;padding:24px;background:" + FUNDO + "'><p>" + android.text.Html.escapeHtml(msg) + "</p></body></html>",
                        "text/html", "utf-8", null));
            }
        }, "paginas-inicio").start();
    }

    synchronized Servidor ligarServidor() throws Exception {
        if (servidor != null && servidor.vivo()) return servidor;
        File pasta = getFilesDir();
        File icone = new File(pasta, "icone.png");
        if (!icone.exists()) {
            try (InputStream is = getAssets().open("icone.png"); OutputStream os = new FileOutputStream(icone)) { copiar(is, os); }
        }
        String html;
        try (InputStream is = getAssets().open("index.html")) {
            ByteArrayOutputStream b = new ByteArrayOutputStream();
            copiar(is, b);
            html = b.toString("UTF-8");
        }
        Object dist = null;
        try (InputStream is = getAssets().open("config.json")) {
            ByteArrayOutputStream b = new ByteArrayOutputStream();
            copiar(is, b);
            dist = Servidor.Json.ler(b.toString("UTF-8"));
        } catch (Exception e) { Log.w("Paginas", "sem assets/config.json", e); }
        Servidor sv = new Servidor(pasta, html, EXTRA_ANDROID, dist instanceof java.util.Map ? (java.util.Map<?, ?>) dist : null);
        sv.iniciar(Servidor.PORTA_PADRAO);
        servidor = sv;
        return sv;
    }

    static void copiar(InputStream is, OutputStream os) throws java.io.IOException {
        byte[] buf = new byte[16384];
        int n;
        while ((n = is.read(buf)) > 0) os.write(buf, 0, n);
    }

    /** Funções que a página pode chamar (window.PaginasAndroid). */
    class Ponte {
        @JavascriptInterface
        public String salvarBackup(String json, String nome) {
            try {
                byte[] b = json.getBytes(StandardCharsets.UTF_8);
                if (Build.VERSION.SDK_INT >= 29) {
                    ContentValues v = new ContentValues();
                    v.put(MediaStore.Downloads.DISPLAY_NAME, nome);
                    v.put(MediaStore.Downloads.MIME_TYPE, "application/json");
                    v.put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                    Uri u = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, v);
                    if (u == null) throw new Exception("sem acesso a Downloads");
                    try (OutputStream os = getContentResolver().openOutputStream(u)) { os.write(b); }
                    return "Backup salvo em Downloads: " + nome;
                }
                File d = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                if (d == null) d = getFilesDir();
                d.mkdirs();
                File f = new File(d, nome);
                try (OutputStream os = new FileOutputStream(f)) { os.write(b); }
                return "Backup salvo em " + f.getAbsolutePath();
            } catch (Exception e) {
                return "Não consegui salvar o backup: " + e.getMessage();
            }
        }
    }

    @Override
    protected void onNewIntent(Intent i) {
        super.onNewIntent(i);
        setIntent(i);
        guardarLogin(i);
        entregarLogin();
    }

    void guardarLogin(Intent i) {
        Uri u = i == null ? null : i.getData();
        if (u != null && "paginas".equals(u.getScheme()) && "login".equals(u.getHost()) && u.getEncodedQuery() != null) loginPendente = u.getEncodedQuery();
    }

    /** Passa o código do Google para a página, que conclui o login pelo servidor local. */
    void entregarLogin() {
        if (loginPendente == null || !paginaPronta || web == null) return;
        String qs = loginPendente;
        loginPendente = null;
        web.evaluateJavascript("(function f(n){if(window.googleVoltou)googleVoltou(" + Servidor.Json.str(qs) + ");else if(n<50)setTimeout(function(){f(n+1)},200)})(0)", null);
    }

    @Override
    protected void onActivityResult(int req, int res, Intent dados) {
        super.onActivityResult(req, res, dados);
        if (req != ESCOLHER_ARQUIVO || escolhaPendente == null) return;
        Uri[] r = (res == RESULT_OK && dados != null && dados.getData() != null) ? new Uri[]{dados.getData()} : null;
        escolhaPendente.onReceiveValue(r);
        escolhaPendente = null;
    }

    @Override
    protected void onPause() {
        if (web != null) web.evaluateJavascript("window.paginasSalvar&&paginasSalvar()", null);
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (servidor != null && !servidor.vivo()) abrir();  // o sistema fechou o servidor: liga de novo
    }

    @Override
    public void onBackPressed() {
        web.evaluateJavascript("window.paginasVoltar?paginasVoltar():false", v -> {
            if ("true".equals(v)) return;
            if (web.canGoBack()) web.goBack();
            else moveTaskToBack(true);
        });
    }
}
