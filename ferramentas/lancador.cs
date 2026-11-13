// Paginas.exe: o Páginas como programa próprio do Windows.
// - Janela própria (WebView2, o motor do Edge que já vem no Windows): aparece como "Páginas" na barra de
//   tarefas, com o ícone, e pode ser fixada nela.
// - Tela de abertura animada enquanto o programa liga.
// - O programa (a parte em PowerShell do Paginas.bat) roda DENTRO deste .exe: nada de powershell.exe
//   escondido, de .vbs ou de "ExecutionPolicy Bypass".
// - Sem WebView2 no computador, abre como antes, numa janela do Edge.
// Compilado no GitHub Actions com o csc.exe do .NET Framework (vem em todo Windows).
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("Páginas")]
[assembly: AssemblyProduct("Páginas")]
[assembly: AssemblyDescription("Páginas: hábito de leitura e biblioteca virtual")]
[assembly: AssemblyCompany("LimaBat")]
[assembly: AssemblyCopyright("© 2026 LimaBat. Código aberto em github.com/LimaBat/Paginas")]

static class Lancador
{
    internal static string pasta;
    internal static Thread trabalho;
    internal static EventWaitHandle mostrar;
    const string APP_ID = "LimaBat.Paginas";

    [DllImport("shell32.dll", SetLastError = true)]
    static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string id);

    [STAThread]
    static int Main(string[] args)
    {
        pasta = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Paginas");
        bool reflexao = args.Length > 0 && args[0] == "--reflexao";
        Mutex unico = null;
        try
        {
            Directory.CreateDirectory(pasta);
            try { SetCurrentProcessExplicitAppUserModelID(APP_ID); } catch { }
            AppDomain.CurrentDomain.AssemblyResolve += ResolverDll;

            if (!reflexao)
            {
                // um Páginas só: se já estiver aberto, traz a janela para a frente
                bool novo;
                unico = new Mutex(true, "Local\\Paginas.App", out novo);
                mostrar = new EventWaitHandle(false, EventResetMode.AutoReset, "Local\\Paginas.Mostrar");
                if (!novo)
                {
                    // já aberto: traz a janela. Se o outro estiver só fechando (atualização), espera ele sair e abre.
                    mostrar.Set();
                    bool pegou;
                    try { pegou = unico.WaitOne(4000); } catch (AbandonedMutexException) { pegou = true; }
                    if (!pegou) return 0;
                    mostrar.Reset();
                }
            }

            string exe = Instalar();
            string bat = Path.Combine(pasta, "Paginas.bat");
            if (!reflexao) GuardarPrograma(bat);
            Environment.SetEnvironmentVariable("PAGINAS_SELF", bat);
            Environment.SetEnvironmentVariable("PAGINAS_EXE", exe);
            Environment.SetEnvironmentVariable("PAGINAS_PRONTO", null);
            Environment.SetEnvironmentVariable("PAGINAS_URL", null);

            if (reflexao)
            {
                // notificação de reflexão agendada (Ajustes > Reflexões)
                string ps1 = Path.Combine(pasta, "notificar.ps1");
                if (File.Exists(ps1)) Rodar(File.ReadAllText(ps1, Encoding.UTF8), ps1);
                return 0;
            }

            string texto = File.ReadAllText(bat, Encoding.UTF8).Replace("\r", "");
            int i = texto.IndexOf("#PS_START\n"), j = texto.IndexOf("\n::HTML_START");
            if (i < 0 || j < 0) throw new Exception("O arquivo do programa está incompleto. Baixe o Páginas de novo.");
            string script = texto.Substring(i + 10, j - i - 10);

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            bool janela = TemWebView2();
            Environment.SetEnvironmentVariable("PAGINAS_JANELA", janela ? "1" : null);

            Exception erro = null;
            trabalho = new Thread(() => { try { Rodar(script, null); } catch (Exception e) { erro = e; } });
            trabalho.SetApartmentState(ApartmentState.STA);
            trabalho.Start();

            if (janela) AbrirJanela();
            else Application.Run(new Abertura());
            trabalho.Join(15000);
            if (erro != null && Environment.GetEnvironmentVariable("PAGINAS_PRONTO") != "1") throw erro;
            Environment.Exit(0);
            return 0;
        }
        catch (Exception e)
        {
            try { File.AppendAllText(Path.Combine(pasta, "erro.log"), DateTime.Now.ToString("s") + " lancador: " + e + "\r\n"); } catch { }
            if (!reflexao) MessageBox.Show("Não consegui abrir o Páginas.\n\n" + e.Message, "Páginas", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally { GC.KeepAlive(unico); }
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static void AbrirJanela() { Application.Run(new Janela()); }

    [MethodImpl(MethodImplOptions.NoInlining)]
    static bool TemWebView2()
    {
        if (Environment.GetEnvironmentVariable("PAGINAS_SEM_JANELA") == "1") return false;
        try { return PreparaWebView2.Pronto(); }
        catch (Exception e)
        {
            try { File.AppendAllText(Path.Combine(pasta, "erro.log"), DateTime.Now.ToString("s") + " webview2: " + e.Message + "\r\n"); } catch { }
            return false;
        }
    }

    // as bibliotecas do WebView2 vêm dentro deste .exe
    static Assembly ResolverDll(object s, ResolveEventArgs a)
    {
        string nome = new AssemblyName(a.Name).Name + ".dll";
        using (Stream st = Assembly.GetExecutingAssembly().GetManifestResourceStream(nome))
        {
            if (st == null) return null;
            using (MemoryStream ms = new MemoryStream()) { st.CopyTo(ms); return Assembly.Load(ms.ToArray()); }
        }
    }

    internal static byte[] Recurso(string nome)
    {
        using (Stream st = Assembly.GetExecutingAssembly().GetManifestResourceStream(nome))
        {
            if (st == null) return null;
            using (MemoryStream ms = new MemoryStream()) { st.CopyTo(ms); return ms.ToArray(); }
        }
    }

    /// Roda um script do PowerShell aqui dentro, na thread atual.
    static void Rodar(string script, string arquivo)
    {
        InitialSessionState iss = InitialSessionState.CreateDefault();
        iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.RemoteSigned;
        using (Runspace rs = RunspaceFactory.CreateRunspace(iss))
        {
            rs.ThreadOptions = PSThreadOptions.UseCurrentThread;
            rs.Open();
            using (PowerShell ps = PowerShell.Create())
            {
                ps.Runspace = rs;
                // o script de notificação usa $MyInvocation para achar a própria pasta
                if (arquivo != null) script = script.Replace("Split-Path -Parent $MyInvocation.MyCommand.Path", "'" + pasta.Replace("'", "''") + "'");
                ps.AddScript(script);
                ps.Invoke();
                if (ps.HadErrors && ps.Streams.Error.Count > 0 && Environment.GetEnvironmentVariable("PAGINAS_PRONTO") != "1")
                    throw new Exception(ps.Streams.Error[0].ToString());
            }
        }
    }

    /// Guarda uma cópia do Paginas.exe na pasta do app (os atalhos e a barra de tarefas apontam para ela).
    static string Instalar()
    {
        string eu = Application.ExecutablePath;
        string destino = Path.Combine(pasta, "Paginas.exe");
        if (string.Equals(Path.GetFullPath(eu), Path.GetFullPath(destino), StringComparison.OrdinalIgnoreCase)) return destino;
        try
        {
            bool copiar = !File.Exists(destino);
            if (!copiar)
            {
                Version minha = new Version(FileVersionInfo.GetVersionInfo(eu).FileVersion ?? "0.0");
                Version dele = new Version(FileVersionInfo.GetVersionInfo(destino).FileVersion ?? "0.0");
                copiar = minha >= dele;
            }
            if (copiar) File.Copy(eu, destino, true);
            return destino;
        }
        catch { return File.Exists(destino) ? destino : eu; }
    }

    /// Guarda o Paginas.bat que vem dentro do .exe, sem trocar uma versão mais nova (atualizada pelo próprio app).
    static void GuardarPrograma(string bat)
    {
        byte[] emb = Recurso("Paginas.bat");
        bool escrever = !File.Exists(bat);
        if (!escrever)
        {
            try { escrever = Versao(Encoding.UTF8.GetString(emb)) >= Versao(File.ReadAllText(bat, Encoding.UTF8)); }
            catch { escrever = true; }
        }
        if (escrever)
        {
            File.WriteAllBytes(bat + ".novo", emb);
            if (File.Exists(bat)) File.Delete(bat);
            File.Move(bat + ".novo", bat);
        }
    }

    static Version Versao(string texto)
    {
        Match m = Regex.Match(texto, @"(?m)^\$APP_VERSAO = '([0-9.]+)'");
        if (!m.Success) return new Version(0, 0);
        string v = m.Groups[1].Value;
        if (v.IndexOf('.') < 0) v += ".0";
        try { return new Version(v); } catch { return new Version(0, 0); }
    }

    internal static Icon Icone() { try { return Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { return null; } }
}

/// Coloca a biblioteca nativa do WebView2 na pasta do app e confere se o Windows tem o WebView2.
static class PreparaWebView2
{
    public static bool Pronto()
    {
        string arq = Environment.Is64BitProcess
            ? (string.Equals(Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE"), "ARM64", StringComparison.OrdinalIgnoreCase) ? "arm64" : "x64")
            : "x86";
        byte[] dll = Lancador.Recurso("WebView2Loader." + arq + ".dll");
        if (dll == null) return false;
        string dir = Path.Combine(Lancador.pasta, "wv2", arq);
        Directory.CreateDirectory(dir);
        string alvo = Path.Combine(dir, "WebView2Loader.dll");
        if (!File.Exists(alvo) || new FileInfo(alvo).Length != dll.Length) File.WriteAllBytes(alvo, dll);
        Microsoft.Web.WebView2.Core.CoreWebView2Environment.SetLoaderDllFolderPath(dir);
        string v = Microsoft.Web.WebView2.Core.CoreWebView2Environment.GetAvailableBrowserVersionString();
        return !string.IsNullOrEmpty(v);
    }
}

/// A janela do Páginas.
class Janela : Form
{
    readonly Microsoft.Web.WebView2.WinForms.WebView2 wv;
    readonly System.Windows.Forms.Timer tm = new System.Windows.Forms.Timer { Interval = 120 };
    bool entregue, fechando, carregou;
    readonly DateTime ini = DateTime.Now;

    public Janela()
    {
        Text = "Páginas";
        Icon = Lancador.Icone();
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(1240, 840);
        MinimumSize = new Size(420, 560);
        WindowState = FormWindowState.Maximized;
        bool escuro = TemaEscuro();
        BackColor = escuro ? Color.FromArgb(20, 17, 14) : Color.FromArgb(246, 241, 231);
        wv = new Microsoft.Web.WebView2.WinForms.WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = BackColor };
        wv.CreationProperties = new Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties { UserDataFolder = Path.Combine(Lancador.pasta, "WebView2") };
        Controls.Add(wv);
        Load += async (s, e) =>
        {
            try
            {
                await wv.EnsureCoreWebView2Async();
                var c = wv.CoreWebView2;
                c.Settings.AreDevToolsEnabled = false;
                c.Settings.IsStatusBarEnabled = false;
                c.Settings.IsZoomControlEnabled = true;
                c.DocumentTitleChanged += (a, b) => { Text = "Páginas"; };
                c.WindowCloseRequested += (a, b) => Close();
                c.NewWindowRequested += (a, b) => { b.Handled = true; AbrirFora(b.Uri); };
                c.NavigationStarting += (a, b) =>
                {
                    // links de fora (Google, GitHub, sites) abrem no navegador
                    if (b.Uri.StartsWith("http", StringComparison.OrdinalIgnoreCase) && !b.Uri.StartsWith("http://127.0.0.1", StringComparison.OrdinalIgnoreCase)) { b.Cancel = true; AbrirFora(b.Uri); }
                };
                c.NavigationCompleted += (a, b) =>
                {
                    if (b.IsSuccess && c.Source.StartsWith("http://127.0.0.1")) { carregou = true; Teste("ok " + c.Source); }
                };
                string html = Encoding.UTF8.GetString(Lancador.Recurso("abertura.html"));
                wv.NavigateToString(html);
            }
            catch (Exception ex)
            {
                try { File.AppendAllText(Path.Combine(Lancador.pasta, "erro.log"), DateTime.Now.ToString("s") + " janela: " + ex + "\r\n"); } catch { }
                Teste("erro " + ex.Message);
                MessageBox.Show("Não consegui mostrar a janela do Páginas.\n\n" + ex.Message, "Páginas", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Close();
            }
        };
        tm.Tick += (s, e) =>
        {
            if (Lancador.mostrar != null && Lancador.mostrar.WaitOne(0)) Trazer();
            string url = Environment.GetEnvironmentVariable("PAGINAS_URL");
            if (!entregue && url != null && wv.CoreWebView2 != null)
            {
                entregue = true;
                wv.CoreWebView2.ExecuteScriptAsync("window.pronto ? pronto(" + Js(url) + ") : location.replace(" + Js(url) + ")");
            }
            if (!entregue && !Lancador.trabalho.IsAlive && wv.CoreWebView2 != null)
            {
                entregue = true;
                wv.CoreWebView2.ExecuteScriptAsync("window.falha && falha('O Páginas não conseguiu ligar. Feche esta janela e abra de novo. Se continuar, veja o arquivo erro.log na pasta do programa.')");
            }
        };
        tm.Start();
    }

    static string Js(string s) { return "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\""; }

    static void AbrirFora(string uri)
    {
        try { Process.Start(new ProcessStartInfo(uri) { UseShellExecute = true }); } catch { }
    }

    static void Teste(string msg)
    {
        string t = Environment.GetEnvironmentVariable("PAGINAS_TESTE");
        if (string.IsNullOrEmpty(t)) return;
        try { File.WriteAllText(t + ".janela", msg); } catch { }
    }

    static bool TemaEscuro()
    {
        try
        {
            object v = Microsoft.Win32.Registry.GetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme", 1);
            return v is int && (int)v == 0;
        }
        catch { return false; }
    }

    void Trazer()
    {
        if (fechando) return;
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Maximized;
        Show(); Activate(); BringToFront();
        TopMost = true; TopMost = false;
    }

    protected override async void OnFormClosing(FormClosingEventArgs e)
    {
        if (fechando) { base.OnFormClosing(e); return; }
        // guarda a leitura e avisa o programa antes de fechar (ele guarda a cópia no Google Drive e desliga)
        fechando = true;
        e.Cancel = true;
        Hide();
        try
        {
            if (wv.CoreWebView2 != null && carregou)
            {
                await wv.CoreWebView2.ExecuteScriptAsync("try{flushReading(true)}catch(e){};try{flushSave()}catch(e){};try{navigator.sendBeacon('/api/bye?t='+API.token)}catch(e){}");
                await System.Threading.Tasks.Task.Delay(700);
            }
        }
        catch { }
        Environment.SetEnvironmentVariable("PAGINAS_FECHAR", "1");   // o programa termina, guarda a cópia no Google Drive e desliga
        Close();
    }
}

/// Janela "Abrindo o Páginas…" para quando o Windows não tem o WebView2 (o programa abre no Edge).
class Abertura : Form
{
    readonly DateTime ini = DateTime.Now;

    public Abertura()
    {
        Text = "Páginas";
        Icon = Lancador.Icone();
        FormBorderStyle = FormBorderStyle.None;
        StartPosition = FormStartPosition.CenterScreen;
        Size = new Size(340, 140);
        BackColor = Color.FromArgb(246, 241, 231);
        PictureBox img = new PictureBox { Size = new Size(64, 64), Location = new Point(26, 38), SizeMode = PictureBoxSizeMode.Zoom };
        try { img.Image = Lancador.Icone().ToBitmap(); } catch { }
        Label t1 = new Label { Text = "Páginas", Font = new Font("Georgia", 18, FontStyle.Bold), ForeColor = Color.FromArgb(180, 83, 42), AutoSize = true, Location = new Point(104, 40) };
        Label t2 = new Label { Text = "Abrindo sua biblioteca…", Font = new Font("Segoe UI", 10), ForeColor = Color.FromArgb(122, 111, 99), AutoSize = true, Location = new Point(107, 78) };
        Controls.Add(img); Controls.Add(t1); Controls.Add(t2);
        System.Windows.Forms.Timer tm = new System.Windows.Forms.Timer { Interval = 150 };
        tm.Tick += (s, e) =>
        {
            bool pronto = Environment.GetEnvironmentVariable("PAGINAS_PRONTO") == "1";
            if ((pronto && (DateTime.Now - ini).TotalMilliseconds > 900) || !Lancador.trabalho.IsAlive || (DateTime.Now - ini).TotalSeconds > 25) { tm.Stop(); Close(); }
        };
        tm.Start();
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        using (Pen p = new Pen(Color.FromArgb(230, 220, 203))) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
    }
}
