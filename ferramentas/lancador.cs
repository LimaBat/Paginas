// Paginas.exe: abre o Páginas com o ícone e uma janela de abertura.
// O programa (a parte em PowerShell do Paginas.bat) roda DENTRO deste .exe, pelo PowerShell do próprio Windows:
// nada de powershell.exe escondido, de .vbs ou de "ExecutionPolicy Bypass".
// Compilado no GitHub Actions com o csc.exe do .NET Framework (vem em todo Windows).
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
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
    static string pasta;

    [STAThread]
    static int Main(string[] args)
    {
        pasta = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Paginas");
        try
        {
            Directory.CreateDirectory(pasta);
            bool reflexao = args.Length > 0 && args[0] == "--reflexao";
            string exe = Instalar();
            string bat = Path.Combine(pasta, "Paginas.bat");
            if (!reflexao) GuardarPrograma(bat);
            Environment.SetEnvironmentVariable("PAGINAS_SELF", bat);
            Environment.SetEnvironmentVariable("PAGINAS_EXE", exe);
            Environment.SetEnvironmentVariable("PAGINAS_PRONTO", null);

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

            Exception erro = null;
            Thread t = new Thread(() => { try { Rodar(script, null); } catch (Exception e) { erro = e; } });
            t.SetApartmentState(ApartmentState.STA);
            t.IsBackground = false;
            t.Start();

            Application.EnableVisualStyles();
            Application.Run(new Abertura(t));
            t.Join();
            if (erro != null && Environment.GetEnvironmentVariable("PAGINAS_PRONTO") != "1") throw erro;
            return 0;
        }
        catch (Exception e)
        {
            try { File.AppendAllText(Path.Combine(pasta, "erro.log"), DateTime.Now.ToString("s") + " lancador: " + e + "\r\n"); } catch { }
            MessageBox.Show("Não consegui abrir o Páginas.\n\n" + e.Message, "Páginas", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
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
            if (arquivo != null) rs.SessionStateProxy.SetVariable("PSCommandPath", arquivo);
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

    /// Guarda uma cópia do Paginas.exe na pasta do app (os atalhos apontam para ela).
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
        byte[] emb;
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Paginas.bat"))
        using (MemoryStream ms = new MemoryStream()) { s.CopyTo(ms); emb = ms.ToArray(); }
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

    /// Janela "Abrindo o Páginas…" até o programa ficar pronto.
    class Abertura : Form
    {
        readonly Thread trab;
        readonly DateTime ini = DateTime.Now;

        public Abertura(Thread t)
        {
            trab = t;
            Text = "Páginas";
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            Size = new Size(340, 140);
            BackColor = Color.FromArgb(246, 241, 231);
            ShowInTaskbar = true;
            PictureBox img = new PictureBox { Size = new Size(64, 64), Location = new Point(26, 38), SizeMode = PictureBoxSizeMode.Zoom };
            try { img.Image = Icon.ExtractAssociatedIcon(Application.ExecutablePath).ToBitmap(); } catch { }
            Label t1 = new Label { Text = "Páginas", Font = new Font("Georgia", 18, FontStyle.Bold), ForeColor = Color.FromArgb(180, 83, 42), AutoSize = true, Location = new Point(104, 40) };
            Label t2 = new Label { Text = "Abrindo sua biblioteca…", Font = new Font("Segoe UI", 10), ForeColor = Color.FromArgb(122, 111, 99), AutoSize = true, Location = new Point(107, 78) };
            Controls.Add(img); Controls.Add(t1); Controls.Add(t2);
            System.Windows.Forms.Timer tm = new System.Windows.Forms.Timer { Interval = 150 };
            tm.Tick += (s, e) =>
            {
                bool pronto = Environment.GetEnvironmentVariable("PAGINAS_PRONTO") == "1";
                if ((pronto && (DateTime.Now - ini).TotalMilliseconds > 900) || !trab.IsAlive || (DateTime.Now - ini).TotalSeconds > 25) { tm.Stop(); Close(); }
            };
            tm.Start();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen p = new Pen(Color.FromArgb(230, 220, 203))) e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }
}
