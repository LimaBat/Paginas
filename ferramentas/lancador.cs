// Paginas.exe: o mesmo programa do Paginas.bat, num .exe com o ícone do Páginas.
// Guarda o Paginas.bat (embutido aqui dentro) na pasta do app e abre sem janela preta.
// Compilado no GitHub Actions com o csc.exe do .NET Framework (vem em todo Windows).
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

[assembly: AssemblyTitle("Páginas")]
[assembly: AssemblyProduct("Páginas")]
[assembly: AssemblyDescription("Hábito de leitura e biblioteca virtual")]

static class Lancador
{
    [STAThread]
    static void Main()
    {
        try
        {
            string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Paginas");
            Directory.CreateDirectory(dir);
            string bat = Path.Combine(dir, "Paginas.bat");

            byte[] emb;
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Paginas.bat"))
            using (MemoryStream ms = new MemoryStream()) { s.CopyTo(ms); emb = ms.ToArray(); }

            // não troca uma versão mais nova (atualizada pelo próprio programa) pela que veio no .exe
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

            string cmd = "$f=[IO.File]::ReadAllText($env:PAGINAS_SELF,[Text.Encoding]::UTF8).Replace([string][char]13,''); "
                       + "$a='#PS_'+'START'+[string][char]10; $b=[string][char]10+'::HTML_'+'START'; "
                       + "$i=$f.IndexOf($a)+$a.Length; $j=$f.IndexOf($b); & ([scriptblock]::Create($f.Substring($i,$j-$i)))";
            ProcessStartInfo psi = new ProcessStartInfo("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"" + cmd + "\"");
            psi.UseShellExecute = false;
            psi.CreateNoWindow = true;
            psi.WorkingDirectory = dir;
            psi.EnvironmentVariables["PAGINAS_SELF"] = bat;
            Process.Start(psi);
        }
        catch (Exception e)
        {
            MessageBox.Show("Não consegui abrir o Páginas.\n\n" + e.Message, "Páginas", MessageBoxButtons.OK, MessageBoxIcon.Error);
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
}
