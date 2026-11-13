@echo off
setlocal
rem Paginas - habito de leitura + biblioteca virtual (programa em arquivo unico)
rem De dois cliques para abrir. Nao precisa instalar nada.
set "PAGINAS_SELF=%~f0"
start "" /min powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$f=[IO.File]::ReadAllText($env:PAGINAS_SELF,[Text.Encoding]::UTF8).Replace([string][char]13,''); $a='#PS_'+'START'+[string][char]10; $b=[string][char]10+'::HTML_'+'START'; $i=$f.IndexOf($a)+$a.Length; $j=$f.IndexOf($b); & ([scriptblock]::Create($f.Substring($i,$j-$i)))"
exit /b 0
#PS_START
$ErrorActionPreference = 'Stop'
# ---- configuracao de distribuicao (preenchida na publicacao por ferramentas/preparar.py) ----
$APP_VERSAO = '1.0'
$ATUALIZA_REPO = ''
$IA_PROXY_URL = ''
$IA_PROXY_TOKEN = ''
$G_CLIENT_ID = ''
$G_CLIENT_SECRET = ''
$SOCIAL_URL = ''
if ($IA_PROXY_URL -and $IA_PROXY_URL -notmatch '^https?://') { $IA_PROXY_URL = 'https://' + $IA_PROXY_URL }
$IA_PROXY_URL = $IA_PROXY_URL.TrimEnd('/')
if ($SOCIAL_URL -and $SOCIAL_URL -notmatch '^https?://') { $SOCIAL_URL = 'https://' + $SOCIAL_URL }
$SOCIAL_URL = $SOCIAL_URL.TrimEnd('/')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$dir = Join-Path $env:LOCALAPPDATA 'Paginas'
$EXE = [string]$env:PAGINAS_EXE   # caminho do Paginas.exe quando o programa foi aberto por ele
if ($EXE -and -not (Test-Path -LiteralPath $EXE)) { $EXE = '' }
try {
  [void](New-Item -ItemType Directory -Force -Path $dir)
  $booksDir = Join-Path $dir 'livros'
  [void](New-Item -ItemType Directory -Force -Path $booksDir)
  $dataFile = Join-Path $dir 'dados.json'
  $bakFile = Join-Path $dir 'dados.anterior.json'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  $cfgFile = Join-Path $dir 'config.json'
  function Get-Cfg {
    $c = @{ apiKey = ''; googleClientId = ''; port = 0; gRefresh = ''; gEmail = ''; gName = ''; gPic = '' }
    if (Test-Path -LiteralPath $cfgFile) {
      try {
        $j = [IO.File]::ReadAllText($cfgFile, [Text.Encoding]::UTF8) | ConvertFrom-Json
        if ($j.apiKey) { $c.apiKey = [string]$j.apiKey }
        if ($j.googleClientId) { $c.googleClientId = [string]$j.googleClientId }
        if ($j.port) { $c.port = [int]$j.port }
        foreach ($k in @('gRefresh', 'gEmail', 'gName', 'gPic')) { if ($j.$k) { $c[$k] = [string]$j.$k } }
      } catch { }
    }
    return $c
  }
  function Save-Cfg($c) {
    [IO.File]::WriteAllText($cfgFile, (ConvertTo-Json -Compress -InputObject $c), $utf8)
  }
  function Read-Body($req) {
    $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
    $b = $sr.ReadToEnd()
    $sr.Close()
    return $b
  }

  # ---- icone do aplicativo (desenhado por codigo) ----
  function New-Logo([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $r = [int]($s * 0.22)
    $d = $r * 2
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddArc(0, 0, $d, $d, 180, 90)
    $gp.AddArc($s - $d - 1, 0, $d, $d, 270, 90)
    $gp.AddArc($s - $d - 1, $s - $d - 1, $d, $d, 0, 90)
    $gp.AddArc(0, $s - $d - 1, $d, $d, 90, 90)
    $gp.CloseFigure()
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s, $s)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb(255, 224, 138, 92), [System.Drawing.Color]::FromArgb(255, 160, 64, 30), 55.0)
    $g.FillPath($br, $gp)
    $P = { param($x, $y) New-Object System.Drawing.PointF([single]($x * $s), [single]($y * $s)) }
    $left = [System.Drawing.PointF[]]@((& $P 0.16 0.34), (& $P 0.48 0.43), (& $P 0.48 0.80), (& $P 0.16 0.71))
    $right = [System.Drawing.PointF[]]@((& $P 0.52 0.43), (& $P 0.84 0.34), (& $P 0.84 0.71), (& $P 0.52 0.80))
    $w1 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 255, 252, 246))
    $w2 = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 246, 232, 212))
    $g.FillPolygon($w1, $left)
    $g.FillPolygon($w2, $right)
    if ($s -ge 48) {
      $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 180, 83, 42), [single]($s * 0.018))
      $g.DrawLine($pen, (& $P 0.22 0.50), (& $P 0.43 0.55))
      $g.DrawLine($pen, (& $P 0.22 0.58), (& $P 0.43 0.63))
      $g.DrawLine($pen, (& $P 0.57 0.55), (& $P 0.78 0.50))
      $g.DrawLine($pen, (& $P 0.57 0.63), (& $P 0.78 0.58))
      $pen.Dispose()
    }
    $g.Dispose(); $br.Dispose(); $w1.Dispose(); $w2.Dispose(); $gp.Dispose()
    return $bmp
  }
  function Save-Ico([string]$file) {
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    $pngs = @()
    foreach ($z in $sizes) {
      $b = New-Logo $z
      $ms = New-Object IO.MemoryStream
      $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
      $pngs += , ($ms.ToArray())
      $b.Dispose()
    }
    $fs = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter($fs)
    $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$sizes.Count)
    $off = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
      $z = $sizes[$i]
      $wb = $z
      if ($z -ge 256) { $wb = 0 }
      $len = $pngs[$i].Length
      $bw.Write([byte]$wb); $bw.Write([byte]$wb); $bw.Write([byte]0); $bw.Write([byte]0)
      $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$len); $bw.Write([uint32]$off)
      $off += $len
    }
    foreach ($p in $pngs) { $bw.Write([byte[]]$p) }
    $bw.Flush()
    [IO.File]::WriteAllBytes($file, $fs.ToArray())
  }

  # ---- arquivos do icone, launcher oculto e atalhos (sem janela preta) ----
  $icoFile = Join-Path $dir 'paginas.ico'
  $pngFile = Join-Path $dir 'icone.png'
  $flag = Join-Path $dir 'atalho.ok'
  $flagTxt = ''
  try { if (Test-Path -LiteralPath $flag) { $flagTxt = [IO.File]::ReadAllText($flag).Trim() } } catch { }
  $marca = $APP_VERSAO
  if ($EXE) { $marca = $APP_VERSAO + '|exe' }
  $versaoNova = $flagTxt -ne $marca   # primeira vez, versao nova ou troca de .bat para .exe: refaz o icone e os atalhos
  try {
    if ($versaoNova -or -not (Test-Path -LiteralPath $icoFile)) { Save-Ico $icoFile }
    if (-not (Test-Path -LiteralPath $pngFile)) { $lb = New-Logo 128; $lb.Save($pngFile, [System.Drawing.Imaging.ImageFormat]::Png); $lb.Dispose() }
  } catch { }
  try {
    $appBat = Join-Path $dir 'Paginas.bat'
    $copiar = $env:PAGINAS_SELF -ne $appBat
    if ($copiar -and (Test-Path -LiteralPath $appBat)) {
      # nao troca uma versao mais nova (atualizada pelo programa) por um arquivo antigo baixado antes
      try {
        $vm = [regex]::Match([IO.File]::ReadAllText($appBat), '(?m)^\$APP_VERSAO = .([0-9.]+).')
        if ($vm.Success -and ([version]($vm.Groups[1].Value + '.0') -gt [version]($APP_VERSAO + '.0'))) { $copiar = $false }
      } catch { }
    }
    if ($copiar) { Copy-Item -LiteralPath $env:PAGINAS_SELF -Destination $appBat -Force }
    $psCmd = @'
$f=[IO.File]::ReadAllText($env:PAGINAS_SELF,[Text.Encoding]::UTF8).Replace([string][char]13,''); $a='#PS_'+'START'+[string][char]10; $b=[string][char]10+'::HTML_'+'START'; $i=$f.IndexOf($a)+$a.Length; $j=$f.IndexOf($b); & ([scriptblock]::Create($f.Substring($i,$j-$i)))
'@
    $vb = 'Set sh = CreateObject("WScript.Shell")' + "`r`n" + 'sh.Environment("Process")("PAGINAS_SELF") = "' + $appBat + '"' + "`r`n" + 'sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command ""' + $psCmd.Trim() + '""", 0, False' + "`r`n"
    $vbsFile = Join-Path $dir 'abrir.vbs'
    if ($EXE) { if (Test-Path -LiteralPath $vbsFile) { Remove-Item -LiteralPath $vbsFile -Force } }
    else { [IO.File]::WriteAllText($vbsFile, $vb, [Text.Encoding]::Unicode) }
    if ($versaoNova) {
      $wsh = New-Object -ComObject WScript.Shell
      $desk = [Environment]::GetFolderPath('Desktop')
      foreach ($folder in @($desk, [Environment]::GetFolderPath('Programs'))) {
        if ($folder -and (Test-Path -LiteralPath $folder)) {
          $lnkPath = Join-Path $folder 'Páginas.lnk'
          # na Area de Trabalho: cria na primeira vez; depois so atualiza o atalho que ainda existe (respeita quem apagou)
          if ($folder -eq $desk -and $flagTxt -and -not (Test-Path -LiteralPath $lnkPath)) { continue }
          $lnk = $wsh.CreateShortcut($lnkPath)
          if ($EXE) {
            $lnk.TargetPath = $EXE
            $lnk.Arguments = ''
            $lnk.IconLocation = $EXE + ',0'
          } else {
            $lnk.TargetPath = Join-Path $env:WINDIR 'System32\wscript.exe'
            $lnk.Arguments = '"' + $vbsFile + '"'
            $lnk.IconLocation = $icoFile + ',0'
          }
          $lnk.WorkingDirectory = $dir
          $lnk.Description = 'Páginas: hábito de leitura e biblioteca virtual'
          $lnk.Save()
        }
      }
      [IO.File]::WriteAllText($flag, $marca, $utf8)
      # pede ao Windows para redesenhar os icones (sem isso, as vezes fica o icone antigo em cache)
      try { $ie = Join-Path $env:WINDIR 'System32\ie4uinit.exe'; if (Test-Path -LiteralPath $ie) { [void](Start-Process -FilePath $ie -ArgumentList '-show' -WindowStyle Hidden) } } catch { }
    }
  } catch { }

  # ---- HTML do programa (embutido no final deste arquivo .bat) ----
  $all = [IO.File]::ReadAllText($env:PAGINAS_SELF, [Text.Encoding]::UTF8).Replace([string][char]13, '')
  $mark = '::HTML_' + 'START' + [string][char]10
  $hi = $all.IndexOf($mark)
  if ($hi -lt 0) { throw 'Arquivo do programa incompleto (HTML nao encontrado).' }
  $token = [guid]::NewGuid().ToString('N')
  $html = $all.Substring($hi + $mark.Length).Replace('__TOKEN__', $token).Replace('__VERSAO__', $APP_VERSAO).Replace('__REPO__', $ATUALIZA_REPO).Replace('__PLAT__', 'windows').Replace('__SOCIAL__', $SOCIAL_URL)

  # ---- servidor local (somente neste computador) ----
  $fixedPort = 0
  try { $fixedPort = [int](Get-Cfg).port } catch { }
  $listener = $null
  $port = 0
  foreach ($try in 1..40) {
    $p = Get-Random -Minimum 49200 -Maximum 65000
    if ($try -eq 1 -and $fixedPort -ge 1024 -and $fixedPort -le 65535) { $p = $fixedPort }
    $l = New-Object System.Net.HttpListener
    $l.Prefixes.Add('http://127.0.0.1:' + $p + '/')
    try { $l.Start(); $listener = $l; $port = $p; break } catch { $l.Close() }
  }
  if ($null -eq $listener) { throw 'Nao foi possivel abrir uma porta local.' }

  $S = @{ lastPing = Get-Date; everPinged = $false; byeAt = $null; dirty = $false; restart = $null; gAccess = ''; gExp = (Get-Date) }
  $OA = @{}
  $cache = @{}
  $allowedParams = @('search', 'languages', 'topic', 'page', 'sort', 'ids')

  function Send-Bytes($ctx, [int]$code, [string]$type, [byte[]]$bytes) {
    try {
      $r = $ctx.Response
      $r.StatusCode = $code
      $r.ContentType = $type
      $r.Headers.Add('Cache-Control', 'no-store')
      $r.ContentLength64 = $bytes.Length
      if ($bytes.Length -gt 0) { $r.OutputStream.Write($bytes, 0, $bytes.Length) }
      $r.OutputStream.Close()
    } catch { }
  }
  function Send-Text($ctx, [int]$code, [string]$type, [string]$text) {
    Send-Bytes $ctx $code $type ([Text.Encoding]::UTF8.GetBytes($text))
  }
  function Send-Json($ctx, [int]$code, [string]$json) {
    Send-Text $ctx $code 'application/json; charset=utf-8' $json
  }
  function Get-Remote([string]$url) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.Timeout = 30000
    $req.ReadWriteTimeout = 30000
    $req.UserAgent = 'Paginas/1.0 (leitor pessoal de livros)'
    $req.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $resp = $req.GetResponse()
    try {
      $ms = New-Object IO.MemoryStream
      $resp.GetResponseStream().CopyTo($ms)
      return , $ms.ToArray()
    } finally { $resp.Close() }
  }

  # ---- pedidos HTTP com corpo e cabecalhos (IA, Google) ----
  function Invoke-Http([string]$method, [string]$url, [string]$ctype, [byte[]]$body, $headers) {
    $rq = [Net.HttpWebRequest]::Create($url)
    $rq.Method = $method
    $rq.Timeout = 90000
    $rq.ReadWriteTimeout = 90000
    $rq.UserAgent = 'Paginas/' + $APP_VERSAO
    if ($headers) { foreach ($k in $headers.Keys) { if ([string]$headers[$k]) { $rq.Headers.Add($k, [string]$headers[$k]) } } }
    if ($null -ne $body) {
      $rq.ContentType = $ctype
      $rq.ContentLength = $body.Length
      $os = $rq.GetRequestStream()
      $os.Write($body, 0, $body.Length)
      $os.Close()
    }
    try { $resp = $rq.GetResponse() }
    catch [Net.WebException] { $resp = $_.Exception.Response; if (-not $resp) { throw } }
    try {
      $ms = New-Object IO.MemoryStream
      $resp.GetResponseStream().CopyTo($ms)
      return @{ code = [int]$resp.StatusCode; text = [Text.Encoding]::UTF8.GetString($ms.ToArray()) }
    } finally { $resp.Close() }
  }
  function Form-Bytes($h) {
    $p = foreach ($k in $h.Keys) { [Uri]::EscapeDataString($k) + '=' + [Uri]::EscapeDataString([string]$h[$k]) }
    return , ([Text.Encoding]::UTF8.GetBytes(($p -join '&')))
  }
  function Json-Bytes($o) { return , ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -Compress -Depth 8 -InputObject $o))) }
  function B64Url([byte[]]$b) { return [Convert]::ToBase64String($b).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
  function New-Rand([int]$n) {
    $b = New-Object byte[] $n
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($b)
    $rng.Dispose()
    return (B64Url $b)
  }

  # ---- notificacao de reflexao (roda sozinha pela tarefa agendada do Windows) ----
  $NOTIF_PS1 = @'
$ErrorActionPreference = 'Stop'
try {
  $d = Split-Path -Parent $MyInvocation.MyCommand.Path
  $f = [IO.File]::ReadAllText((Join-Path $d 'Paginas.bat'), [Text.Encoding]::UTF8)
  $m = [regex]::Match($f, '<script type="application/json" id="refle[x]oes">([\s\S]*?)</script>')
  $l = @($m.Groups[1].Value | ConvertFrom-Json)
  $r = $l[(Get-Random -Maximum $l.Count)]
  $t = [Security.SecurityElement]::Escape([string]$r.t)
  $a = ''
  if ($r.a) { $a = '<text placement="attribution">' + [Security.SecurityElement]::Escape('— ' + [string]$r.a) + '</text>' }
  $ico = (Join-Path $d 'icone.png') -replace '\\', '/'
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $x = New-Object Windows.Data.Xml.Dom.XmlDocument
  $x.LoadXml('<toast><visual><binding template="ToastGeneric"><image placement="appLogoOverride" hint-crop="circle" src="file:///' + $ico + '"/><text>Reflexão do Páginas 💭</text><text>' + $t + '</text>' + $a + '</binding></visual></toast>')
  $app = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($app).Show((New-Object Windows.UI.Notifications.ToastNotification $x))
} catch {
  [IO.File]::AppendAllText((Join-Path $env:LOCALAPPDATA 'Paginas\erro.log'), ((Get-Date).ToString('s') + ' notificacao: ' + $_.Exception.Message + "`r`n"))
}
'@

  # ---- conta Google (fluxo de "app para computador" com PKCE, igual ao Investe.AI) e copia dos dados no Google Drive ----
  $G_AUTH = 'https://accounts.google.com/o/oauth2/v2/auth'
  $G_TOKEN = 'https://oauth2.googleapis.com/token'
  $G_ESCOPO = 'openid email profile https://www.googleapis.com/auth/drive.appdata'
  $DRIVE_ARQ = 'paginas_dados.json'
  function Get-GAccess {
    $c = Get-Cfg
    if (-not $c.gRefresh) { throw 'Entre com sua conta Google primeiro.' }
    if ($S.gAccess -and $S.gExp -gt (Get-Date).AddSeconds(60)) { return $S.gAccess }
    $r = Invoke-Http 'POST' $G_TOKEN 'application/x-www-form-urlencoded' (Form-Bytes @{ client_id = $G_CLIENT_ID; client_secret = $G_CLIENT_SECRET; refresh_token = $c.gRefresh; grant_type = 'refresh_token' }) $null
    $j = $null
    try { $j = $r.text | ConvertFrom-Json } catch { }
    if (-not $j -or -not $j.access_token) {
      if ($j -and $j.error -eq 'invalid_grant') {
        foreach ($k in @('gRefresh', 'gEmail', 'gName', 'gPic')) { $c[$k] = '' }
        Save-Cfg $c
        throw 'Sua sessão do Google expirou. Entre de novo em Ajustes.'
      }
      throw ('O Google não liberou o acesso agora (erro ' + $r.code + ').')
    }
    $S.gAccess = [string]$j.access_token
    $S.gExp = (Get-Date).AddSeconds([int]$j.expires_in)
    return $S.gAccess
  }
  function Find-DriveFile([string]$at) {
    $q = [Uri]::EscapeDataString("name='" + $DRIVE_ARQ + "'")
    $r = Invoke-Http 'GET' ('https://www.googleapis.com/drive/v3/files?spaces=appDataFolder&fields=files(id,modifiedTime)&q=' + $q) $null $null @{ Authorization = 'Bearer ' + $at }
    if ($r.code -ne 200) { throw ('Google Drive: erro ' + $r.code + ' ao procurar seus dados.') }
    $f = @(($r.text | ConvertFrom-Json).files) | Where-Object { $_ } | Select-Object -First 1
    if ($f) { return [string]$f.id }
    return ''
  }
  function Push-Drive {
    if (-not (Test-Path -LiteralPath $dataFile)) { return }
    $at = Get-GAccess
    $bytes = [IO.File]::ReadAllBytes($dataFile)
    $id = Find-DriveFile $at
    $h = @{ Authorization = 'Bearer ' + $at }
    if ($id) {
      $r = Invoke-Http 'PATCH' ('https://www.googleapis.com/upload/drive/v3/files/' + $id + '?uploadType=media') 'application/json' $bytes $h
    } else {
      $bd = 'pgn' + [guid]::NewGuid().ToString('N')
      $meta = '{"name":"' + $DRIVE_ARQ + '","parents":["appDataFolder"]}'
      $pre = [Text.Encoding]::UTF8.GetBytes('--' + $bd + "`r`nContent-Type: application/json; charset=UTF-8`r`n`r`n" + $meta + "`r`n--" + $bd + "`r`nContent-Type: application/json`r`n`r`n")
      $pos = [Text.Encoding]::UTF8.GetBytes("`r`n--" + $bd + "--`r`n")
      $buf = New-Object byte[] ($pre.Length + $bytes.Length + $pos.Length)
      [Array]::Copy($pre, 0, $buf, 0, $pre.Length)
      [Array]::Copy($bytes, 0, $buf, $pre.Length, $bytes.Length)
      [Array]::Copy($pos, 0, $buf, $pre.Length + $bytes.Length, $pos.Length)
      $r = Invoke-Http 'POST' 'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart' ('multipart/related; boundary=' + $bd) $buf $h
    }
    if ($r.code -ne 200) { throw ('Google Drive: erro ' + $r.code + ' ao guardar seus dados.') }
    $S.dirty = $false
  }
  function Pull-Drive {
    $at = Get-GAccess
    $id = Find-DriveFile $at
    if (-not $id) { return $null }
    $r = Invoke-Http 'GET' ('https://www.googleapis.com/drive/v3/files/' + $id + '?alt=media') $null $null @{ Authorization = 'Bearer ' + $at }
    if ($r.code -ne 200) { throw ('Google Drive: erro ' + $r.code + ' ao trazer seus dados.') }
    return $r.text
  }
  function Google-Page([string]$msg, [bool]$ok) {
    $cor = '#2f7d4f'
    $tit = 'Pronto'
    if (-not $ok) { $cor = '#b4532a'; $tit = 'Não deu certo' }
    $m = [Net.WebUtility]::HtmlEncode($msg)
    return '<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Páginas</title><body style="font-family:system-ui,sans-serif;background:#f6f1e7;color:#2b2118;display:grid;place-items:center;height:100vh;margin:0"><div style="text-align:center;max-width:440px;padding:24px"><div style="font-size:40px;font-weight:800;color:' + $cor + '">' + $tit + '</div><p style="font-size:18px">' + $m + '</p></div></body>'
  }
  function Google-Callback($q) {
    $st = $null
    $sk = [string]$q['state']
    if ($sk -and $OA.ContainsKey($sk)) { $st = $OA[$sk]; $OA.Remove($sk) }
    if (-not $st -or ((Get-Date) - $st.t).TotalMinutes -gt 15) { return (Google-Page 'A sessão de login expirou. Volte ao Páginas e tente de novo.' $false) }
    if ($q['error']) { return (Google-Page 'Login cancelado ou recusado pelo Google.' $false) }
    $r = Invoke-Http 'POST' $G_TOKEN 'application/x-www-form-urlencoded' (Form-Bytes @{ code = [string]$q['code']; client_id = $G_CLIENT_ID; client_secret = $G_CLIENT_SECRET; redirect_uri = $st.redir; grant_type = 'authorization_code'; code_verifier = $st.v }) $null
    $j = $null
    try { $j = $r.text | ConvertFrom-Json } catch { }
    if (-not $j -or -not $j.access_token) {
      $e = 'erro desconhecido'
      if ($j -and $j.error_description) { $e = [string]$j.error_description } elseif ($j -and $j.error) { $e = [string]$j.error }
      return (Google-Page ('O Google recusou o login: ' + $e) $false)
    }
    $u = (Invoke-Http 'GET' 'https://openidconnect.googleapis.com/v1/userinfo' $null $null @{ Authorization = 'Bearer ' + [string]$j.access_token }).text | ConvertFrom-Json
    $c = Get-Cfg
    if ($j.refresh_token) { $c.gRefresh = [string]$j.refresh_token }
    if (-not $c.gRefresh) { return (Google-Page 'O Google não deu acesso permanente. Tente entrar de novo.' $false) }
    $c.gEmail = [string]$u.email
    $c.gName = [string]$u.name
    $c.gPic = [string]$u.picture
    Save-Cfg $c
    $S.gAccess = [string]$j.access_token
    $S.gExp = (Get-Date).AddSeconds([int]$j.expires_in)
    return (Google-Page 'Conta Google conectada! Pode fechar esta aba e voltar ao Páginas.' $true)
  }
  function Google-Status {
    $c = Get-Cfg
    return (ConvertTo-Json -Compress -InputObject @{ available = [bool]($G_CLIENT_ID -and $G_CLIENT_SECRET); connected = [bool]$c.gRefresh; email = $c.gEmail; name = $c.gName; picture = $c.gPic })
  }

  function Handle-Request($ctx) {
    $req = $ctx.Request
    $path = $req.Url.AbsolutePath
    if ($req.UserHostName -ne ('127.0.0.1:' + $port)) { Send-Text $ctx 403 'text/plain' 'proibido'; return }
    if ($path -eq '/') { Send-Text $ctx 200 'text/html; charset=utf-8' $html; return }
    $q = $req.QueryString
    if ($path -eq '/oauth/google/callback') {
      $pg = ''
      try { $pg = Google-Callback $q } catch { $pg = Google-Page ('Falha ao falar com o Google: ' + $_.Exception.Message) $false }
      Send-Text $ctx 200 'text/html; charset=utf-8' $pg
      return
    }
    if ($q['t'] -ne $token) { Send-Json $ctx 403 '{"error":"acesso negado"}'; return }

    if ($path -eq '/api/ping') {
      $S.lastPing = Get-Date; $S.everPinged = $true
      Send-Json $ctx 200 '{"ok":true}'
    }
    elseif ($path -eq '/api/bye') {
      $S.byeAt = Get-Date
      Send-Json $ctx 200 '{"ok":true}'
    }
    elseif ($path -eq '/api/load') {
      if (Test-Path -LiteralPath $dataFile) { Send-Text $ctx 200 'application/json; charset=utf-8' ([IO.File]::ReadAllText($dataFile, [Text.Encoding]::UTF8)) }
      else { Send-Json $ctx 200 '{}' }
    }
    elseif ($path -eq '/api/save' -and $req.HttpMethod -eq 'POST') {
      $sr = New-Object IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
      $body = $sr.ReadToEnd()
      $sr.Close()
      if ($body.Length -lt 2 -or $body.Length -gt 30000000 -or $body[0] -ne '{') { Send-Json $ctx 400 '{"error":"dados invalidos"}'; return }
      $tmp = $dataFile + '.tmp'
      [IO.File]::WriteAllText($tmp, $body, $utf8)
      if (Test-Path -LiteralPath $dataFile) { Copy-Item -LiteralPath $dataFile -Destination $bakFile -Force }
      Move-Item -LiteralPath $tmp -Destination $dataFile -Force
      $S.dirty = $true
      Send-Json $ctx 200 '{"ok":true}'
    }
    elseif ($path -eq '/api/google/status') { Send-Json $ctx 200 (Google-Status) }
    elseif ($path -eq '/api/google/token') {
      # acesso do Google para entrar na Comunidade (o servidor social confirma a conta com o proprio Google)
      Send-Json $ctx 200 (ConvertTo-Json -Compress -InputObject @{ token = (Get-GAccess) })
    }
    elseif ($path -eq '/api/notif' -and $req.HttpMethod -eq 'POST') {
      $in = (Read-Body $req) | ConvertFrom-Json
      $nomeTarefa = 'Paginas - Reflexoes'
      $ps1 = Join-Path $dir 'notificar.ps1'
      $vbsN = Join-Path $dir 'notificar.vbs'
      [IO.File]::WriteAllText($ps1, $NOTIF_PS1, (New-Object System.Text.UTF8Encoding($true)))
      if ($EXE) { if (Test-Path -LiteralPath $vbsN) { Remove-Item -LiteralPath $vbsN -Force } }
      else {
        $vbsTxt = 'CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""' + $ps1 + '""", 0, False' + "`r`n"
        [IO.File]::WriteAllText($vbsN, $vbsTxt, [Text.Encoding]::Unicode)
      }
      try { Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false -ErrorAction SilentlyContinue } catch { }
      if ($in.on) {
        $gat = @()
        foreach ($h in @($in.horas)) { if ([string]$h -match '^\d{1,2}:\d{2}$') { $gat += New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact([string]$h, 'H:mm', $null)) } }
        if (-not $gat.Count) { $gat += New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact('09:00', 'H:mm', $null)) }
        if ($EXE) { $acao = New-ScheduledTaskAction -Execute $EXE -Argument '--reflexao' }
        else { $acao = New-ScheduledTaskAction -Execute (Join-Path $env:WINDIR 'System32\wscript.exe') -Argument ('"' + $vbsN + '"') }
        $cfgT = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
        [void](Register-ScheduledTask -TaskName $nomeTarefa -Action $acao -Trigger $gat -Settings $cfgT -Description 'Reflexoes do Paginas' -Force)
      }
      Send-Json $ctx 200 '{"ok":true}'
    }
    elseif ($path -eq '/api/notif/teste' -and $req.HttpMethod -eq 'POST') {
      $ps1 = Join-Path $dir 'notificar.ps1'
      [IO.File]::WriteAllText($ps1, $NOTIF_PS1, (New-Object System.Text.UTF8Encoding($true)))
      if ($EXE) { [void](Start-Process -FilePath $EXE -ArgumentList '--reflexao') }
      else { [void](Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $ps1 + '"') -WindowStyle Hidden) }
      Send-Json $ctx 200 '{"ok":true}'
    }
    elseif ($path -eq '/api/google/start') {
      if (-not ($G_CLIENT_ID -and $G_CLIENT_SECRET)) { Send-Json $ctx 400 '{"error":"O login com Google não está ativado nesta cópia do programa."}'; return }
      foreach ($k in @($OA.Keys)) { if (((Get-Date) - $OA[$k].t).TotalMinutes -gt 15) { $OA.Remove($k) } }
      $sk = New-Rand 24
      $ver = New-Rand 48
      $sha = [Security.Cryptography.SHA256]::Create()
      $chal = B64Url ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($ver)))
      $sha.Dispose()
      $redir = 'http://127.0.0.1:' + $port + '/oauth/google/callback'
      $OA[$sk] = @{ v = $ver; t = Get-Date; redir = $redir }
      $prm = @{ client_id = $G_CLIENT_ID; redirect_uri = $redir; response_type = 'code'; scope = $G_ESCOPO; state = $sk; code_challenge = $chal; code_challenge_method = 'S256'; access_type = 'offline'; prompt = 'consent select_account' }
      $u = $G_AUTH + '?' + (($prm.Keys | ForEach-Object { $_ + '=' + [Uri]::EscapeDataString([string]$prm[$_]) }) -join '&')
      try { [void](Start-Process $u) } catch { }
      Send-Json $ctx 200 (ConvertTo-Json -Compress -InputObject @{ ok = $true; url = $u })
    }
    elseif ($path -eq '/api/google/logout') {
      $c = Get-Cfg
      if ($c.gRefresh) { try { [void](Invoke-Http 'POST' 'https://oauth2.googleapis.com/revoke' 'application/x-www-form-urlencoded' (Form-Bytes @{ token = $c.gRefresh }) $null) } catch { } }
      foreach ($k in @('gRefresh', 'gEmail', 'gName', 'gPic')) { $c[$k] = '' }
      Save-Cfg $c
      $S.gAccess = ''
      Send-Json $ctx 200 (Google-Status)
    }
    elseif ($path -eq '/api/google/push' -and $req.HttpMethod -eq 'POST') {
      Push-Drive
      Send-Json $ctx 200 '{"ok":true}'
    }
    elseif ($path -eq '/api/google/pull') {
      $txt = Pull-Drive
      if ($null -eq $txt) { Send-Bytes $ctx 204 'application/json' ([byte[]]@()) }
      else { Send-Text $ctx 200 'application/json; charset=utf-8' $txt }
    }
    elseif ($path -eq '/api/atualizar' -and $req.HttpMethod -eq 'POST') {
      if (-not $ATUALIZA_REPO) { Send-Json $ctx 400 '{"error":"Esta cópia não tem atualização automática."}'; return }
      $nb = Get-Remote ('https://github.com/' + $ATUALIZA_REPO + '/releases/latest/download/Paginas.bat')
      $nt = [Text.Encoding]::UTF8.GetString($nb)
      if ($nt.IndexOf('#PS_START') -lt 0 -or $nt.IndexOf('::HTML_START') -lt 0 -or $nb.Length -lt 50000) { Send-Json $ctx 502 '{"error":"O arquivo baixado veio incompleto. Tente de novo mais tarde."}'; return }
      $dest = Join-Path $dir 'Paginas.bat'
      [IO.File]::WriteAllBytes($dest + '.novo', $nb)
      Move-Item -LiteralPath ($dest + '.novo') -Destination $dest -Force
      $S.restart = Get-Date
      Send-Json $ctx 200 '{"ok":true}'
    }
    elseif ($path -eq '/api/catalog') {
      $parts = @()
      foreach ($k in $allowedParams) {
        $v = $q[$k]
        if ($v) { $parts += ($k + '=' + [Uri]::EscapeDataString($v)) }
      }
      $u = 'https://gutendex.com/books/?' + ($parts -join '&')
      $hit = $cache[$u]
      if ($hit -and ((Get-Date) - $hit.t).TotalMinutes -lt 20) { $bytes = $hit.b }
      else {
        $bytes = Get-Remote $u
        $cache[$u] = @{ t = Get-Date; b = $bytes }
      }
      Send-Bytes $ctx 200 'application/json; charset=utf-8' $bytes
    }
    elseif ($path -eq '/api/cover') {
      $ct = $q['title']; $ca = $q['author']
      if (-not $ct -or $ct.Length -gt 200) { Send-Json $ctx 400 '{"error":"titulo invalido"}'; return }
      $u = 'https://openlibrary.org/search.json?limit=5&fields=cover_i,title,author_name&title=' + [Uri]::EscapeDataString($ct)
      if ($ca -and $ca.Length -le 200) { $u += '&author=' + [Uri]::EscapeDataString($ca) }
      $hit = $cache[$u]
      if ($hit -and ((Get-Date) - $hit.t).TotalHours -lt 12) { $bytes = $hit.b }
      else { $bytes = Get-Remote $u; $cache[$u] = @{ t = Get-Date; b = $bytes } }
      Send-Bytes $ctx 200 'application/json; charset=utf-8' $bytes
    }
    elseif ($path -eq '/api/book') {
      $gid = $q['gid']
      if ($gid -notmatch '^[0-9]{1,9}$') { Send-Json $ctx 400 '{"error":"livro invalido"}'; return }
      $file = Join-Path $booksDir ($gid + '.txt')
      if (-not (Test-Path -LiteralPath $file)) {
        $u = $q['u']
        $uri = $null
        if (-not [Uri]::TryCreate($u, [UriKind]::Absolute, [ref]$uri) -or ($uri.Scheme -ne 'https' -and $uri.Scheme -ne 'http') -or ($uri.Host -notmatch '(^|\.)gutenberg\.org$')) {
          Send-Json $ctx 400 '{"error":"endereco de livro nao permitido"}'; return
        }
        $raw = Get-Remote $u
        $text = [Text.Encoding]::UTF8.GetString($raw)
        if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
        if ($text.Length -lt 500) { throw 'O texto baixado veio vazio.' }
        [IO.File]::WriteAllText($file, $text, $utf8)
      }
      Send-Bytes $ctx 200 'text/plain; charset=utf-8' ([IO.File]::ReadAllBytes($file))
    }
    elseif ($path -eq '/api/icon') {
      if (Test-Path -LiteralPath $pngFile) { Send-Bytes $ctx 200 'image/png' ([IO.File]::ReadAllBytes($pngFile)) }
      else { Send-Json $ctx 404 '{"error":"sem icone"}' }
    }
    elseif ($path -eq '/api/config') {
      $cfg = Get-Cfg
      if ($req.HttpMethod -eq 'POST') {
        $in = (Read-Body $req) | ConvertFrom-Json
        if ($null -ne $in.apiKey) {
          $k = ([string]$in.apiKey).Trim()
          if ($k.Length -gt 300) { Send-Json $ctx 400 '{"error":"chave invalida"}'; return }
          $cfg.apiKey = $k
        }
        if ($null -ne $in.googleClientId) {
          $g = ([string]$in.googleClientId).Trim()
          if ($g.Length -gt 300) { Send-Json $ctx 400 '{"error":"client id invalido"}'; return }
          $cfg.googleClientId = $g
        }
        if ($null -ne $in.port) {
          $pp = 0
          [void][int]::TryParse([string]$in.port, [ref]$pp)
          if ($pp -ne 0 -and ($pp -lt 1024 -or $pp -gt 65535)) { Send-Json $ctx 400 '{"error":"use uma porta entre 1024 e 65535"}'; return }
          $cfg.port = $pp
        }
        Save-Cfg $cfg
      }
      Send-Json $ctx 200 (ConvertTo-Json -Compress -InputObject @{ hasKey = [bool]$cfg.apiKey; proxy = [bool]$IA_PROXY_URL; googleClientId = [string]$cfg.googleClientId; port = [int]$cfg.port })
    }
    elseif ($path -eq '/api/ai' -and $req.HttpMethod -eq 'POST') {
      $cfg = Get-Cfg
      if (-not $cfg.apiKey -and -not $IA_PROXY_URL) { Send-Json $ctx 400 '{"error":"Configure sua chave de IA em Ajustes."}'; return }
      $in = (Read-Body $req) | ConvertFrom-Json
      $sel = [string]$in.text
      if ($sel.Length -lt 1 -or $sel.Length -gt 1500) { Send-Json $ctx 400 '{"error":"Trecho invalido (use ate 1500 caracteres)."}'; return }
      $cx = [string]$in.context
      if ($cx.Length -gt 3000) { $cx = $cx.Substring(0, 3000) }
      $bt = [string]$in.title
      $ba = [string]$in.author
      $sys = 'Você é um assistente de leitura que ajuda leitores brasileiros a entender trechos de livros. Explique o significado da palavra, expressão ou frase selecionada em português do Brasil, de forma clara e curta (no máximo 120 palavras). Se for uma palavra ou expressão, dê o sentido no contexto e, se for arcaica ou rara, o equivalente atual. Se o trecho estiver em outro idioma, traduza e explique. Se for uma frase, diga o que ela quer dizer e, se ajudar, o recurso literário usado. Não use títulos nem listas longas; pode usar **negrito** para destacar o termo principal.'
      $usr = 'Livro: ' + $bt + ' (' + $ba + ")`n`nParágrafo de contexto:`n" + $cx + "`n`nTrecho selecionado:`n" + $sel + "`n`nExplique o significado do trecho selecionado."
      if (-not $cfg.apiKey) {
        # IA do Paginas: o mesmo intermediario (Cloudflare) do Investe.AI; as chaves ficam so la
        $r = Invoke-Http 'POST' ($IA_PROXY_URL + '/chat') 'application/json' (Json-Bytes @{ sistema = $sys; mensagens = @(@{ role = 'user'; content = $usr }) }) @{ 'X-App-Token' = $IA_PROXY_TOKEN; 'X-App-Versao' = ('paginas-' + $APP_VERSAO) }
        $j = $null
        try { $j = $r.text | ConvertFrom-Json } catch { }
        if ($r.code -ne 200 -or -not $j -or -not $j.texto) {
          $m = 'A IA não respondeu agora. Tente de novo em instantes.'
          if ($j -and $j.erro) { $m = [string]$j.erro }
          Send-Json $ctx 502 (ConvertTo-Json -Compress -InputObject @{ error = $m })
          return
        }
        Send-Json $ctx 200 (ConvertTo-Json -Compress -InputObject @{ text = [string]$j.texto })
        return
      }
      $payload =ConvertTo-Json -Compress -Depth 6 -InputObject @{ model = 'claude-haiku-5-5'; max_tokens = 500; system = $sys; messages = @(@{ role = 'user'; content = $usr }) }
      $rq = [Net.HttpWebRequest]::Create('https://api.anthropic.com/v1/messages')
      $rq.Method = 'POST'
      $rq.ContentType = 'application/json'
      $rq.Timeout = 60000
      $rq.Headers.Add('x-api-key', $cfg.apiKey)
      $rq.Headers.Add('anthropic-version', '2023-06-01')
      $pb = [Text.Encoding]::UTF8.GetBytes($payload)
      $rq.ContentLength = $pb.Length
      $os = $rq.GetRequestStream()
      $os.Write($pb, 0, $pb.Length)
      $os.Close()
      try { $resp = $rq.GetResponse() }
      catch [Net.WebException] { $resp = $_.Exception.Response; if (-not $resp) { throw } }
      $rd = New-Object IO.StreamReader($resp.GetResponseStream(), [Text.Encoding]::UTF8)
      $raw = $rd.ReadToEnd()
      $rd.Close()
      $code = [int]$resp.StatusCode
      $resp.Close()
      $j = $raw | ConvertFrom-Json
      if ($code -ne 200) {
        $m = 'Erro ' + $code + ' ao falar com a IA.'
        if ($j.error.message) { $m = [string]$j.error.message }
        Send-Json $ctx 502 (ConvertTo-Json -Compress -InputObject @{ error = $m })
        return
      }
      $out = (@($j.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text })) -join "`n"
      Send-Json $ctx 200 (ConvertTo-Json -Compress -InputObject @{ text = $out })
    }
    else { Send-Json $ctx 404 '{"error":"nao encontrado"}' }
  }

  # ---- abre a janela do programa (sem barra de enderecos) ----
  $url = 'http://127.0.0.1:' + $port + '/'
  $cands = @()
  foreach ($base in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
    if ($base) { $cands += (Join-Path $base 'Microsoft\Edge\Application\msedge.exe') }
  }
  foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
    if ($base) { $cands += (Join-Path $base 'Google\Chrome\Application\chrome.exe') }
  }
  $exe = $cands | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
  $env:PAGINAS_PRONTO = '1'   # avisa o Paginas.exe que o programa abriu (fecha a janela "Abrindo o Paginas...")
  if ($env:PAGINAS_TESTE) {
    # teste automatico (GitHub Actions): sem janela; informa a porta e a senha da sessao
    [IO.File]::WriteAllText($env:PAGINAS_TESTE, ([string]$port + ' ' + $token))
  }
  elseif ($exe) {
    $prof = Join-Path $dir 'janela'
    $argList = @(('--app=' + $url), ('--user-data-dir="' + $prof + '"'), '--no-first-run', '--no-default-browser-check', '--window-size=1200,820')
    [void](Start-Process -FilePath $exe -ArgumentList $argList)
  } else {
    [void](Start-Process $url)
  }

  # ---- laco principal: atende a janela e encerra quando ela fecha ----
  $started = Get-Date
  $task = $listener.GetContextAsync()
  while ($true) {
    if ($task.Wait(60)) {
      $ctx = $task.Result
      $task = $listener.GetContextAsync()
      try { Handle-Request $ctx }
      catch {
        $msg = ConvertTo-Json -InputObject ([string]$_.Exception.Message)
        Send-Json $ctx 500 ('{"error":' + $msg + '}')
      }
    }
    $now = Get-Date
    if ($null -ne $S.byeAt -and ($now - $S.byeAt).TotalSeconds -gt 5 -and $S.lastPing -lt $S.byeAt) { break }
    if (-not $S.everPinged -and ($now - $started).TotalSeconds -gt 120) { break }
    if ($S.everPinged -and ($now - $S.lastPing).TotalSeconds -gt 600) { break }
    if ($null -ne $S.restart -and ($now - $S.restart).TotalSeconds -gt 1.5) { break }
  }
  $listener.Stop()
  $listener.Close()
  # guarda no Google Drive o que mudou desde a ultima copia
  if ($S.dirty -and (Get-Cfg).gRefresh) { try { Push-Drive } catch { } }
  # depois de atualizar: abre a versao nova
  if ($null -ne $S.restart) {
    try {
      $vbsNovo = Join-Path $dir 'abrir.vbs'
      if ($EXE) { [void](Start-Process -FilePath $EXE) }
      elseif (Test-Path -LiteralPath $vbsNovo) { [void](Start-Process -FilePath (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + $vbsNovo + '"')) }
      else { [void](Start-Process -FilePath (Join-Path $dir 'Paginas.bat')) }
    } catch { }
  }
} catch {
  try { [IO.File]::WriteAllText((Join-Path $dir 'erro.log'), ($_ | Out-String)) } catch { }
  [void][System.Windows.Forms.MessageBox]::Show('Erro no Paginas: ' + $_.Exception.Message, 'Paginas')
}
::HTML_START
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Páginas</title>
<link rel="icon" type="image/png" href="/api/icon?t=__TOKEN__">
<script>(function(){try{var t=localStorage.getItem('pg_tema')||'auto',d=t==='escuro'||(t==='auto'&&matchMedia('(prefers-color-scheme: dark)').matches);document.documentElement.classList.add(d?'escuro':'claro')}catch(e){}})()</script>
<style>
:root{
  color-scheme: light dark;
  --bg:#f6f1e7; --card:#fffdf8; --ink:#2a2420; --muted:#7a6f63; --line:#e6dccb;
  --accent:#b4532a; --accent-ink:#fff; --ok:#3f7d4e; --track:#eadfca; --warn:#c08a1e;
}
/* tema escuro: automático (segue o aparelho) ou escolhido em Ajustes > Aparência */
:root.escuro{ color-scheme: dark;
  --bg:#1b1815; --card:#25211d; --ink:#f0e8db; --muted:#a39886; --line:#383128;
    --accent:#e08a5c; --accent-ink:#1b1815; --ok:#7bc08a; --track:#383128; --warn:#e0b04a; }
:root.claro{ color-scheme: light }
*{box-sizing:border-box}
html,body{margin:0}
body{background:var(--bg);color:var(--ink);font:16px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;min-height:100vh}
h1,h2,h3{font-family:Georgia,"Times New Roman",serif;margin:0 0 .5rem;font-weight:700}
h2{font-size:1.2rem}
header{border-bottom:1px solid var(--line);background:var(--card);position:sticky;top:0;z-index:5}
.bar{max-width:980px;margin:0 auto;padding:.75rem 1rem;display:flex;align-items:center;gap:1rem;flex-wrap:wrap}
.brand{font:700 1.5rem Georgia,serif;color:var(--accent);margin-right:auto;letter-spacing:.2px}
nav{display:flex;gap:.25rem;flex-wrap:wrap}
.tab{background:none;border:0;color:var(--muted);font:inherit;font-weight:600;padding:.5rem .9rem;border-radius:999px;cursor:pointer}
.tab:hover{color:var(--ink)}
.tab.on{background:var(--accent);color:var(--accent-ink)}
main{max-width:980px;margin:0 auto;padding:1rem 1rem 4rem}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:1.1rem 1.2rem;margin-bottom:1rem}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:1rem}
.grid2 .card{margin-bottom:0}
.grid2{margin-bottom:1rem}
@media(max-width:700px){.grid2{grid-template-columns:1fr}}
.center{text-align:center}
.muted{color:var(--muted)} .small{font-size:.85rem}
.ringwrap{position:relative;width:170px;height:170px;margin:.25rem auto}
.ring{width:100%;height:100%}
.ring circle{fill:none;stroke-width:10}
.rt{stroke:var(--track)} .rp{stroke:var(--accent);stroke-linecap:round;transition:stroke-dashoffset .5s}
.ring.ok .rp{stroke:var(--ok)}
.ringtxt{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.ringtxt b{font:700 2.2rem Georgia,serif;line-height:1}
.ringtxt span{color:var(--muted);font-size:.85rem}
.msg{margin:.5rem 0 0}
.streakhead{display:flex;align-items:baseline;gap:.5rem}
.big{font:700 2.6rem Georgia,serif;color:var(--accent);line-height:1}
.week{display:grid;grid-template-columns:repeat(7,1fr);gap:.4rem;margin:.9rem 0 .6rem}
.day{text-align:center;font-size:.75rem;color:var(--muted)}
.dot{width:30px;height:30px;border-radius:50%;margin:.2rem auto 0;border:2px solid var(--line);display:flex;align-items:center;justify-content:center;font-size:.8rem}
.dot.done{background:var(--ok);border-color:var(--ok);color:#fff}
.dot.rest{background:var(--warn);border-color:var(--warn);color:#fff}
.dot.today{border-color:var(--accent)}
.row{display:flex;gap:.75rem;flex-wrap:wrap;align-items:flex-end}
label{display:flex;flex-direction:column;gap:.25rem;font-size:.85rem;color:var(--muted);font-weight:600;flex:1;min-width:120px}
input,select,textarea{font:inherit;color:var(--ink);background:var(--bg);border:1px solid var(--line);border-radius:10px;padding:.55rem .7rem;width:100%}
input:focus,select:focus,textarea:focus{outline:2px solid var(--accent);outline-offset:1px}
.btn{font:inherit;font-weight:600;border:1px solid var(--line);background:var(--card);color:var(--ink);padding:.55rem 1rem;border-radius:10px;cursor:pointer}
.btn:hover{border-color:var(--accent)}
.btn.primary{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.btn.danger{color:#c0392b}
.btn.sm{padding:.3rem .7rem;font-size:.85rem}
.chips{margin-top:.7rem;display:flex;gap:.4rem;align-items:center;flex-wrap:wrap;font-size:.85rem;color:var(--muted)}
.chip{border:1px solid var(--line);background:none;color:var(--ink);border-radius:999px;padding:.2rem .7rem;cursor:pointer;font:inherit;font-size:.85rem}
.chip:hover{border-color:var(--accent)}
.timer{display:flex;align-items:center;gap:1rem;flex-wrap:wrap}
.clock{font:700 2rem ui-monospace,Menlo,Consolas,monospace;margin-right:auto}
.log{display:flex;justify-content:space-between;gap:.5rem;padding:.5rem 0;border-top:1px solid var(--line);font-size:.92rem}
.log:first-of-type{border-top:0}
.x{background:none;border:0;color:var(--muted);cursor:pointer;font-size:1.1rem}
.x:hover{color:#c0392b}
.filters{display:flex;gap:.4rem;flex-wrap:wrap;margin-bottom:1rem;align-items:center}
.filters .btn.on{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.filters .spacer{margin-left:auto}
.book h3{margin:0}
.book .by{color:var(--muted);font-size:.9rem;margin-bottom:.6rem}
.prog{height:10px;background:var(--track);border-radius:99px;overflow:hidden}
.prog>i{display:block;height:100%;background:var(--accent);border-radius:99px;transition:width .4s}
.prog.ok>i{background:var(--ok)}
.bookmeta{display:flex;justify-content:space-between;font-size:.85rem;color:var(--muted);margin:.35rem 0 .7rem}
.bookact{display:flex;gap:.4rem;flex-wrap:wrap}
.note{font-style:italic;color:var(--muted);margin:.4rem 0 .7rem;font-size:.92rem}
.stars{color:var(--warn);letter-spacing:2px}
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:.8rem;margin-bottom:1rem}
.stat{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:.9rem 1rem}
.stat b{display:block;font:700 1.7rem Georgia,serif;color:var(--accent);line-height:1.1}
.stat span{font-size:.82rem;color:var(--muted)}
.chart{display:flex;align-items:flex-end;gap:3px;height:150px;position:relative;margin-top:.8rem;border-bottom:1px solid var(--line)}
.chart .b{flex:1;background:var(--track);border-radius:3px 3px 0 0;min-height:2px}
.chart .b.hit{background:var(--accent)}
.chart .goal{position:absolute;left:0;right:0;border-top:2px dashed var(--ok);opacity:.7}
.empty{text-align:center;color:var(--muted);padding:2rem 1rem}
dialog{border:1px solid var(--line);border-radius:18px;background:var(--card);color:var(--ink);padding:1.3rem;width:min(460px,92vw)}
dialog::backdrop{background:rgba(0,0,0,.45)}
dialog form{display:flex;flex-direction:column;gap:.8rem}
.actions{display:flex;gap:.5rem;justify-content:flex-end;margin-top:.3rem;flex-wrap:wrap}
.star{background:none;border:0;font-size:2rem;color:var(--track);cursor:pointer;padding:0 .1rem}
.star.on{color:var(--warn)}
#toast{position:fixed;left:50%;bottom:1.5rem;transform:translateX(-50%);background:var(--ink);color:var(--bg);padding:.6rem 1.1rem;border-radius:999px;opacity:0;pointer-events:none;transition:opacity .25s;z-index:20;max-width:90vw;text-align:center}
#toast.show{opacity:1}
.setgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:1rem}
[hidden]{display:none!important}
.tab{padding:.5rem .8rem}
.hello{margin:0 0 .8rem}
.cont{display:flex;align-items:center;justify-content:space-between;gap:1rem;flex-wrap:wrap}
.cont h3{margin:.1rem 0}
.gchips{display:flex;flex-wrap:wrap;gap:.4rem;margin-top:.8rem}
.gchip{border:1px solid var(--line);background:var(--card);color:var(--ink);border-radius:999px;padding:.4rem .9rem;font:inherit;font-size:.9rem;cursor:pointer}
.gchip:hover{border-color:var(--accent)}
.gchip.on{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.bgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:1rem;margin:.6rem 0 1.6rem}
.tile{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:.7rem;display:flex;flex-direction:column}
.cover{position:relative;aspect-ratio:2/3;border-radius:8px;overflow:hidden;margin-bottom:.55rem;background:linear-gradient(135deg,var(--accent),#6b3a2a);display:flex;align-items:center;justify-content:center;padding:.6rem;text-align:center;color:#fff;font:700 .85rem Georgia,serif;line-height:1.25}
.cover img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.tile .tt{font-weight:600;font-size:.9rem;line-height:1.25;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.tile .au{font-size:.8rem;color:var(--muted);margin:.15rem 0 .5rem}
.tile .tact{margin-top:auto;display:flex;gap:.3rem;flex-wrap:wrap}
.tag{display:inline-block;font-size:.7rem;font-weight:700;border:1px solid var(--line);border-radius:6px;padding:0 .35rem;color:var(--muted);margin-left:.3rem;vertical-align:middle}
.sechead{margin:1.2rem 0 0}
#onb{position:fixed;inset:0;z-index:60;background:var(--bg);overflow:auto;display:flex;align-items:center;justify-content:center;padding:1rem}
.onbbox{max-width:640px;width:100%;background:var(--card);border:1px solid var(--line);border-radius:20px;padding:2rem}
.onbbrand{font:700 1.4rem Georgia,serif;color:var(--accent);margin-bottom:.8rem}
.onbdots{display:flex;gap:.4rem;margin-bottom:1.2rem}
.onbdots i{width:28px;height:5px;border-radius:9px;background:var(--track)}
.onbdots i.on{background:var(--accent)}
.onbact{display:flex;justify-content:space-between;gap:.5rem;margin-top:1.5rem}
.reader{position:fixed;inset:0;z-index:40;display:flex;flex-direction:column;--rbg:#f4ecd8;--rink:#3b3226;--rmut:#8a7c66;--rline:#dccfb2;background:var(--rbg);color:var(--rink)}
.reader.th-light{--rbg:#ffffff;--rink:#222222;--rmut:#777777;--rline:#e5e5e5}
.reader.th-dark{--rbg:#121212;--rink:#d6d0c4;--rmut:#8b8579;--rline:#2c2c2c}
.rhead,.rfoot{display:flex;align-items:center;gap:.6rem;padding:.6rem 1rem}
.rhead{border-bottom:1px solid var(--rline)}
.rfoot{border-top:1px solid var(--rline)}
.rtitle{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-weight:600}
.reader .btn{background:transparent;color:var(--rink);border-color:var(--rline)}
.reader .btn.primary{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.reader .btn:disabled{opacity:.4;cursor:default}
.rbody{flex:1;overflow:auto;padding:2rem 1rem}
.rbody article{max-width:680px;margin:0 auto;font-family:Georgia,"Times New Roman",serif;line-height:1.8}
.rbody p{margin:0 0 1em;white-space:pre-line;text-align:left;hyphens:auto}
.rbody h4{text-align:center;margin:1.6em 0 1em;letter-spacing:.05em;font-family:Georgia,serif}
.rmsg{max-width:520px;margin:4rem auto;text-align:center}
.rfoot input[type=range]{flex:1;padding:0;border:0;background:transparent;accent-color:var(--accent)}
.rinfo{font-size:.85rem;color:var(--rmut);min-width:170px;text-align:center}
@media(max-width:600px){.rinfo{min-width:0;font-size:.75rem}.rhead .btn.sm{padding:.3rem .5rem}}
</style>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Lora:ital,wght@0,400;0,600;0,700;1,400&family=Nunito:wght@400;600;700;800&display=swap" rel="stylesheet">
<style>
html{background:#f6f1e7}
html.escuro{background:#1b1815}
#splash{position:fixed;inset:0;z-index:100;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:.9rem;background:#f6f1e7;color:#7a6f63;transition:opacity .5s ease,visibility .5s}
#splash.out{opacity:0;visibility:hidden}
#splash svg{width:104px;height:104px;filter:drop-shadow(0 14px 18px rgba(120,60,25,.35));animation:spfloat 2.4s ease-in-out infinite}
#splash b{font:700 2rem Lora,Georgia,serif;color:#b4532a}
#splash span{font:600 .95rem Nunito,system-ui,sans-serif}
#splash i{display:block;width:180px;height:5px;border-radius:9px;background:#eadfca;overflow:hidden}
#splash i::after{content:'';display:block;width:40%;height:100%;border-radius:9px;background:linear-gradient(90deg,#b4532a,#e08a5c);animation:spbar 1.2s ease-in-out infinite}
@keyframes spbar{0%{transform:translateX(-110%)}100%{transform:translateX(260%)}}
@keyframes spfloat{50%{transform:translateY(-6px)}}
.escuro #splash{background:#1b1815;color:#a39886}.escuro #splash b{color:#e08a5c}.escuro #splash i{background:#383128}
</style>
</head>
<body>
<div id="splash"><svg viewBox="0 0 100 100" aria-hidden="true"><defs><linearGradient id="spg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#e08a5c"/><stop offset="1" stop-color="#a0401e"/></linearGradient></defs><rect width="100" height="100" rx="22" fill="url(#spg)"/><polygon points="16,34 48,43 48,80 16,71" fill="#fffcf6"/><polygon points="52,43 84,34 84,71 52,80" fill="#f6e8d4"/><g stroke="#b4532a" stroke-opacity=".6" stroke-width="1.8" stroke-linecap="round"><path d="M22 50L43 55M22 58L43 63M57 55L78 50M57 63L78 58"/></g></svg><b>Páginas</b><i></i><span>Abrindo sua biblioteca...</span></div>
<header>
  <div class="bar">
    <div class="brand">Páginas</div>
    <nav>
      <button class="tab" data-v="today" data-a="nav">Hoje</button>
      <button class="tab" data-v="foryou" data-a="nav">Para você</button>
      <button class="tab" data-v="social" data-a="nav">Comunidade</button>
      <button class="tab" data-v="library" data-a="nav">Pesquisar</button>
      <button class="tab" data-v="brasil" data-a="nav">Brasil</button>
      <button class="tab" data-v="shelf" data-a="nav">Estante</button>
      <button class="tab" data-v="stats" data-a="nav">Estatísticas</button>
      <button class="tab" data-v="settings" data-a="nav">Ajustes</button>
    </nav>
  </div>
</header>
<main id="main"></main>
<dialog id="dlg"></dialog>
<div id="reader" class="reader" hidden></div>
<div id="onb" hidden></div>
<div id="toast" role="status"></div>
<noscript>Este aplicativo precisa de JavaScript ativado.</noscript>

<script>
/* ============ Utilidades de data e texto ============ */
const $ = s => document.querySelector(s);
const pad = n => String(n).padStart(2, '0');
const fmt = d => `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
const todayStr = () => fmt(new Date());
const parseD = s => { const [y,m,d] = s.split('-').map(Number); return new Date(y, m-1, d); };
const addDays = (s, n) => { const d = parseD(s); d.setDate(d.getDate()+n); return fmt(d); };
const weekStart = s => addDays(s, -((parseD(s).getDay()+6) % 7));
const brDate = s => { const [y,m,d] = s.split('-'); return `${d}/${m}`; };
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2,6);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

/* ============ Armazenamento (camada isolada: no celular basta trocar esta parte) ============ */
const KEY = 'paginas.v1';
const defaults = () => ({
  version: 1,
  settings: { goalType: 'minutes', dailyGoal: 15, yearGoal: 12, reminder: '', restPerWeek: 1 },
  books: [], logs: [], rests: [], profile: null, prefs: { size: 19, theme: 'sepia' }
});
const Store = {
  load() {
    try {
      const raw = localStorage.getItem(KEY);
      if (raw) {
        const p = JSON.parse(raw), d = defaults();
        return { ...d, ...p, settings: { ...d.settings, ...(p.settings || {}) } };
      }
    } catch (e) {}
    return defaults();
  },
  save(s) { try { localStorage.setItem(KEY, JSON.stringify(s)); return true; } catch (e) { return false; } }
};

/* ============ Estado ============ */
let state = Store.load();
let view = 'today';
let shelfFilter = 'reading';
let draft = { bookId: '', pages: '', minutes: '' };
let fin = null;
let _map = null;
let lastNotified = '';

function commit() {
  const ok = Store.save(state);
  _map = null;
  if (!ok) toast('Não foi possível salvar neste navegador.');
  render();
}

/* ============ Cálculos ============ */
function dayMap() {
  if (!_map) {
    _map = {};
    for (const l of state.logs) {
      const o = _map[l.date] || (_map[l.date] = { pages: 0, minutes: 0 });
      o.pages += l.pages; o.minutes += l.minutes;
    }
  }
  return _map;
}
const totalsFor = d => dayMap()[d] || { pages: 0, minutes: 0 };
const goalVal = d => totalsFor(d)[state.settings.goalType];
const goalMet = d => goalVal(d) >= state.settings.dailyGoal;
const isRest = d => state.rests.includes(d);
const isDone = d => goalMet(d) || isRest(d);
const unitLabel = () => state.settings.goalType === 'minutes' ? 'min' : 'págs';

function computeStreak() {
  const t = todayStr();
  let d = isDone(t) ? t : addDays(t, -1);
  let n = 0;
  while (isDone(d)) { n++; d = addDays(d, -1); }
  return n;
}
function bestStreak() {
  const dates = [...Object.keys(dayMap()), ...state.rests].sort();
  if (!dates.length) return 0;
  const t = todayStr();
  let d = dates[0], best = 0, cur = 0;
  while (d <= t) {
    if (isDone(d)) { cur++; best = Math.max(best, cur); }
    else if (d !== t) cur = 0;
    d = addDays(d, 1);
  }
  return best;
}
function restsThisWeek() {
  const ws = weekStart(todayStr()), we = addDays(ws, 6);
  return state.rests.filter(r => r >= ws && r <= we).length;
}

/* ============ Ações de dados ============ */
function addLog() {
  const b = state.books.find(x => x.id === draft.bookId);
  const pages = Math.max(0, parseInt(draft.pages) || 0);
  const minutes = Math.max(0, parseInt(draft.minutes) || 0);
  if (!b) return toast('Escolha um livro.');
  if (!pages && !minutes) return toast('Informe páginas ou minutos.');
  let applied = 0;
  if (pages) {
    const np = Math.min(b.totalPages, b.currentPage + pages);
    applied = np - b.currentPage; b.currentPage = np;
  }
  const wasMet = goalMet(todayStr());
  state.logs.push({ id: uid(), date: todayStr(), ts: Date.now(), bookId: b.id, pages: applied, minutes });
  _map = null;
  draft.pages = ''; draft.minutes = '';
  let finished = false;
  if (b.currentPage >= b.totalPages && b.status !== 'finished') {
    b.status = 'finished'; b.finishedAt = todayStr(); finished = true;
  }
  commit();
  if (finished) { toast('Livro concluído! 🎉'); openFinish(b.id); }
  else if (!wasMet && goalMet(todayStr())) toast('Meta de hoje concluída! 🔥');
}
function deleteLog(id) {
  const l = state.logs.find(x => x.id === id); if (!l) return;
  const b = state.books.find(x => x.id === l.bookId);
  if (b) {
    b.currentPage = Math.max(0, b.currentPage - l.pages);
    if (b.status === 'finished' && b.currentPage < b.totalPages) { b.status = 'reading'; b.finishedAt = null; }
  }
  state.logs = state.logs.filter(x => x.id !== id);
  commit();
}
function startBook(id) { const b = state.books.find(x => x.id === id); if (b) { b.status = 'reading'; commit(); } }
function finishBook(id) {
  const b = state.books.find(x => x.id === id); if (!b) return;
  b.status = 'finished'; b.currentPage = b.totalPages; b.finishedAt = b.finishedAt || todayStr();
  commit(); openFinish(id);
}
function deleteBook(id) {
  const b = state.books.find(x => x.id === id); if (!b) return;
  if (!confirm(`Excluir "${b.title}" e o histórico de leitura dele?`)) return;
  state.books = state.books.filter(x => x.id !== id);
  state.logs = state.logs.filter(l => l.bookId !== id);
  commit();
}

/* ============ Cronômetro ============ */
const TKEY = 'paginas.timer';
let timer = (() => { try { return JSON.parse(localStorage.getItem(TKEY)) || null; } catch (e) { return null; } })() || { running: false, startedAt: 0, acc: 0 };
const saveTimer = () => { try { localStorage.setItem(TKEY, JSON.stringify(timer)); } catch (e) {} };
const elapsed = () => timer.acc + (timer.running ? Date.now() - timer.startedAt : 0);
const clock = ms => { const s = Math.floor(ms/1000); return `${pad(Math.floor(s/3600))}:${pad(Math.floor(s%3600/60))}:${pad(s%60)}`; };
setInterval(() => { const el = $('#timerDisplay'); if (el) el.textContent = clock(elapsed()); }, 500);

/* ============ Lembrete ============ */
function notify() {
  const msg = 'Hora de ler! Alguns minutos já mantêm sua sequência.';
  if ('Notification' in window && Notification.permission === 'granted') {
    try { new Notification('Páginas 📖', { body: msg }); return; } catch (e) {}
  }
  toast(msg);
}
setInterval(() => {
  const t = state.settings.reminder; if (!t) return;
  const n = new Date();
  if (`${pad(n.getHours())}:${pad(n.getMinutes())}` === t && lastNotified !== todayStr() && !isDone(todayStr())) {
    lastNotified = todayStr(); notify();
  }
}, 20000);

/* ============ Telas ============ */
function render() {
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('on', t.dataset.v === view));
  $('#main').innerHTML = (VIEWS[view] || VIEWS.today)();
}

function ring(pct, ok) {
  const c = 2 * Math.PI * 52;
  return `<svg viewBox="0 0 120 120" class="ring ${ok ? 'ok' : ''}"><circle cx="60" cy="60" r="52" class="rt"/><circle cx="60" cy="60" r="52" class="rp" stroke-dasharray="${c}" stroke-dashoffset="${c * (1 - Math.min(1, pct))}" transform="rotate(-90 60 60)"/></svg>`;
}

function renderToday() {
  const s = state.settings, t = todayStr(), val = goalVal(t), unit = unitLabel();
  const met = goalMet(t), rest = isRest(t);
  const reading = state.books.filter(b => b.status === 'reading');
  if (!reading.find(b => b.id === draft.bookId)) draft.bookId = reading[0] ? reading[0].id : '';
  const streak = computeStreak(), best = bestStreak(), used = restsThisWeek();
  const dayNames = ['S','T','Q','Q','S','S','D'];
  const ws = weekStart(t);
  const dots = dayNames.map((n, i) => {
    const d = addDays(ws, i);
    let cls = '', mark = '';
    if (goalMet(d)) { cls = 'done'; mark = '✓'; }
    else if (isRest(d)) { cls = 'rest'; mark = '☾'; }
    if (d === t) cls += ' today';
    return `<div class="day">${n}<div class="dot ${cls}">${mark}</div></div>`;
  }).join('');
  const msg = met ? 'Meta de hoje concluída. Bom trabalho!'
    : rest ? 'Hoje é seu dia de descanso. A sequência está protegida.'
    : `Faltam ${Math.max(0, s.dailyGoal - val)} ${unit} para a meta de hoje.`;
  const canRest = !met && !rest && used < s.restPerWeek;
  const recent = [...state.logs].sort((a, b) => b.ts - a.ts).slice(0, 6);
  const bookName = id => { const b = state.books.find(x => x.id === id); return b ? b.title : 'Livro removido'; };

  const running = timer.running, hasTime = elapsed() > 0;
  return `
  <p class="muted" style="margin:.2rem 0 1rem">${new Date().toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long' })}</p>
  ${continueCard()}
  <div class="grid2">
    <section class="card center">
      <div class="ringwrap">${ring(val / s.dailyGoal, met)}<div class="ringtxt"><b>${val}</b><span>de ${s.dailyGoal} ${unit}</span></div></div>
      <p class="msg">${msg}</p>
    </section>
    <section class="card">
      <div class="streakhead"><span class="big">${streak}</span><span>${streak === 1 ? 'dia seguido' : 'dias seguidos'}</span></div>
      <div class="week">${dots}</div>
      <p class="muted small" style="margin:0">Melhor sequência: ${best} · Descansos nesta semana: ${used}/${s.restPerWeek}</p>
      ${canRest ? `<button class="btn sm" style="margin-top:.7rem" data-a="rest">Usar dia de descanso hoje</button>` : ''}
    </section>
  </div>

  <section class="card">
    <h2>Registrar leitura</h2>
    ${reading.length ? `
    <form id="logForm" class="row">
      <label>Livro<select data-draft="bookId">${reading.map(b => `<option value="${b.id}" ${b.id === draft.bookId ? 'selected' : ''}>${esc(b.title)}</option>`).join('')}</select></label>
      <label>Páginas lidas<input id="fPages" type="number" min="0" inputmode="numeric" data-draft="pages" value="${esc(draft.pages)}"></label>
      <label>Minutos<input id="fMin" type="number" min="0" inputmode="numeric" data-draft="minutes" value="${esc(draft.minutes)}"></label>
      <button class="btn primary" type="submit">Registrar</button>
    </form>
    <div class="chips">Atalhos de tempo:
      ${[5, 10, 15, 30].map(m => `<button type="button" class="chip" data-a="qmin" data-v="${m}">${m} min</button>`).join('')}
    </div>` : `
    <p class="muted">Você não tem nenhum livro em andamento.</p>
    <button class="btn primary" data-a="goAdd">Adicionar um livro</button>`}
  </section>

  <section class="card">
    <h2>Cronômetro de leitura</h2>
    <div class="timer">
      <div class="clock" id="timerDisplay">${clock(elapsed())}</div>
      ${running ? `<button class="btn" data-a="tpause">Pausar</button>` : `<button class="btn primary" data-a="tstart">${hasTime ? 'Continuar' : 'Iniciar'}</button>`}
      ${hasTime ? `<button class="btn" data-a="tfinish">Finalizar e registrar</button><button class="btn sm" data-a="treset">Zerar</button>` : ''}
    </div>
  </section>

  ${recent.length ? `<section class="card"><h2>Últimos registros</h2>
    ${recent.map(l => `<div class="log"><span>${l.date === t ? 'Hoje' : brDate(l.date)} · ${esc(bookName(l.bookId))} · ${l.pages ? l.pages + ' págs' : ''}${l.pages && l.minutes ? ' · ' : ''}${l.minutes ? l.minutes + ' min' : ''}</span><button class="x" title="Remover" data-a="dellog" data-id="${l.id}">×</button></div>`).join('')}
  </section>` : ''}`;
}

function stars(n) { return '★'.repeat(n) + '☆'.repeat(5 - n); }

function bookCard(b) {
  const pct = b.totalPages ? Math.round(b.currentPage / b.totalPages * 100) : 0;
  let act = '';
  if (b.status === 'reading') act = `<button class="btn sm" data-a="finishbook" data-id="${b.id}">Concluir</button>`;
  if (b.status === 'want') act = `<button class="btn sm primary" data-a="startbook" data-id="${b.id}">Começar a ler</button>`;
  if (b.status === 'finished') act = `<button class="btn sm" data-a="review" data-id="${b.id}">${b.rating || b.note ? 'Editar resenha' : 'Escrever resenha'}</button>`;
  return `<article class="card book">
    <h3>${esc(b.title)}</h3>
    <div class="by">${esc(b.author || 'Autor não informado')}${b.status === 'finished' && b.finishedAt ? ' · concluído em ' + brDate(b.finishedAt) : ''}</div>
    ${b.status !== 'want' ? `<div class="prog ${b.status === 'finished' ? 'ok' : ''}"><i style="width:${pct}%"></i></div>
    <div class="bookmeta"><span>p. ${b.currentPage} de ${b.totalPages}</span><span>${pct}%</span></div>` : `<div class="bookmeta"><span>${b.totalPages ? b.totalPages + ' páginas' : 'Biblioteca virtual'}</span></div>`}
    ${b.status === 'finished' && b.rating ? `<div class="stars">${stars(b.rating)}</div>` : ''}
    ${b.status === 'finished' && b.note ? `<p class="note">“${esc(b.note)}”</p>` : ''}
    <div class="bookact">${b.gid ? `<button class="btn sm primary" data-x="read" data-id="${b.id}">${b.status === 'finished' ? 'Reler' : (b.currentPage > 0 ? 'Continuar lendo' : 'Ler agora')}</button>` : ''}${act}${b.gid ? '' : `<button class="btn sm" data-a="editbook" data-id="${b.id}">Editar</button>`}<button class="btn sm danger" data-a="delbook" data-id="${b.id}">Excluir</button></div>
  </article>`;
}

function renderShelf() {
  const cnt = st => state.books.filter(b => b.status === st).length;
  const filters = [['reading', 'Lendo', cnt('reading')], ['want', 'Quero ler', cnt('want')], ['finished', 'Concluídos', cnt('finished')], ['all', 'Todos', state.books.length]];
  const list = state.books.filter(b => shelfFilter === 'all' || b.status === shelfFilter)
    .sort((a, b) => (b.addedAt || '').localeCompare(a.addedAt || ''));
  return `
  <div class="filters">
    ${filters.map(([k, l, n]) => `<button class="btn ${shelfFilter === k ? 'on' : ''}" data-a="filter" data-v="${k}">${l} (${n})</button>`).join('')}
    <button class="btn primary spacer" data-a="goAdd">+ Novo livro</button>
  </div>
  ${list.length ? list.map(bookCard).join('') : `<div class="card empty">Nada por aqui ainda.<br>Adicione um livro para começar a acompanhar seu progresso.</div>`}`;
}

function renderStats() {
  const s = state.settings, t = todayStr(), unit = unitLabel();
  const logs = state.logs;
  const totPages = logs.reduce((a, l) => a + l.pages, 0);
  const totMin = logs.reduce((a, l) => a + l.minutes, 0);
  const year = String(new Date().getFullYear());
  const doneYear = state.books.filter(b => b.status === 'finished' && (b.finishedAt || '').startsWith(year)).length;
  const month = t.slice(0, 7);
  const mDays = Object.keys(dayMap()).filter(d => d.startsWith(month) && (dayMap()[d].pages || dayMap()[d].minutes)).length;
  const mPages = logs.filter(l => l.date.startsWith(month)).reduce((a, l) => a + l.pages, 0);
  const mMin = logs.filter(l => l.date.startsWith(month)).reduce((a, l) => a + l.minutes, 0);
  const hm = m => m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}min` : `${m} min`;
  const days = []; for (let i = 29; i >= 0; i--) days.push(addDays(t, -i));
  const vals = days.map(goalVal);
  const max = Math.max(s.dailyGoal, ...vals, 1);
  const ypct = s.yearGoal ? Math.min(100, Math.round(doneYear / s.yearGoal * 100)) : 0;
  return `
  <div class="cards">
    <div class="stat"><b>${computeStreak()}</b><span>sequência atual (dias)</span></div>
    <div class="stat"><b>${bestStreak()}</b><span>melhor sequência</span></div>
    <div class="stat"><b>${state.books.filter(b => b.status === 'finished').length}</b><span>livros concluídos</span></div>
    <div class="stat"><b>${totPages}</b><span>páginas lidas</span></div>
    <div class="stat"><b>${hm(totMin)}</b><span>tempo de leitura</span></div>
  </div>
  <section class="card">
    <h2>Meta do ano: ${doneYear} de ${s.yearGoal} livros</h2>
    <div class="prog ${ypct >= 100 ? 'ok' : ''}"><i style="width:${ypct}%"></i></div>
  </section>
  <section class="card">
    <h2>Este mês</h2>
    <p style="margin:0">${mDays} dias com leitura · ${mPages} páginas · ${hm(mMin)}</p>
  </section>
  <section class="card">
    <h2>Últimos 30 dias (${unit})</h2>
    <p class="muted small" style="margin:0">Barras laranjas bateram a meta. A linha tracejada é a meta diária.</p>
    <div class="chart">
      <div class="goal" style="bottom:${s.dailyGoal / max * 100}%"></div>
      ${vals.map((v, i) => `<div class="b ${v >= s.dailyGoal ? 'hit' : ''}" style="height:${v / max * 100}%" title="${brDate(days[i])}: ${v} ${unit}"></div>`).join('')}
    </div>
  </section>`;
}

function renderSettings() {
  const s = state.settings;
  return `
  <section class="card">
    <h2>Metas e hábito</h2>
    <div class="setgrid">
      <label>Meta diária medida em<select data-set="goalType"><option value="minutes" ${s.goalType === 'minutes' ? 'selected' : ''}>Minutos</option><option value="pages" ${s.goalType === 'pages' ? 'selected' : ''}>Páginas</option></select></label>
      <label>Meta diária (${unitLabel()})<input type="number" min="1" data-set="dailyGoal" value="${s.dailyGoal}"></label>
      <label>Meta anual (livros)<input type="number" min="0" data-set="yearGoal" value="${s.yearGoal}"></label>
      <label>Dias de descanso por semana<input type="number" min="0" max="3" data-set="restPerWeek" value="${s.restPerWeek}"></label>
      <label>Lembrete diário<input type="time" data-set="reminder" value="${esc(s.reminder)}"></label>
    </div>
    <p class="muted small">Dica: comece com uma meta pequena (10 a 15 minutos). Constância vale mais que volume. O lembrete só dispara com o programa aberto.</p>
  </section>
  <section class="card">
    <h2>Seus dados</h2>
    <p class="muted small">Seus dados e os livros baixados ficam salvos neste computador (pasta Paginas em AppData). Faça um backup de vez em quando.</p>
    <div class="bookact">
      <button class="btn" data-a="export">Exportar backup</button>
      <label class="btn" style="flex:none;min-width:0;flex-direction:row;color:var(--ink);font-size:1rem;cursor:pointer">Importar backup<input id="importFile" type="file" accept="application/json" hidden></label>
      <button class="btn danger" data-a="wipe">Apagar tudo</button>
    </div>
  </section>`;
}

/* ============ Diálogos ============ */
const dlg = $('#dlg');
function openBook(id) {
  const b = id ? state.books.find(x => x.id === id) : null;
  dlg.innerHTML = `<form id="bookForm" data-id="${id || ''}">
    <h2>${b ? 'Editar livro' : 'Novo livro'}</h2>
    <label>Título<input name="title" required maxlength="120" value="${esc(b && b.title)}"></label>
    <label>Autor<input name="author" maxlength="80" value="${esc(b && b.author)}"></label>
    <label>Total de páginas<input name="total" type="number" min="1" required value="${b ? b.totalPages : ''}"></label>
    <label>Situação<select name="status"><option value="reading">Lendo</option><option value="want">Quero ler</option><option value="finished">Concluído</option></select></label>
    ${b ? `<label>Página atual<input name="current" type="number" min="0" value="${b.currentPage}"></label>` : ''}
    <div class="actions"><button type="button" class="btn" data-a="closeDlg">Cancelar</button><button class="btn primary" type="submit">Salvar</button></div>
  </form>`;
  dlg.querySelector('[name=status]').value = b ? b.status : 'reading';
  dlg.showModal();
}
function saveBook(f) {
  const id = f.dataset.id, fd = new FormData(f);
  const title = String(fd.get('title')).trim(); if (!title) return;
  const total = Math.max(1, parseInt(fd.get('total')) || 1);
  const status = fd.get('status');
  let openRev = null;
  if (id) {
    const b = state.books.find(x => x.id === id);
    const wasFinished = b.status === 'finished';
    b.title = title; b.author = String(fd.get('author')).trim(); b.totalPages = total;
    let cur = Math.min(total, Math.max(0, parseInt(fd.get('current')) || 0));
    b.status = status;
    if (status === 'finished') { cur = total; b.finishedAt = b.finishedAt || todayStr(); if (!wasFinished) openRev = b.id; }
    else { b.finishedAt = null; if (cur >= total) { b.status = 'finished'; b.finishedAt = todayStr(); openRev = b.id; } }
    if (status === 'want') cur = 0;
    b.currentPage = cur;
  } else {
    state.books.push({ id: uid(), title, author: String(fd.get('author')).trim(), totalPages: total,
      currentPage: status === 'finished' ? total : 0, status, addedAt: new Date().toISOString(),
      finishedAt: status === 'finished' ? todayStr() : null, rating: 0, note: '' });
    shelfFilter = status;
  }
  dlg.close(); commit();
  if (openRev) openFinish(openRev);
}
function openFinish(id) {
  const b = state.books.find(x => x.id === id); if (!b) return;
  fin = { id, rating: b.rating || 0, note: b.note || '' };
  renderFinish(); dlg.showModal();
}
function renderFinish() {
  const b = state.books.find(x => x.id === fin.id);
  dlg.innerHTML = `<form id="finForm">
    <h2>Resenha de “${esc(b.title)}”</h2>
    <div>${[1,2,3,4,5].map(n => `<button type="button" class="star ${n <= fin.rating ? 'on' : ''}" data-a="rate" data-v="${n}" aria-label="${n} estrelas">★</button>`).join('')}</div>
    <label>O que você achou? (opcional)<textarea name="note" rows="4" maxlength="500">${esc(fin.note)}</textarea></label>
    <div class="actions"><button type="button" class="btn" data-a="closeDlg">Pular</button><button class="btn primary" type="submit">Salvar</button></div>
  </form>`;
}

/* ============ Backup ============ */
function exportData() {
  const blob = new Blob([JSON.stringify(state, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob); a.download = `paginas-backup-${todayStr()}.json`;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
function importData(file) {
  const r = new FileReader();
  r.onload = () => {
    try {
      const p = JSON.parse(r.result);
      if (!p || !Array.isArray(p.books) || !Array.isArray(p.logs)) throw new Error('formato');
      if (!confirm('Isso vai substituir os dados atuais pelos do backup. Continuar?')) return;
      const d = defaults();
      state = { ...d, ...p, settings: { ...d.settings, ...(p.settings || {}) }, rests: Array.isArray(p.rests) ? p.rests : [] };
      commit(); toast('Backup importado.');
    } catch (e) { toast('Arquivo inválido.'); }
  };
  r.readAsText(file);
}

/* ============ Toast ============ */
let toastT;
function toast(msg) {
  const el = $('#toast'); el.textContent = msg; el.classList.add('show');
  clearTimeout(toastT); toastT = setTimeout(() => el.classList.remove('show'), 3200);
}

/* ============ Eventos ============ */
document.addEventListener('click', e => {
  const el = e.target.closest('[data-a]'); if (!el) return;
  const a = el.dataset.a, id = el.dataset.id, v = el.dataset.v;
  switch (a) {
    case 'nav': view = v; render(); window.scrollTo(0, 0); break;
    case 'filter': shelfFilter = v; render(); break;
    case 'goAdd': view = 'shelf'; render(); openBook(); break;
    case 'editbook': openBook(id); break;
    case 'delbook': deleteBook(id); break;
    case 'startbook': startBook(id); break;
    case 'finishbook': finishBook(id); break;
    case 'review': openFinish(id); break;
    case 'dellog': deleteLog(id); break;
    case 'qmin': draft.minutes = v; render(); break;
    case 'rest': state.rests.push(todayStr()); commit(); toast('Dia de descanso registrado.'); break;
    case 'closeDlg': dlg.close(); break;
    case 'rate': {
      const ta = dlg.querySelector('textarea'); if (ta) fin.note = ta.value;
      fin.rating = fin.rating === Number(v) ? 0 : Number(v); renderFinish(); break;
    }
    case 'tstart': timer.running = true; timer.startedAt = Date.now(); saveTimer(); render(); break;
    case 'tpause': timer.acc = elapsed(); timer.running = false; saveTimer(); render(); break;
    case 'treset': timer = { running: false, startedAt: 0, acc: 0 }; saveTimer(); render(); break;
    case 'tfinish': {
      draft.minutes = String(Math.max(1, Math.round(elapsed() / 60000)));
      timer = { running: false, startedAt: 0, acc: 0 }; saveTimer(); render();
      const p = $('#fPages'); if (p) p.focus();
      break;
    }
    case 'export': exportData(); break;
    case 'wipe':
      if (confirm('Apagar todos os livros, registros e configurações? Isso não pode ser desfeito.')) {
        state = defaults(); draft = { bookId: '', pages: '', minutes: '' }; commit(); toast('Dados apagados.');
      }
      break;
  }
});
document.addEventListener('input', e => {
  const k = e.target.dataset && e.target.dataset.draft;
  if (k) draft[k] = e.target.value;
});
document.addEventListener('change', e => {
  const t = e.target;
  if (t.dataset.draft) draft[t.dataset.draft] = t.value;
  if (t.dataset.set) {
    const k = t.dataset.set; let v = t.value;
    if (['dailyGoal', 'yearGoal', 'restPerWeek'].includes(k)) {
      v = Math.max(k === 'dailyGoal' ? 1 : 0, parseInt(v) || 0);
      if (k === 'restPerWeek') v = Math.min(3, v);
    }
    state.settings[k] = v;
    if (k === 'reminder' && v && 'Notification' in window && Notification.permission === 'default') Notification.requestPermission();
    commit();
  }
  if (t.id === 'importFile' && t.files[0]) importData(t.files[0]);
});
document.addEventListener('submit', e => {
  e.preventDefault();
  const f = e.target;
  if (f.id === 'logForm') addLog();
  else if (f.id === 'bookForm') saveBook(f);
  else if (f.id === 'finForm') {
    const b = state.books.find(x => x.id === fin.id);
    if (b) { b.rating = fin.rating; b.note = f.querySelector('textarea').value.trim(); }
    dlg.close(); commit(); toast('Resenha salva.');
  }
});

</script>
<script>
/* ====================================================================
   PARTE 2: programa em janela, biblioteca virtual, gostos, recomendações e leitor
   ==================================================================== */
const API = { token: '__TOKEN__' };
const APP = { versao: '__VERSAO__', repo: '__REPO__', plat: '__PLAT__' };
if (APP.repo.charAt(0) === '_') APP.repo = '';
const IS_APP = /^https?:$/.test(location.protocol) && API.token.charAt(0) !== '_';
let loadFailed = false, saveT = null, pendingSave = null;

async function api(path, opts) {
  if (!IS_APP) throw new Error('A biblioteca só funciona dentro do programa Paginas.bat (e precisa de internet para baixar livros novos).');
  const url = path + (path.includes('?') ? '&' : '?') + 't=' + API.token;
  let r;
  try { r = await fetch(url, opts || {}); }
  catch (e) { throw new Error('O programa parou de responder. Feche e abra de novo.'); }
  if (!r.ok) {
    let m = '';
    try { m = (await r.json()).error; } catch (e) {}
    throw new Error(m || ('Erro ' + r.status + ' (sem internet ou serviço fora do ar?)'));
  }
  return r;
}

/* ---------- salvamento em disco ---------- */
function diskSave(s) { if (loadFailed) return; pendingSave = s; clearTimeout(saveT); saveT = setTimeout(flushSave, 400); }
function flushSave() {
  clearTimeout(saveT);
  if (!pendingSave || !IS_APP) return Promise.resolve();
  const body = JSON.stringify(pendingSave); pendingSave = null;
  return api('/api/save', { method: 'POST', body, keepalive: body.length < 60000 })
    .catch(e => toast('Não consegui salvar no disco: ' + e.message));
}
const _origSave = Store.save;
Store.save = function (s) {
  const quiet = !!(window.Sync && Sync.quiet);
  if (IS_APP && !quiet) s.mod = Date.now();  // hora da última mudança (sincronização com a conta Google)
  const ok = _origSave.call(Store, s);
  if (IS_APP) { diskSave(s); if (window.Sync && !quiet) Sync.later(); return true; }
  return ok;
};

/* ---------- gostos ---------- */
const GENRES = [
  { id: 'romance', label: 'Romance', topic: 'love stories' },
  { id: 'adventure', label: 'Aventura', topic: 'adventure' },
  { id: 'mystery', label: 'Mistério e policial', topic: 'detective' },
  { id: 'scifi', label: 'Ficção científica', topic: 'science fiction' },
  { id: 'fantasy', label: 'Fantasia', topic: 'fantasy' },
  { id: 'horror', label: 'Terror e gótico', topic: 'horror' },
  { id: 'classics', label: 'Clássicos mais lidos', topic: '' },
  { id: 'philosophy', label: 'Filosofia', topic: 'philosophy' },
  { id: 'history', label: 'História', topic: 'history' },
  { id: 'poetry', label: 'Poesia', topic: 'poetry' },
  { id: 'drama', label: 'Teatro', topic: 'drama' },
  { id: 'humor', label: 'Humor e sátira', topic: 'humor' },
  { id: 'children', label: 'Infantil e juvenil', topic: 'children' },
  { id: 'biography', label: 'Biografias', topic: 'biography' },
  { id: 'science', label: 'Ciência e natureza', topic: 'science' }
];
const LANGS = [
  { id: 'pt', label: 'Português' }, { id: 'en', label: 'English' },
  { id: 'es', label: 'Español' }, { id: 'fr', label: 'Français' }
];
const genreLabel = id => (GENRES.find(g => g.id === id) || {}).label;
const userLangs = () => (state.profile && state.profile.langs && state.profile.langs.length) ? state.profile.langs : ['pt'];
const shuffle = a => { a = a.slice(); for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(Math.random() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

/* ---------- catálogo (Projeto Gutenberg via Gutendex) ---------- */
const GCACHE = {};
function niceAuthor(n) {
  if (!n) return 'Autor desconhecido';
  const p = n.split(', ');
  return p.length >= 2 ? (p.slice(1).join(' ') + ' ' + p[0]).trim() : n;
}
function normBook(g) {
  const f = g.formats || {};
  const keys = Object.keys(f).filter(k => k.indexOf('text/plain') === 0);
  const pref = keys.find(k => /utf-8/i.test(k)) || keys[0];
  let textUrl = pref ? f[pref] : '';
  if (/\.zip$/i.test(textUrl)) textUrl = '';
  const b = {
    gid: g.id,
    title: String(g.title || 'Sem título').replace(/\s+/g, ' ').trim(),
    author: niceAuthor(g.authors && g.authors[0] && g.authors[0].name),
    lang: (g.languages || [])[0] || '',
    downloads: g.download_count || 0,
    textUrl,
    cover: f['image/jpeg'] || ''
  };
  GCACHE[b.gid] = b;
  return b;
}
async function gutendex(params) {
  const sp = new URLSearchParams();
  Object.keys(params).forEach(k => { if (params[k] !== undefined && params[k] !== '') sp.set(k, params[k]); });
  const r = await api('/api/catalog?' + sp.toString());
  return r.json();
}
async function fetchList(params) {
  const data = await gutendex(params);
  return (data.results || []).map(normBook).filter(b => b.textUrl);
}
const shelfBook = gid => state.books.find(b => b.gid === gid);

function tile(g) {
  const sb = shelfBook(g.gid);
  const cover = `<div class="cover"><span>${esc(g.title)}</span>${g.cover ? `<img src="${esc(g.cover)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer" onerror="this.remove()">` : ''}</div>`;
  let act;
  if (!sb) act = `<button class="btn sm primary" data-x="readg" data-id="${g.gid}">Ler</button><button class="btn sm" data-x="addg" data-id="${g.gid}">+ Estante</button>`;
  else if (sb.status === 'finished') act = `<button class="btn sm" data-x="readg" data-id="${g.gid}">Reler</button>`;
  else act = `<button class="btn sm primary" data-x="readg" data-id="${g.gid}">${sb.currentPage > 0 ? 'Continuar' : 'Ler'}</button>${sb.status === 'want' ? '<span class="muted small">na estante</span>' : ''}`;
  return `<article class="tile">${cover}<div class="tt" title="${esc(g.title)}">${esc(g.title)}</div>
    <div class="au">${esc(g.author)}${g.lang ? `<span class="tag">${esc(g.lang.toUpperCase())}</span>` : ''}</div><div class="tact">${act}</div></article>`;
}

function addToShelf(g, status) {
  let b = shelfBook(g.gid);
  if (b) return b;
  b = { id: 'g' + g.gid, gid: g.gid, title: g.title, author: g.author, totalPages: 0, currentPage: 0, rp: 0,
    status, addedAt: new Date().toISOString(), finishedAt: null, rating: 0, note: '', textUrl: g.textUrl, lang: g.lang };
  state.books.push(b);
  return b;
}

/* ---------- aba Biblioteca ---------- */
const lib = { q: '', lang: 'mine', topic: '', page: 1, items: [], loading: false, error: '', hasMore: false, started: false };
async function libSearch(reset) {
  if (reset) { lib.page = 1; lib.items = []; }
  lib.loading = true; lib.error = ''; render();
  try {
    const params = { page: lib.page };
    if (lib.q.trim()) params.search = lib.q.trim();
    const langs = lib.lang === 'mine' ? userLangs().join(',') : lib.lang;
    if (langs) params.languages = langs;
    if (lib.topic) params.topic = lib.topic;
    const data = await gutendex(params);
    const items = (data.results || []).map(normBook).filter(b => b.textUrl);
    lib.items = lib.items.concat(items);
    lib.hasMore = !!data.next;
  } catch (e) { lib.error = e.message; }
  lib.loading = false; render();
}
function renderLibrary() {
  if (!lib.started) { lib.started = true; setTimeout(() => libSearch(true), 0); }
  const chips = GENRES.filter(g => g.topic).map(g => `<button class="gchip ${lib.topic === g.topic ? 'on' : ''}" data-x="libtopic" data-id="${esc(g.topic)}">${esc(g.label)}</button>`).join('');
  const langOpts = [['mine', 'Meus idiomas'], ['', 'Todos']].concat(LANGS.map(l => [l.id, l.label]))
    .map(([v, l]) => `<option value="${v}" ${lib.lang === v ? 'selected' : ''}>${l}</option>`).join('');
  return `
  <section class="card">
    <h2>Biblioteca virtual</h2>
    <p class="muted small" style="margin-top:0">Livros reais de domínio público (Projeto Gutenberg), gratuitos para ler aqui dentro. Seu progresso fica salvo.</p>
    <form id="libForm" class="row">
      <label style="flex:3">Buscar por título ou autor<input id="libQ" data-xin="libq" value="${esc(lib.q)}" placeholder="ex.: Machado de Assis, Dom Casmurro, Sherlock"></label>
      <label>Idioma<select data-xin="liblang">${langOpts}</select></label>
      <button class="btn primary" type="submit">Buscar</button>
    </form>
    <div class="gchips">${chips}</div>
  </section>
  ${lib.error ? `<div class="card empty">${esc(lib.error)}<br><br><button class="btn" data-x="libretry">Tentar de novo</button></div>` : ''}
  ${lib.items.length ? `<div class="bgrid">${lib.items.map(tile).join('')}</div>` : ''}
  ${lib.loading ? '<p class="empty">Carregando…</p>' : ''}
  ${!lib.loading && !lib.error && !lib.items.length ? '<div class="card empty">Nenhum livro encontrado. Tente outra busca ou outro idioma.</div>' : ''}
  ${lib.hasMore && !lib.loading ? '<p class="center"><button class="btn" data-x="libmore">Carregar mais</button></p>' : ''}`;
}

/* ---------- aba Para você (recomendados) ---------- */
const rec = { status: 'idle', sections: [], error: '', seed: 0 };
async function loadRec() {
  rec.status = 'loading'; rec.error = ''; render();
  try {
    const prof = state.profile || {};
    const langs = userLangs().join(',');
    const ids = (prof.genres && prof.genres.length) ? prof.genres : ['classics'];
    const gs = shuffle(ids.map(id => GENRES.find(g => g.id === id)).filter(Boolean)).slice(0, 5);
    const jobs = [];
    const run = (title, params) => {
      const withPage = rec.seed ? Object.assign({}, params, { page: 1 + Math.floor(Math.random() * 3) }) : params;
      return fetchList(withPage).catch(() => fetchList(params)).then(items => ({ title, items })).catch(() => ({ title, items: [], failed: true }));
    };
    gs.forEach(g => jobs.push(run(g.id === 'classics' ? 'Clássicos mais lidos no seu idioma' : 'Porque você gosta de ' + g.label, { languages: langs, topic: g.topic })));
    const fans = state.books.filter(b => b.status === 'finished' && b.rating >= 4 && b.author && b.gid);
    if (fans.length) { const f = shuffle(fans)[0]; jobs.push(run('Mais de ' + f.author + ', que você avaliou bem', { search: f.author, languages: langs })); }
    const results = await Promise.all(jobs);
    if (results.length && results.every(r => r.failed)) throw new Error('Não consegui buscar sugestões agora. Verifique a internet e tente de novo.');
    const seen = new Set();
    rec.sections = results.map(r => ({
      title: r.title,
      items: r.items.filter(b => { if (seen.has(b.gid)) return false; seen.add(b.gid); return true; }).slice(0, 8)
    })).filter(s => s.items.length);
    rec.status = 'done';
  } catch (e) { rec.error = e.message; rec.status = 'error'; }
  render();
}
function renderForYou() {
  if (rec.status === 'idle') { rec.status = 'loading'; setTimeout(loadRec, 0); }
  const p = state.profile || {};
  const gl = (p.genres || []).map(genreLabel).filter(Boolean).join(', ');
  return `
  <section class="card cont">
    <div><h2 style="margin:0">Para você</h2>
    <div class="muted small">${gl ? 'Com base nos seus gostos: ' + esc(gl) : 'Escolha seus gostos para sugestões melhores.'}</div></div>
    <div class="bookact"><button class="btn" data-x="recrefresh">Mostrar outras sugestões</button><button class="btn" data-x="retake">Mudar gostos</button></div>
  </section>
  ${rec.status === 'loading' ? '<p class="empty">Procurando livros para você…</p>' : ''}
  ${rec.status === 'error' ? `<div class="card empty">${esc(rec.error)}<br><br><button class="btn" data-x="recrefresh">Tentar de novo</button></div>` : ''}
  ${rec.status === 'done' && !rec.sections.length ? '<div class="card empty">Não encontrei sugestões para esses gostos e idiomas. Tente incluir outro idioma em “Mudar gostos”.</div>' : ''}
  ${rec.sections.map(s => `<h3 class="sechead">${esc(s.title)}</h3><div class="bgrid">${s.items.map(tile).join('')}</div>`).join('')}`;
}

/* ---------- início: continuar lendo ---------- */
function continueCard() {
  const name = state.profile && state.profile.name;
  const hello = name ? `<h2 class="hello">Olá, ${esc(name)}!</h2>` : '';
  const cur = state.books.filter(b => b.gid && b.status === 'reading').sort((a, b) => (b.lastRead || 0) - (a.lastRead || 0))[0];
  if (cur) {
    const pct = cur.totalPages ? Math.round(cur.currentPage / cur.totalPages * 100) : 0;
    return hello + `<section class="card cont"><div><div class="muted small">Continuar lendo</div><h3>${esc(cur.title)}</h3>
      <div class="muted small">${esc(cur.author)}${cur.totalPages ? ' · página ' + (cur.currentPage + 1) + ' de ' + cur.totalPages + ' (' + pct + '%)' : ''}</div></div>
      <button class="btn primary" data-x="read" data-id="${cur.id}">${cur.currentPage > 0 ? 'Continuar' : 'Começar'}</button></section>`;
  }
  return hello + `<section class="card cont"><div><h3>Escolha seu próximo livro</h3><div class="muted small">Veja sugestões feitas para os seus gostos e leia aqui dentro.</div></div>
    <button class="btn primary" data-x="go" data-v="foryou">Ver sugestões</button></section>`;
}

/* ---------- leitor ---------- */
const PAGE_CHARS = 1600;
function stripGutenberg(t) {
  t = t.replace(/\r\n?/g, '\n');
  const m = t.match(/\*\*\* ?START OF (?:THE|THIS) PROJECT GUTENBERG EBOOK[^\n]*\n/i);
  if (m) t = t.slice(m.index + m[0].length);
  const e = t.search(/\*\*\* ?END OF (?:THE|THIS) PROJECT GUTENBERG EBOOK/i);
  if (e >= 0) t = t.slice(0, e);
  return t.trim();
}
function paginate(text) {
  const paras = [];
  for (let p of text.split(/\n[ \t]*\n+/)) {
    p = p.replace(/ /g, ' ').trim();
    if (!p) continue;
    const lines = p.split('\n').map(l => l.trim()).filter(Boolean);
    if (!lines.length) continue;
    const avg = lines.reduce((a, l) => a + l.length, 0) / lines.length;
    const t = (lines.length > 1 && avg < 38) ? lines.join('\n') : lines.join(' ').replace(/\s{2,}/g, ' ');
    const h = t.length < 70 && /[A-ZÀ-Ý]/.test(t) && !/[a-zà-ÿ]/.test(t);
    if (t.length > 2600 && !h) {
      let rest = t;
      while (rest.length > 2000) {
        let cut = rest.lastIndexOf('. ', 1800);
        if (cut < 600) cut = rest.indexOf(' ', 1800);
        if (cut < 0) break;
        paras.push({ t: rest.slice(0, cut + 1).trim(), h: false });
        rest = rest.slice(cut + 1).trim();
      }
      if (rest) paras.push({ t: rest, h: false });
    } else paras.push({ t, h });
  }
  const pages = []; let cur = [], n = 0;
  for (const p of paras) {
    if (cur.length && ((p.h && n > PAGE_CHARS * 0.5) || n + p.t.length > PAGE_CHARS * 1.25)) { pages.push(cur); cur = []; n = 0; }
    cur.push(p); n += p.t.length;
    if (n >= PAGE_CHARS && !p.h) { pages.push(cur); cur = []; n = 0; }
  }
  if (cur.length) pages.push(cur);
  return pages;
}

let R = null;
const rprefs = () => Object.assign({ size: 19, theme: 'sepia' }, state.prefs || {});
function readerShell(inner, theme) {
  const el = $('#reader');
  el.className = 'reader th-' + (theme || rprefs().theme);
  el.hidden = false;
  el.innerHTML = inner;
  document.body.style.overflow = 'hidden';
}
function readerMsg(b, html) {
  readerShell(`<div class="rhead"><button class="btn sm" data-x="rclose">← Voltar</button><div class="rtitle">${esc(b.title)}</div></div><div class="rbody"><div class="rmsg">${html}</div></div>`);
}
async function openReader(id) {
  const b = state.books.find(x => x.id === id);
  if (!b || !b.gid) return;
  R = null;
  readerMsg(b, '<p>Preparando o livro… Na primeira vez ele é baixado e fica guardado no computador para ler offline depois.</p>');
  try {
    const r = await api('/api/book?gid=' + b.gid + '&u=' + encodeURIComponent(b.textUrl || ''));
    const pages = paginate(stripGutenberg(await r.text()));
    if (!pages.length) throw new Error('Não consegui ler o texto deste livro.');
    b.totalPages = pages.length;
    let idx = Math.max(0, Math.min(pages.length - 1, b.rp != null ? b.rp : (b.currentPage || 0)));
    if (b.status === 'want') b.status = 'reading';
    b.rp = idx; b.currentPage = Math.min(b.status === 'finished' ? b.totalPages : idx, b.totalPages);
    b.lastRead = Date.now();
    R = { b, pages, idx, pagesAcc: 0, secs: 0, lastAct: Date.now(), lastFlush: Date.now(), wasMet: goalMet(todayStr()) };
    Store.save(state);
    renderPage();
  } catch (e) {
    readerMsg(b, `<p>${esc(e.message)}</p><p><button class="btn primary" data-x="rretry" data-id="${esc(id)}">Tentar de novo</button> <button class="btn" data-x="rclose">Voltar</button></p>`);
  }
}
function renderPage() {
  if (!R) return;
  const { b, pages, idx } = R, n = pages.length, pr = rprefs();
  const body = pageBody();
  const pct = Math.round((idx + 1) / n * 100);
  readerShell(`
    <div class="rhead">
      <button class="btn sm" data-x="rclose">← Voltar</button>
      <div class="rtitle">${esc(b.title)} <span style="font-weight:400;color:var(--rmut)">· ${esc(b.author)}</span></div>
      <button class="btn sm" data-x="rfont" data-v="-1" title="Diminuir letra">A−</button>
      <button class="btn sm" data-x="rfont" data-v="1" title="Aumentar letra">A+</button>
      <button class="btn sm" data-x="rtheme" title="Trocar tema">Tema</button>
      <button class="btn sm" data-x="hllist" title="Seus grifos neste livro">🖍 ${(b.hl || []).length}</button>
    </div>
    <div class="rbody" id="rbody"><article style="font-size:${pr.size}px">${body}</article></div>
    <div class="rfoot">
      <button class="btn" data-x="rprev" ${idx === 0 ? 'disabled' : ''}>←</button>
      <input type="range" id="rslider" min="0" max="${n - 1}" value="${idx}" aria-label="Posição no livro">
      <div class="rinfo">Página ${idx + 1} de ${n} · ${pct}%</div>
      <button class="btn primary" data-x="rnext">${idx === n - 1 ? 'Concluir livro' : '→'}</button>
    </div>`, pr.theme);
}
function goPage(n) {
  if (!R) return;
  n = Math.max(0, Math.min(R.pages.length - 1, n));
  if (n === R.idx) return;
  const d = n - R.idx;
  if (d > 0 && d <= 3) R.pagesAcc += d;
  R.idx = n; R.b.rp = n; R.b.lastRead = Date.now();
  if (R.b.status !== 'finished') R.b.currentPage = n;
  R.lastAct = Date.now();
  renderPage();
  Store.save(state);
}
function flushReading(final) {
  if (!R) return false;
  let min = Math.floor(R.secs / 60);
  if (final && min === 0 && R.secs >= 20) min = 1;
  const pg = R.pagesAcc;
  if (!min && !(final && pg)) return false;
  state.logs.push({ id: uid(), date: todayStr(), ts: Date.now(), bookId: R.b.id, pages: pg, minutes: min });
  _map = null;
  R.secs = Math.max(0, R.secs - min * 60); R.pagesAcc = 0; R.lastFlush = Date.now();
  Store.save(state);
  return true;
}
function closeReader(skipRender) {
  if (R) flushReading(true);
  const met = R ? R.wasMet : true;
  R = null;
  const el = $('#reader'); el.hidden = true; el.innerHTML = '';
  document.body.style.overflow = '';
  Store.save(state); _map = null;
  if (!skipRender) { render(); if (!met && goalMet(todayStr())) toast('Meta de hoje concluída! 🔥'); }
}
setInterval(() => {
  if (!R) return;
  if (document.visibilityState === 'visible' && Date.now() - R.lastAct < 120000) R.secs++;
  if (Date.now() - R.lastFlush > 300000) flushReading(false);
}, 1000);
['keydown', 'click', 'mousemove', 'wheel', 'scroll'].forEach(ev => document.addEventListener(ev, () => { if (R) R.lastAct = Date.now(); }, true));

/* ---------- tela inicial de gostos ---------- */
let onb = { step: 0, name: '', genres: [], langs: ['pt'], goal: 15 };
function renderOnb() {
  const s = onb.step;
  let h = `<div class="onbbox"><div class="onbbrand">Páginas</div><div class="onbdots">${[0, 1, 2].map(i => `<i class="${i <= s ? 'on' : ''}"></i>`).join('')}</div>`;
  if (s === 0) {
    h += `<h1>Bem-vindo(a)!</h1><p>Vamos montar uma biblioteca com a sua cara. Leva menos de um minuto e você pode mudar tudo depois.</p>
      <label>Como posso te chamar? (opcional)<input id="onbName" data-xin="onbname" maxlength="40" value="${esc(onb.name)}"></label>`;
  } else if (s === 1) {
    h += `<h1>Do que você gosta de ler?</h1><p class="muted">Escolha quantos quiser. Isso define as sugestões da aba “Para você”.</p>
      <div class="gchips">${GENRES.map(g => `<button class="gchip ${onb.genres.includes(g.id) ? 'on' : ''}" data-x="onbgenre" data-id="${g.id}">${esc(g.label)}</button>`).join('')}</div>`;
  } else {
    h += `<h1>Últimos detalhes</h1><p class="muted">Em quais idiomas você lê?</p>
      <div class="gchips">${LANGS.map(l => `<button class="gchip ${onb.langs.includes(l.id) ? 'on' : ''}" data-x="onblang" data-id="${l.id}">${esc(l.label)}</button>`).join('')}</div>
      <p class="muted" style="margin-top:1.4rem">Quanto tempo por dia você quer ler? Comece pequeno: o hábito vale mais que o volume.</p>
      <div class="gchips">${[5, 10, 15, 20, 30].map(m => `<button class="gchip ${onb.goal === m ? 'on' : ''}" data-x="onbgoal" data-id="${m}">${m} min</button>`).join('')}</div>`;
  }
  h += `<div class="onbact"><div>${s > 0 ? '<button class="btn" data-x="onbback">Voltar</button>' : '<button class="btn" data-x="onbskip">Pular</button>'}</div>
    <button class="btn primary" data-x="onbnext">${s === 2 ? 'Concluir' : 'Continuar'}</button></div></div>`;
  return h;
}
function finishOnb() {
  state.profile = { name: onb.name.trim(), genres: onb.genres.slice(), langs: onb.langs.length ? onb.langs.slice() : ['pt'], createdAt: todayStr() };
  state.settings.goalType = 'minutes'; state.settings.dailyGoal = onb.goal;
  rec.status = 'idle'; rec.sections = []; rec.seed = 0;
  lib.started = false; lib.items = [];
  view = 'foryou';
  commit();
}

/* ---------- ajustes extras ---------- */
function settingsExtra() {
  const p = state.profile || {};
  const gl = (p.genres || []).map(genreLabel).filter(Boolean).join(', ') || 'nenhum';
  const ll = (p.langs || []).map(id => (LANGS.find(l => l.id === id) || {}).label).filter(Boolean).join(', ') || 'Português';
  return `<section class="card"><h2>Seus gostos</h2><p style="margin-top:0">Gêneros: ${esc(gl)}<br>Idiomas: ${esc(ll)}</p>
    <button class="btn" data-x="retake">Refazer as perguntas</button></section>`;
}

/* ---------- ligação com o app existente ---------- */
const VIEWS = { today: renderToday, foryou: renderForYou, library: renderLibrary, shelf: renderShelf, stats: renderStats,
  settings: function () { return renderSettings() + settingsExtra(); } };
const _origRender = render;
render = function () {
  _origRender();
  const onbEl = $('#onb');
  if (!state.profile) { onbEl.hidden = false; onbEl.innerHTML = renderOnb(); } else { onbEl.hidden = true; }
};

document.addEventListener('click', e => {
  const el = e.target.closest('[data-x]'); if (!el) return;
  const x = el.dataset.x, id = el.dataset.id, v = el.dataset.v;
  const redrawOnb = () => { $('#onb').innerHTML = renderOnb(); };
  switch (x) {
    case 'go': view = v; render(); break;
    case 'read': openReader(id); break;
    case 'rretry': openReader(id); break;
    case 'readg': { const g = GCACHE[Number(id)]; if (!g) break; const b = addToShelf(g, 'reading'); if (b.status === 'want') b.status = 'reading'; Store.save(state); openReader(b.id); break; }
    case 'addg': { const g = GCACHE[Number(id)]; if (!g) break; addToShelf(g, 'want'); commit(); toast('Adicionado à estante (Quero ler).'); break; }
    case 'libtopic': lib.topic = lib.topic === id ? '' : id; libSearch(true); break;
    case 'libmore': lib.page++; libSearch(false); break;
    case 'libretry': libSearch(lib.items.length === 0); break;
    case 'recrefresh': rec.seed++; loadRec(); break;
    case 'retake':
      onb = { step: 0, name: (state.profile && state.profile.name) || '', genres: ((state.profile && state.profile.genres) || []).slice(),
        langs: ((state.profile && state.profile.langs) || ['pt']).slice(), goal: state.settings.dailyGoal || 15 };
      state.profile = null; commit(); break;
    case 'onbgenre': onb.genres = onb.genres.includes(id) ? onb.genres.filter(g => g !== id) : onb.genres.concat(id); redrawOnb(); break;
    case 'onblang': onb.langs = onb.langs.includes(id) ? onb.langs.filter(g => g !== id) : onb.langs.concat(id); redrawOnb(); break;
    case 'onbgoal': onb.goal = Number(id); redrawOnb(); break;
    case 'onbback': onb.step = Math.max(0, onb.step - 1); redrawOnb(); break;
    case 'onbskip': onb.genres = []; finishOnb(); break;
    case 'onbnext':
      if (onb.step === 1 && !onb.genres.length) { toast('Escolha pelo menos um gênero (ou volte e toque em Pular).'); break; }
      if (onb.step === 2 && !onb.langs.length) { toast('Escolha pelo menos um idioma.'); break; }
      if (onb.step < 2) { onb.step++; redrawOnb(); } else finishOnb();
      break;
    case 'rclose': closeReader(); break;
    case 'rprev': if (R) goPage(R.idx - 1); break;
    case 'rnext':
      if (!R) break;
      if (R.idx >= R.pages.length - 1) { const bid = R.b.id; closeReader(true); finishBook(bid); }
      else goPage(R.idx + 1);
      break;
    case 'rfont': { const pr = rprefs(); state.prefs = Object.assign({}, state.prefs, { size: Math.max(14, Math.min(30, pr.size + Number(v) * 2)) }); Store.save(state); renderPage(); break; }
    case 'rtheme': { const order = ['sepia', 'light', 'dark']; const pr = rprefs(); state.prefs = Object.assign({}, state.prefs, { theme: order[(order.indexOf(pr.theme) + 1) % 3] }); Store.save(state); renderPage(); break; }
  }
});
document.addEventListener('input', e => {
  const k = e.target.dataset && e.target.dataset.xin;
  if (k === 'libq') lib.q = e.target.value;
  if (k === 'onbname') onb.name = e.target.value;
});
document.addEventListener('change', e => {
  const k = e.target.dataset && e.target.dataset.xin;
  if (k === 'liblang') { lib.lang = e.target.value; libSearch(true); }
  if (e.target.id === 'rslider' && R) goPage(Number(e.target.value));
});
document.addEventListener('submit', e => { if (e.target.id === 'libForm') libSearch(true); });
document.addEventListener('keydown', e => {
  if (!R || $('#reader').hidden) return;
  const dlgEl = $('#dlg'); if (dlgEl && dlgEl.open) return;
  const t = e.target;
  if (t && /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName) && t.type !== 'range') return;
  if (e.key === 'ArrowRight' || e.key === 'PageDown') { e.preventDefault(); if (R.idx < R.pages.length - 1) goPage(R.idx + 1); }
  else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); goPage(R.idx - 1); }
  else if (e.key === 'Escape') closeReader();
});

/* ---------- início do programa ---------- */
function startPing() {
  const ping = () => api('/api/ping').catch(() => {});
  ping(); setInterval(ping, 5000);
  addEventListener('pagehide', () => { flushReading(true); flushSave(); try { navigator.sendBeacon('/api/bye?t=' + API.token); } catch (e) {} });
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden') { flushReading(false); flushSave(); } });
}
async function boot() {
  if (IS_APP) {
    try {
      const r = await api('/api/load');
      const p = await r.json();
      if (p && Array.isArray(p.books)) {
        const d = defaults();
        state = Object.assign({}, d, p, { settings: Object.assign({}, d.settings, p.settings || {}) });
      }
    } catch (e) { loadFailed = true; toast('Não consegui abrir seus dados salvos: ' + e.message); }
    startPing();
  }
  render();
}
boot().finally(() => { window.__booted = true; });

</script>
<style>
.feed{max-width:620px;margin:0 auto}
.fsearch{display:flex;gap:.5rem;margin-bottom:.9rem}
.stories{display:flex;gap:.8rem;overflow-x:auto;padding:.2rem .1rem .9rem;scrollbar-width:none}
.story{flex:none;width:68px;text-align:center;background:none;border:0;cursor:pointer;color:var(--muted);font:inherit;font-size:.72rem}
.story .ring2{width:60px;height:60px;border-radius:50%;padding:3px;background:var(--line);margin:0 auto .25rem}
.story.on .ring2{background:conic-gradient(var(--accent),var(--warn),var(--accent))}
.story.on{color:var(--ink);font-weight:700}
.story .in{width:100%;height:100%;border-radius:50%;background:var(--card);display:flex;align-items:center;justify-content:center;font-size:1.5rem}
.post{background:var(--card);border:1px solid var(--line);border-radius:16px;margin-bottom:1rem;overflow:hidden}
.phead{display:flex;align-items:center;gap:.6rem;padding:.7rem .9rem}
.av{width:38px;height:38px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:1.15rem;flex:none}
.pname{font-weight:700;font-size:.92rem;line-height:1.15}
.psub{font-size:.75rem;color:var(--muted)}
.pbody{padding:0 .9rem .8rem}
.pbody h3{font-size:1.05rem;margin:0 0 .3rem}
.pbody p{margin:.2rem 0 .7rem}
.pquote{margin:0 .9rem .7rem;padding:1.4rem 1.2rem;border-radius:12px;color:#fff;background:linear-gradient(135deg,hsl(var(--h) 50% 36%),hsl(var(--h) 45% 22%))}
.pquote p{font:italic 1.2rem/1.5 Georgia,serif;margin:0 0 .6rem}
.pquote small{opacity:.85}
.pact{display:flex;gap:.2rem;border-top:1px solid var(--line);padding:.25rem .5rem}
.pbtn{background:none;border:0;font:inherit;font-size:.88rem;color:var(--muted);cursor:pointer;padding:.45rem .7rem;border-radius:8px}
.pbtn:hover{color:var(--ink);background:var(--bg)}
.pbtn.on{color:var(--accent);font-weight:700}
.hscroll{display:flex;gap:.8rem;overflow-x:auto;padding:0 .9rem .9rem;scroll-snap-type:x mandatory}
.hscroll .tile{flex:none;width:136px;scroll-snap-align:start}
.fbook{display:flex;gap:.9rem;padding:0 .9rem .9rem}
.fbook .cover{width:100px;flex:none;margin:0}
.lrow{display:flex;align-items:center;gap:.7rem;width:100%;text-align:left;background:none;border:0;border-top:1px solid var(--line);padding:.6rem .9rem;font:inherit;color:var(--ink);cursor:pointer}
.lrow:hover{background:var(--bg)}
.lrow span{color:var(--accent);font-weight:700;width:1.2rem}
.lrow b{flex:1;font-weight:600}
.lrow em{color:var(--muted);font-style:normal;font-size:.82rem}
.qopt{display:block;width:100%;text-align:left;font:inherit;background:var(--bg);color:var(--ink);border:1px solid var(--line);border-radius:10px;padding:.55rem .8rem;margin-bottom:.4rem;cursor:pointer}
.qopt:hover:not(:disabled){border-color:var(--accent)}
.qopt.right{background:var(--ok);color:#fff;border-color:var(--ok)}
.qopt.wrong{border-color:#c0392b;color:#c0392b}
.srows{display:flex;flex-direction:column;gap:.6rem;margin-bottom:1rem}
.srow{display:flex;gap:.8rem;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:.6rem}
.srow .cover{width:62px;flex:none;margin:0;font-size:.6rem;padding:.3rem}
.srow h4{margin:0;font:600 .98rem/1.25 system-ui,sans-serif}
.srow .muted{font-size:.82rem}
.srow .bookact{margin-top:.4rem}
</style>
<script>
/* ====================================================================
   PARTE 3: feed "Para você" (estilo rede social) e aba Pesquisar
   ==================================================================== */
lib.req = 0;
const ensure = () => { state.likes = state.likes || {}; state.saved = state.saved || {}; state.recent = state.recent || []; };
const GEMO = { romance: '💞', adventure: '🧭', mystery: '🕵️', scifi: '🚀', fantasy: '🐉', horror: '🦇', classics: '🏛️', philosophy: '🤔', history: '📜', poetry: '🪶', drama: '🎭', humor: '😄', children: '🧸', biography: '👤', science: '🔬' };
const ACC = {
  quote: { n: 'Frases & Clássicos', e: '💬', h: 18 }, fact: { n: 'Você sabia?', e: '💡', h: 42 }, author: { n: 'Autor em destaque', e: '✍️', h: 200 },
  list: { n: 'Clube Páginas', e: '📚', h: 340 }, tip: { n: 'Hábito de leitura', e: '🔥', h: 12 }, quiz: { n: 'Quiz literário', e: '🧩', h: 150 },
  book: { n: 'Descobertas', e: '🧭', h: 260 }, me: { n: 'Seu progresso', e: '📈', h: 100 }
};

/* ---------- banco de conteúdos (só obras e autores de domínio público) ---------- */
const Q = (id, text, by, work, pt, g) => ({ id, kind: 'quote', text, by, work, pt, g });
const F = (id, title, text, g, q) => ({ id, kind: 'fact', title, text, g, q });
const A = (id, name, yrs, bio, q, g) => ({ id, kind: 'author', name, yrs, bio, q, g });
const L = (id, title, items, g) => ({ id, kind: 'list', title, items, g });
const T = (id, tag, title, text, g, btn) => ({ id, kind: 'tip', tag, title, text, g: g || [], btn });
const Z = (id, q, opts, a, exp, g) => ({ id, kind: 'quiz', q, opts, a, exp, g });
const CONTENT = [
  Q('q1', 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.', 'Jane Austen', 'Orgulho e Preconceito (1813)', 'É uma verdade universalmente reconhecida que um homem solteiro, dono de uma boa fortuna, deve estar procurando esposa.', ['romance', 'classics']),
  Q('q2', 'It was the best of times, it was the worst of times, it was the age of wisdom, it was the age of foolishness…', 'Charles Dickens', 'Um Conto de Duas Cidades (1859)', 'Era o melhor dos tempos, era o pior dos tempos, era a idade da sabedoria, era a idade da tolice…', ['classics', 'history']),
  Q('q3', 'Call me Ishmael.', 'Herman Melville', 'Moby Dick (1851)', 'Chamem-me Ishmael.', ['adventure', 'classics']),
  Q('q4', 'Curiouser and curiouser!', 'Lewis Carroll', 'Alice no País das Maravilhas (1865)', 'Cada vez mais curioso! (Alice erra a gramática de tanto espanto.)', ['children', 'fantasy']),
  Q('q5', 'When you have eliminated the impossible, whatever remains, however improbable, must be the truth.', 'Arthur Conan Doyle', 'O Signo dos Quatro (1890)', 'Quando você elimina o impossível, o que sobra, por mais improvável que seja, deve ser a verdade.', ['mystery']),
  Q('q6', 'Beware; for I am fearless, and therefore powerful.', 'Mary Shelley', 'Frankenstein (1818)', 'Cuidado, pois não tenho medo e, por isso, sou poderoso.', ['horror', 'scifi']),
  Q('q7', 'I can resist everything except temptation.', 'Oscar Wilde', 'O Leque de Lady Windermere (1892)', 'Resisto a tudo, menos à tentação.', ['humor', 'drama']),
  Q('q8', 'Ao verme que primeiro roeu as frias carnes do meu cadáver dedico como saudosa lembrança estas Memórias Póstumas.', 'Machado de Assis', 'Memórias Póstumas de Brás Cubas (1881)', '', ['classics', 'humor']),
  Q('q9', 'Tudo vale a pena / Se a alma não é pequena.', 'Fernando Pessoa', 'Mensagem (1934)', '', ['poetry']),
  Q('q10', 'Amor é fogo que arde sem se ver; / É ferida que dói e não se sente;', 'Luís de Camões', 'Sonetos', '', ['poetry', 'romance']),
  Q('q11', 'Whatever our souls are made of, his and mine are the same.', 'Emily Brontë', 'O Morro dos Ventos Uivantes (1847)', 'Seja do que for que as nossas almas são feitas, a dele e a minha são iguais.', ['romance', 'classics']),
  Q('q12', 'En un lugar de la Mancha, de cuyo nombre no quiero acordarme…', 'Miguel de Cervantes', 'Dom Quixote (1605)', 'Num lugar da Mancha, de cujo nome não quero me lembrar…', ['adventure', 'humor', 'classics']),
  F('f1', 'De onde vêm os livros da biblioteca?', 'Eles vêm do Projeto Gutenberg, considerado a biblioteca digital mais antiga do mundo. Começou em 1971, com Michael Hart, e reúne dezenas de milhares de obras de domínio público.', [], ''),
  F('f2', 'Machado e a Academia', 'Machado de Assis foi o primeiro presidente da Academia Brasileira de Letras, fundada em 1897. Dom Casmurro saiu dois anos depois, em 1899.', ['classics'], 'Machado de Assis'),
  F('f3', 'Frankenstein nasceu de um desafio', 'Mary Shelley começou a escrever Frankenstein aos 18 anos, num verão chuvoso na Suíça, depois que um grupo de amigos combinou de escrever histórias de fantasmas. O livro saiu em 1818, sem o nome dela na capa.', ['horror', 'scifi'], 'Mary Shelley'),
  F('f4', 'Quantos casos tem Sherlock Holmes?', 'Conan Doyle escreveu quatro romances e 56 contos com o detetive mais famoso da literatura.', ['mystery'], 'Conan Doyle'),
  F('f5', 'Jane Austen sem assinatura', 'Os primeiros romances de Jane Austen saíram sem o nome dela. Razão e Sensibilidade, de 1811, foi assinado apenas como “por uma dama”.', ['romance'], 'Austen'),
  F('f6', 'Moby Dick demorou a ser amado', 'Quando saiu, em 1851, Moby Dick vendeu pouco. Só no século XX o livro passou a ser tratado como obra-prima.', ['adventure', 'classics'], 'Melville'),
  F('f7', 'Alice nasceu num passeio de barco', 'A história foi contada em 1862, num passeio pelo rio, para Alice Liddell, de 10 anos. Três anos depois virou livro.', ['children', 'fantasy'], 'Lewis Carroll'),
  F('f8', 'Drácula é feito de cartas', 'Drácula (1897) é um romance epistolar: a história é contada por diários, cartas e recortes de jornal.', ['horror'], 'Stoker'),
  A('a1', 'Machado de Assis', '1839–1908', 'Carioca de origem humilde, autodidata, virou o maior nome da literatura brasileira. Narradores irônicos que conversam com o leitor. Comece por Memórias Póstumas de Brás Cubas ou Dom Casmurro.', 'Machado de Assis', ['classics', 'humor']),
  A('a2', 'Jane Austen', '1775–1817', 'Inglesa, escreveu seis romances afiados sobre dinheiro, casamento e as pequenas hipocrisias da sociedade. Um bom começo: Orgulho e Preconceito.', 'Austen', ['romance']),
  A('a3', 'Edgar Allan Poe', '1809–1849', 'Americano, mestre do suspense e do macabro. É apontado como inventor do conto policial moderno, com Os Crimes da Rua Morgue (1841), e autor do poema O Corvo.', 'Poe', ['mystery', 'horror', 'poetry']),
  A('a4', 'Eça de Queirós', '1845–1900', 'Português, o grande nome do romance realista em sua língua. Ironia e crítica social em O Primo Basílio, Os Maias e O Crime do Padre Amaro.', 'Queirós', ['classics', 'drama']),
  A('a5', 'Júlio Verne', '1828–1905', 'Francês, pioneiro da ficção científica de aventura. Escreveu Vinte Mil Léguas Submarinas, A Volta ao Mundo em 80 Dias e Viagem ao Centro da Terra.', 'Verne', ['scifi', 'adventure']),
  A('a6', 'José de Alencar', '1829–1877', 'Cearense, um dos pilares do romantismo brasileiro. Escreveu O Guarani, Iracema e Senhora.', 'Alencar', ['romance', 'history']),
  A('a7', 'Fiódor Dostoiévski', '1821–1881', 'Russo, explorou como poucos a culpa, a fé e a mente humana em Crime e Castigo e Os Irmãos Karamázov.', 'Dostoyevsky', ['philosophy', 'drama']),
  A('a8', 'Oscar Wilde', '1854–1900', 'Irlandês, famoso pelo humor afiado. Escreveu O Retrato de Dorian Gray e a peça A Importância de Ser Prudente.', 'Wilde', ['humor', 'drama']),
  L('l1', '5 clássicos curtos para um fim de semana', [['O Alienista (Machado de Assis)', 'Alienista'], ['O Médico e o Monstro (Stevenson)', 'Jekyll and Hyde'], ['A Metamorfose (Kafka)', 'Metamorphosis'], ['Bartleby, o Escrivão (Melville)', 'Bartleby'], ['Um Conto de Natal (Dickens)', 'Christmas Carol']], ['classics']),
  L('l2', 'Mistérios para devorar', [['As Aventuras de Sherlock Holmes', 'Adventures of Sherlock Holmes'], ['O Cão dos Baskervilles', 'Hound of the Baskervilles'], ['A Pedra da Lua (Wilkie Collins)', 'Moonstone'], ['Os Crimes da Rua Morgue (Poe)', 'Rue Morgue'], ['Arsène Lupin', 'Arsene Lupin']], ['mystery']),
  L('l3', 'Brasileiros para ter na estante', [['Dom Casmurro', 'Dom Casmurro'], ['Memórias Póstumas de Brás Cubas', 'Brás Cubas'], ['O Cortiço (Aluísio Azevedo)', 'Cortiço'], ['Iracema (José de Alencar)', 'Iracema'], ['Triste Fim de Policarpo Quaresma', 'Policarpo Quaresma']], ['classics', 'history']),
  L('l4', 'Aventuras para fugir da rotina', [['A Ilha do Tesouro', 'Treasure Island'], ['Vinte Mil Léguas Submarinas', 'Twenty Thousand Leagues'], ['Robinson Crusoé', 'Robinson Crusoe'], ['Os Três Mosqueteiros', 'Three Musketeers'], ['O Livro da Selva', 'Jungle Book']], ['adventure']),
  L('l5', 'Ficção científica com mais de 100 anos', [['Frankenstein', 'Frankenstein'], ['A Máquina do Tempo (H. G. Wells)', 'Time Machine'], ['A Guerra dos Mundos', 'War of the Worlds'], ['Da Terra à Lua (Verne)', 'From the Earth to the Moon'], ['A Ilha do Dr. Moreau', 'Island of Doctor Moreau']], ['scifi']),
  L('l6', 'Romances para suspirar', [['Orgulho e Preconceito', 'Pride and Prejudice'], ['Jane Eyre', 'Jane Eyre'], ['O Morro dos Ventos Uivantes', 'Wuthering Heights'], ['Persuasão (Austen)', 'Persuasion'], ['Senhora (José de Alencar)', 'Senhora']], ['romance']),
  L('l7', 'Terror clássico para a noite', [['Drácula', 'Dracula'], ['Carmilla', 'Carmilla'], ['A Volta do Parafuso', 'Turn of the Screw'], ['O Retrato de Dorian Gray', 'Dorian Gray'], ['O Corvo (Poe)', 'Raven']], ['horror']),
  L('l8', 'Filosofia para começar', [['A República (Platão)', 'Republic Plato'], ['Meditações (Marco Aurélio)', 'Meditations Marcus Aurelius'], ['O Príncipe (Maquiavel)', 'The Prince Machiavelli'], ['Assim Falou Zaratustra', 'Zarathustra']], ['philosophy']),
  T('t1', 'Dica', 'Comece pequeno', 'Uma meta de 5 minutos que você cumpre todo dia vale mais do que uma hora que você abandona na terceira noite.', [], ['Ajustar minha meta', 'settings']),
  T('t2', 'Dica', 'Deixe o livro à vista', 'Livro na mesa de cabeceira ou na mochila é leitura que acontece. Livro guardado vira boa intenção.', []),
  T('t3', 'Dica', 'A regra das 50 páginas', 'Se depois de umas 50 páginas o livro não te pegou, trocar de livro não é fracasso. Quem lê por prazer pode escolher outro.', [], ['Procurar outro livro', 'library']),
  T('t4', 'Dica', 'Mude o visual do leitor', 'No leitor do Páginas dá para aumentar a letra (A+) e trocar o tema entre sépia, claro e escuro. Experimente à noite.', [], ['Abrir a estante', 'shelf']),
  T('t5', 'Desafio', 'Desafio dos 7 dias', 'Leia 10 minutos por dia durante uma semana e registre cada leitura em “Hoje”. Ao fim, veja a sequência crescer.', [], ['Ir para Hoje', 'today']),
  T('t6', 'Desafio', 'Fora da zona de conforto', 'Escolha um gênero que você quase nunca lê e tente um livro curto dele. Pode surgir um novo favorito.', [], ['Explorar livros', 'library']),
  Z('z1', 'Quem escreveu Dom Casmurro?', ['Machado de Assis', 'José de Alencar', 'Eça de Queirós', 'Lima Barreto'], 0, 'Machado de Assis, em 1899. A dúvida sobre Capitu rende debate até hoje.', ['classics']),
  Z('z2', 'Em que cidade fica a Baker Street, onde mora Sherlock Holmes?', ['Londres', 'Paris', 'Edimburgo', 'Dublin'], 0, 'Em Londres, no endereço fictício 221B.', ['mystery']),
  Z('z3', 'No romance de Mary Shelley, quem é Frankenstein?', ['A criatura', 'O cientista que a cria', 'O capitão do navio', 'O narrador das cartas'], 1, 'Frankenstein é Victor, o cientista. A criatura não recebe nome.', ['horror', 'scifi']),
  Z('z4', 'Quem escreveu Os Lusíadas?', ['Camões', 'Fernando Pessoa', 'Eça de Queirós', 'Gil Vicente'], 0, 'Luís de Camões, em 1572, o grande épico da língua portuguesa.', ['poetry', 'history']),
  Z('z5', 'Como se chama o capitão obcecado pela baleia branca em Moby Dick?', ['Ahab', 'Ishmael', 'Nemo', 'Flint'], 0, 'Ahab. Ishmael é o narrador, e Nemo é de Vinte Mil Léguas Submarinas.', ['adventure']),
  Z('z6', 'Os nomes Caeiro, Reis e Campos pertencem a quê?', ['Heterônimos de Pessoa', 'Personagens de Machado', 'Poetas árcades', 'Tradutores de Homero'], 0, 'São heterônimos de Fernando Pessoa: poetas inventados, cada um com estilo próprio.', ['poetry'])
];

/* ---------- peças de HTML ---------- */
const hue = id => { let h = 0; for (const c of String(id)) h = (h * 31 + c.charCodeAt(0)) % 360; return h; };
function head(kind, sub) { const a = ACC[kind]; return `<div class="phead"><div class="av" style="background:hsl(${a.h} 55% 85%)">${a.e}</div><div><div class="pname">${a.n}</div><div class="psub">${esc(sub || '')}</div></div></div>`; }
function acts(p) {
  ensure();
  return `<div class="pact"><button class="pbtn ${state.likes[p.id] ? 'on' : ''}" data-x="plike" data-id="${p.id}">${state.likes[p.id] ? '♥ Curtido' : '♡ Curtir'}</button><button class="pbtn ${state.saved[p.id] ? 'on' : ''}" data-x="psave" data-id="${p.id}">${state.saved[p.id] ? '🔖 Salvo' : '🔖 Salvar'}</button>${p.kind === 'quote' ? `<button class="pbtn" data-x="pcopy" data-id="${p.id}">Copiar</button>` : ''}</div>`;
}
let coverHtml = g => `<div class="cover"><span>${esc(g.title)}</span>${g.cover ? `<img src="${esc(g.cover)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer" onerror="this.remove()">` : ''}</div>`;
function tileAct(g) {
  const sb = shelfBook(g.gid);
  if (!sb) return `<button class="btn sm primary" data-x="readg" data-id="${g.gid}">Ler</button><button class="btn sm" data-x="addg" data-id="${g.gid}">+ Estante</button>`;
  if (sb.status === 'finished') return `<button class="btn sm" data-x="readg" data-id="${g.gid}">Reler</button>`;
  return `<button class="btn sm primary" data-x="readg" data-id="${g.gid}">${sb.currentPage > 0 ? 'Continuar' : 'Ler'}</button>`;
}
function postHtml(p) {
  const P = c => `<article class="post" data-pid="${esc(p.id)}">${c}</article>`;
  switch (p.kind) {
    case 'quote': return P(`${head('quote', p.work)}<div class="pquote" style="--h:${hue(p.id)}"><p>“${esc(p.text)}”</p><small>— ${esc(p.by)}</small></div>${p.pt ? `<div class="pbody muted small">Tradução livre: ${esc(p.pt)}</div>` : ''}${acts(p)}`);
    case 'fact': return P(`${head('fact', 'Curiosidade')}<div class="pbody"><h3>${esc(p.title)}</h3><p>${esc(p.text)}</p>${p.q ? `<button class="btn sm" data-x="psearch" data-q="${esc(p.q)}">Ver livros relacionados</button>` : ''}</div>${acts(p)}`);
    case 'author': return P(`${head('author', p.yrs)}<div class="pbody"><h3>${esc(p.name)}</h3><p>${esc(p.bio)}</p><button class="btn sm primary" data-x="psearch" data-q="${esc(p.q)}">Ver obras</button></div>${acts(p)}`);
    case 'list': return P(`${head('list', 'Lista')}<div class="pbody"><h3>${esc(p.title)}</h3></div>${p.items.map((it, i) => `<button class="lrow" data-x="psearch" data-q="${esc(it[1])}"><span>${i + 1}</span><b>${esc(it[0])}</b><em>Buscar ›</em></button>`).join('')}${acts(p)}`);
    case 'tip': return P(`${head('tip', p.tag)}<div class="pbody"><h3>${esc(p.title)}</h3><p>${esc(p.text)}</p>${p.btn ? `<button class="btn sm primary" data-x="go" data-v="${p.btn[1]}">${esc(p.btn[0])}</button>` : ''}</div>${acts(p)}`);
    case 'quiz': {
      const ans = feed.quiz[p.id], done = ans !== undefined;
      return P(`${head('quiz', 'Teste seus conhecimentos')}<div class="pbody"><h3>${esc(p.q)}</h3>${p.opts.map((o, i) => `<button class="qopt ${done ? (i === p.a ? 'right' : (i === ans ? 'wrong' : '')) : ''}" ${done ? 'disabled' : ''} data-x="pquiz" data-id="${p.id}" data-v="${i}">${esc(o)}</button>`).join('')}${done ? `<p class="small"><b>${ans === p.a ? 'Acertou! 🎉' : 'Quase!'}</b> ${esc(p.exp)}</p>` : ''}</div>${acts(p)}`);
    }
    case 'me': {
      const t = todayStr(), s = computeStreak();
      return P(`${head('me', 'Hoje')}<div class="pbody"><h3>${s} ${s === 1 ? 'dia' : 'dias'} de sequência</h3><p>Hoje: ${goalVal(t)} de ${state.settings.dailyGoal} ${unitLabel()}. ${goalMet(t) ? 'Meta cumprida!' : 'Um pouco de leitura mantém o fogo aceso.'}</p><button class="btn sm primary" data-x="go" data-v="today">Registrar leitura</button></div>`);
    }
    case 'cont': {
      const b = state.books.find(x => x.id === p.bid); if (!b) return '';
      return P(`${head('me', 'Continue de onde parou')}<div class="pbody"><h3>${esc(b.title)}</h3><p class="muted small">${esc(b.author)}</p><button class="btn sm primary" data-x="read" data-id="${b.id}">Continuar lendo</button></div>`);
    }
    case 'carousel': return P(`${head('book', p.title)}<div class="hscroll">${p.books.map(tile).join('')}</div>`);
    case 'book': {
      const g = p.books[0];
      return P(`${head('book', p.title)}<div class="fbook">${coverHtml(g)}<div><h3 style="margin:0">${esc(g.title)}</h3><div class="muted small">${esc(g.author)}${g.lang ? ' · ' + esc(g.lang.toUpperCase()) : ''}</div><p class="small">Muito lido no Projeto Gutenberg (${g.downloads.toLocaleString('pt-BR')} downloads).</p><div class="bookact">${tileAct(g)}</div></div></div>`);
    }
  }
  return '';
}

/* ---------- feed Para você ---------- */
const feed = { status: 'idle', items: [], filter: '', seed: 0, shown: new Set(), quiz: {}, error: '', byId: {} };
function contentPool() {
  ensure();
  if (feed.filter === 'saved') return CONTENT.filter(p => state.saved[p.id]);
  const mine = new Set((state.profile && state.profile.genres) || []);
  const pick = () => CONTENT.filter(p => !feed.shown.has(p.id) && (!feed.filter || p.g.includes(feed.filter) || !p.g.length));
  let it = pick();
  if (!it.length) { feed.shown.clear(); it = pick(); }
  return it.map(p => [(p.g.some(x => mine.has(x)) ? 2 : 0) + (p.g.length ? 0 : .8) + Math.random() * 1.6, p]).sort((a, b) => b[0] - a[0]).map(x => x[1]);
}
async function fetchSections() {
  const prof = state.profile || {}, langs = userLangs().join(',');
  const ids = (feed.filter && feed.filter !== 'saved') ? [feed.filter] : ((prof.genres && prof.genres.length) ? prof.genres : ['classics']);
  const gs = shuffle(ids.map(id => GENRES.find(g => g.id === id)).filter(Boolean)).slice(0, 3);
  const run = (title, params) => {
    const p2 = feed.seed ? Object.assign({}, params, { page: 1 + Math.floor(Math.random() * 4) }) : params;
    return fetchList(p2).catch(() => fetchList(params)).then(items => ({ title, items })).catch(() => ({ title, items: [], failed: true }));
  };
  const jobs = gs.map(g => run(g.id === 'classics' ? 'Clássicos mais lidos no seu idioma' : 'Porque você gosta de ' + g.label, { languages: langs, topic: g.topic }));
  const fans = state.books.filter(b => b.status === 'finished' && b.rating >= 4 && b.author && b.gid);
  if (fans.length && !feed.filter) { const f = shuffle(fans)[0]; jobs.push(run('Mais de ' + f.author + ', que você avaliou bem', { search: f.author, languages: langs })); }
  return Promise.all(jobs);
}
async function loadFeed(append) {
  feed.status = 'loading'; feed.error = '';
  if (!append) feed.items = [];
  render();
  let secs = [];
  if (feed.filter !== 'saved') { try { secs = await fetchSections(); } catch (e) { secs = []; } }
  const failed = secs.length > 0 && secs.every(s => s.failed);
  const seen = new Set();
  feed.items.forEach(p => (p.books || []).forEach(b => seen.add(b.gid)));
  const books = [];
  secs.forEach(s => {
    const its = s.items.filter(b => !seen.has(b.gid));
    if (!its.length) return;
    its.forEach(b => seen.add(b.gid));
    books.push({ id: 'c' + uid(), kind: 'carousel', title: s.title, books: its.slice(0, 8) });
    if (its[8]) books.push({ id: 'b' + its[8].gid, kind: 'book', title: s.title, books: [its[8]] });
  });
  const pool = contentPool(), out = [];
  if (!append && feed.filter !== 'saved') {
    const cur = state.books.filter(b => b.gid && b.status === 'reading').sort((a, b) => (b.lastRead || 0) - (a.lastRead || 0))[0];
    if (cur) out.push({ id: 'cont', kind: 'cont', bid: cur.id });
    if (!feed.filter) out.push({ id: 'me', kind: 'me' });
  }
  const take = n => { for (let i = 0; i < n && pool.length; i++) { const p = pool.shift(); feed.shown.add(p.id); out.push(p); } };
  if (feed.filter === 'saved') take(99);
  else { take(2); books.forEach(b => { out.push(b); take(2); }); take(books.length ? 3 : 8); }
  feed.items = feed.items.concat(out);
  feed.items.forEach(p => { feed.byId[p.id] = p; });
  if (failed) feed.error = 'Sem internet (ou o catálogo está fora do ar): mostrando só os conteúdos do feed.';
  feed.status = 'done';
  render();
}
function renderForYou2() {
  ensure();
  if (feed.status === 'idle') { feed.status = 'loading'; setTimeout(() => loadFeed(false), 0); }
  const mine = ((state.profile && state.profile.genres) || []).slice(0, 8);
  const ids = mine.length ? mine : ['classics', 'mystery', 'romance', 'adventure', 'scifi'];
  const st = [['', '✨', 'Tudo']].concat(ids.map(id => [id, GEMO[id] || '📖', (genreLabel(id) || id).split(' ')[0]])).concat([['saved', '🔖', 'Salvos']]);
  const stories = st.map(([id, e, l]) => `<button class="story ${feed.filter === id ? 'on' : ''}" data-x="pfilter" data-id="${id}"><div class="ring2"><div class="in">${e}</div></div>${esc(l)}</button>`).join('');
  return `<div class="feed">
    <form id="feedSearch" class="fsearch"><input id="feedQ" type="search" placeholder="Pesquisar livros ou autores…" autocomplete="off"><button class="btn primary" type="submit">Buscar</button></form>
    <div class="stories">${stories}</div>
    ${feed.error ? `<div class="card muted small">${esc(feed.error)}</div>` : ''}
    ${feed.items.map(postHtml).join('')}
    ${feed.status === 'loading' ? '<p class="empty">Montando seu feed…</p>' : ''}
    ${feed.status === 'done' && feed.filter === 'saved' && !feed.items.length ? '<div class="card empty">Você ainda não salvou nada. Toque em 🔖 Salvar nos posts.</div>' : ''}
    ${feed.status === 'done' && feed.filter !== 'saved' ? '<p class="center"><button class="btn" data-x="pmore">Ver mais</button> <button class="btn" data-x="prefresh">Atualizar feed</button></p>' : ''}
    <p class="center"><button class="btn sm" data-x="retake">Mudar gostos</button></p></div>`;
}

/* ---------- aba Pesquisar ---------- */
const SUGG = ['Machado de Assis', 'Sherlock Holmes', 'Dom Casmurro', 'Jane Austen', 'Drácula', 'Edgar Allan Poe', 'Júlio Verne', 'Shakespeare'];
function addRecent(q) {
  q = (q || '').trim(); if (q.length < 2) return;
  ensure(); state.recent = [q].concat(state.recent.filter(x => x.toLowerCase() !== q.toLowerCase())).slice(0, 8); Store.save(state);
}
function searchFor(q, langs) {
  lib.q = q; lib.lang = langs || ''; lib.topic = ''; lib.started = true; view = 'library';
  addRecent(q); render(); window.scrollTo(0, 0); libSearch(true);
}
function resRow(g) {
  return `<article class="srow">${coverHtml(g)}<div style="min-width:0"><h4>${esc(g.title)}</h4><div class="muted">${esc(g.author)}${g.lang ? `<span class="tag">${esc(g.lang.toUpperCase())}</span>` : ''}</div><div class="muted">${g.downloads.toLocaleString('pt-BR')} downloads</div><div class="bookact">${tileAct(g)}</div></div></article>`;
}
function libResults() {
  ensure();
  const q = lib.q.trim().toLowerCase();
  const chips = GENRES.filter(g => g.topic).map(g => `<button class="gchip ${lib.topic === g.topic ? 'on' : ''}" data-x="libtopic" data-id="${esc(g.topic)}">${esc(g.label)}</button>`).join('');
  const chipQ = a => a.map(s => `<button class="gchip" data-x="psearch" data-q="${esc(s)}">${esc(s)}</button>`).join('');
  const mine = q ? state.books.filter(b => (b.title + ' ' + (b.author || '')).toLowerCase().includes(q)) : [];
  return `<div class="gchips" style="margin:0 0 1rem">${chips}</div>
  ${!q ? `${state.recent.length ? `<p class="muted small" style="margin:.2rem 0">Pesquisas recentes</p><div class="gchips" style="margin:0 0 .8rem">${chipQ(state.recent)}</div>` : ''}<p class="muted small" style="margin:.2rem 0">Sugestões</p><div class="gchips" style="margin:0 0 1rem">${chipQ(SUGG)}</div>` : ''}
  ${mine.length ? `<h3 class="sechead">Na sua estante</h3><div class="srows">${mine.map(b => `<article class="srow"><div style="min-width:0"><h4>${esc(b.title)}</h4><div class="muted">${esc(b.author || '')}</div>${b.gid ? `<div class="bookact"><button class="btn sm primary" data-x="read" data-id="${b.id}">${b.currentPage > 0 ? 'Continuar' : 'Ler'}</button></div>` : ''}</div></article>`).join('')}</div>` : ''}
  ${lib.error ? `<div class="card empty">${esc(lib.error)}<br><br><button class="btn" data-x="libretry">Tentar de novo</button></div>` : ''}
  ${lib.items.length ? `<h3 class="sechead">${q ? 'Resultados' : 'Em alta na biblioteca'}${lib.total ? ` <span class="muted small">(${lib.total.toLocaleString('pt-BR')})</span>` : ''}</h3><div class="srows">${lib.items.map(resRow).join('')}</div>` : ''}
  ${lib.loading ? '<p class="empty">Buscando…</p>' : ''}
  ${!lib.loading && !lib.error && !lib.items.length ? '<div class="card empty">Nenhum livro encontrado. Tente outro título, o sobrenome do autor ou outro idioma.</div>' : ''}
  ${lib.hasMore && !lib.loading ? '<p class="center"><button class="btn" data-x="libmore">Carregar mais</button></p>' : ''}`;
}
function libPaint() {
  if (view !== 'library') return;
  const el = $('#sres'); if (el) el.innerHTML = libResults(); else render();
}
libSearch = async function (reset) {
  const my = ++lib.req;
  if (reset) { lib.page = 1; lib.items = []; }
  lib.loading = true; lib.error = ''; libPaint();
  try {
    const params = { page: lib.page };
    if (lib.q.trim()) params.search = lib.q.trim();
    const langs = lib.lang === 'mine' ? userLangs().join(',') : lib.lang;
    if (langs) params.languages = langs;
    if (lib.topic) params.topic = lib.topic;
    const data = await gutendex(params);
    if (my !== lib.req) return;
    lib.items = lib.items.concat((data.results || []).map(normBook).filter(b => b.textUrl));
    lib.hasMore = !!data.next; lib.total = data.count || 0;
  } catch (e) { if (my !== lib.req) return; lib.error = e.message; }
  lib.loading = false; libPaint();
};
function renderLibrary2() {
  if (!lib.started) { lib.started = true; setTimeout(() => libSearch(true), 0); }
  const langOpts = [['mine', 'Meus idiomas'], ['', 'Todos']].concat(LANGS.map(l => [l.id, l.label])).map(([v, l]) => `<option value="${v}" ${lib.lang === v ? 'selected' : ''}>${l}</option>`).join('');
  return `<section class="card"><h2>Pesquisar livros</h2>
    <p class="muted small" style="margin-top:0">Busque por título ou autor na biblioteca virtual (Projeto Gutenberg). Livros gratuitos para ler aqui dentro, com o progresso salvo.</p>
    <form id="libForm" class="row"><label style="flex:3">Título ou autor<input id="libQ" type="search" data-xin="libq" value="${esc(lib.q)}" placeholder="ex.: Machado de Assis, Dom Casmurro, Sherlock" autocomplete="off"></label>
    <label>Idioma<select data-xin="liblang">${langOpts}</select></label><button class="btn primary" type="submit">Buscar</button></form></section>
  <div id="sres">${libResults()}</div>`;
}

/* ---------- ligação com o app ---------- */
VIEWS.foryou = renderForYou2;
VIEWS.library = renderLibrary2;
const _finishOnb = finishOnb;
finishOnb = function () { feed.status = 'idle'; feed.items = []; feed.filter = ''; feed.shown.clear(); feed.seed = 0; _finishOnb(); };

document.addEventListener('click', e => {
  const el = e.target.closest('[data-x]'); if (!el) return;
  const x = el.dataset.x, id = el.dataset.id;
  switch (x) {
    case 'pfilter': feed.filter = id; feed.seed++; loadFeed(false); break;
    case 'pmore': feed.seed++; loadFeed(true); break;
    case 'prefresh': feed.seed++; feed.shown.clear(); loadFeed(false); break;
    case 'plike': case 'psave': {
      ensure(); const m = x === 'plike' ? state.likes : state.saved;
      if (m[id]) delete m[id]; else m[id] = 1;
      Store.save(state);
      const p = feed.byId[id] || CONTENT.find(c => c.id === id), art = el.closest('.post');
      if (art && p) art.querySelector('.pact').outerHTML = acts(p);
      const nb = art && art.querySelector('.pbtn.on[data-x="' + x + '"]'); if (nb) nb.classList.add('just');
      break;
    }
    case 'pcopy': {
      const p = CONTENT.find(c => c.id === id); if (!p) break;
      try { navigator.clipboard.writeText('“' + p.text + '” — ' + p.by + ', ' + p.work); toast('Frase copiada.'); } catch (err) { toast('Não consegui copiar.'); }
      break;
    }
    case 'pquiz': {
      feed.quiz[id] = Number(el.dataset.v);
      const p = feed.byId[id], art = el.closest('.post');
      if (p && art) art.outerHTML = postHtml(p);
      break;
    }
    case 'psearch': searchFor(el.dataset.q, ''); break;
  }
});
document.addEventListener('submit', e => {
  if (e.target.id === 'feedSearch') searchFor($('#feedQ').value.trim(), '');
  else if (e.target.id === 'libForm') addRecent(lib.q);
});
document.addEventListener('input', e => {
  if (e.target.dataset && e.target.dataset.xin === 'libq') {
    clearTimeout(lib.dt);
    lib.dt = setTimeout(() => { if (view === 'library') libSearch(true); }, 550);
  }
});
render();
</script>
<style>
:root{--sh:0 1px 2px rgba(60,35,15,.06),0 8px 24px -12px rgba(60,35,15,.25);--sh2:0 2px 4px rgba(60,35,15,.08),0 20px 38px -16px rgba(60,35,15,.4);--ease:cubic-bezier(.2,.7,.2,1)}
:root.escuro{--sh:0 1px 2px rgba(0,0,0,.4),0 8px 24px -12px rgba(0,0,0,.7);--sh2:0 2px 4px rgba(0,0,0,.5),0 20px 38px -16px rgba(0,0,0,.9)}
*{scrollbar-width:thin;scrollbar-color:var(--line) transparent}
body{background:radial-gradient(900px 420px at 8% -8%,color-mix(in srgb,var(--accent) 14%,transparent),transparent 70%),radial-gradient(700px 380px at 100% 0,color-mix(in srgb,var(--warn) 10%,transparent),transparent 70%),var(--bg)}
header{background:var(--card);box-shadow:0 1px 0 var(--line)}
.brand{background:linear-gradient(90deg,var(--accent),var(--warn));-webkit-background-clip:text;background-clip:text;color:transparent;font-size:1.65rem}
.tab{transition:color .2s,background .25s,transform .2s,box-shadow .25s}
.tab:hover{transform:translateY(-1px)}
.tab.on{box-shadow:0 8px 18px -8px var(--accent)}
.card,.post,.tile,.stat,.srow{box-shadow:var(--sh);border-radius:18px}
.tile,.srow,.stat,.post{transition:transform .35s var(--ease),box-shadow .35s var(--ease),border-color .3s}
.tile:hover,.srow:hover,.stat:hover{transform:translateY(-4px);box-shadow:var(--sh2);border-color:color-mix(in srgb,var(--accent) 50%,var(--line))}
.btn{transition:transform .15s,box-shadow .2s,border-color .2s,background .2s}
.btn:hover{transform:translateY(-1px)}
.btn:active{transform:scale(.96)}
.btn.primary{background:linear-gradient(180deg,color-mix(in srgb,var(--accent) 86%,#fff),var(--accent));box-shadow:0 8px 16px -8px var(--accent)}
.btn.primary:hover{box-shadow:0 12px 22px -8px var(--accent)}
.gchip{transition:transform .15s,background .2s,border-color .2s,box-shadow .2s}
.gchip:hover{transform:translateY(-1px)}
.gchip.on{box-shadow:0 6px 14px -6px var(--accent)}
.prog>i{background:linear-gradient(90deg,var(--accent),var(--warn))}
.story .ring2{transition:transform .25s var(--ease)}
.story:hover .ring2{transform:scale(1.08)}
.hscroll{scrollbar-width:none}
/* animações de entrada (só ao trocar de tela) */
@keyframes fadeUp{from{opacity:0;transform:translateY(14px)}}
@keyframes pop{0%{transform:scale(.4)}60%{transform:scale(1.2)}100%{transform:scale(1)}}
@keyframes shimmer{to{background-position:-200% 0}}
@keyframes dlg{from{opacity:0;transform:translateY(14px) scale(.97)}}
@keyframes fade{from{opacity:0}}
@keyframes pageIn{from{opacity:0;transform:translateX(12px)}}
#main.enter>*:not(.feed),#main.enter .feed>*,#main.enter #sres>*{animation:fadeUp .55s var(--ease) both}
#main.enter .bgrid .tile,#main.enter .cards .stat{animation:fadeUp .5s var(--ease) both}
#main.enter .dot.done{animation:pop .5s var(--ease) both}
.srow{animation:fadeUp .35s var(--ease) both}
dialog[open]{animation:dlg .28s var(--ease)}
dialog[open]::backdrop{animation:fade .28s}
.rbody article{animation:pageIn .4s var(--ease)}
.pbtn.just{animation:pop .45s var(--ease)}
.qopt.right{animation:pop .4s var(--ease)}
#toast{transform:translate(-50%,14px);transition:opacity .3s,transform .3s var(--ease);box-shadow:var(--sh2)}
#toast.show{transform:translate(-50%,0)}
/* capas */
.cover{display:block;padding:0;border-radius:6px;background:linear-gradient(135deg,hsl(var(--h,20) 45% 38%),hsl(calc(var(--h,20) + 30) 45% 22%));box-shadow:0 12px 20px -10px rgba(0,0,0,.55),0 2px 4px rgba(0,0,0,.25);transition:transform .4s var(--ease),box-shadow .4s}
.srow .cover,.fbook .cover,.bcov .cover{padding:0}
.cover::after{content:'';position:absolute;inset:0;border-radius:inherit;pointer-events:none;z-index:2;background:linear-gradient(90deg,rgba(255,255,255,.3) 0,rgba(255,255,255,.08) 3.5%,rgba(0,0,0,.2) 5.5%,transparent 11%,transparent 88%,rgba(0,0,0,.16))}
.tile:hover .cover,.srow:hover .cover{transform:translateY(-3px) rotate(-1.2deg) scale(1.03);box-shadow:0 18px 26px -10px rgba(0,0,0,.6)}
.cfb{position:absolute;inset:0;display:flex;flex-direction:column;justify-content:space-between;padding:13% 11% 10% 17%;color:#fff;text-align:left}
.cfb i{display:block;width:34%;border-top:2px solid rgba(255,255,255,.55)}
.cfb b{font:700 1em/1.2 Georgia,serif;display:-webkit-box;-webkit-line-clamp:5;-webkit-box-orient:vertical;overflow:hidden;margin:.5em 0 auto}
.cfb small{font-size:.74em;opacity:.8;letter-spacing:.04em;text-transform:uppercase;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.cover img{position:absolute;inset:0;width:100%;height:100%;object-fit:cover;opacity:0;transition:opacity .6s;z-index:1}
.cover img.in{opacity:1}
.cover.load::before{content:'';position:absolute;inset:0;z-index:3;border-radius:inherit;background:linear-gradient(110deg,transparent 30%,rgba(255,255,255,.28) 50%,transparent 70%);background-size:200% 100%;animation:shimmer 1.3s linear infinite}
.card.book.withcov{display:grid;grid-template-columns:76px 1fr;column-gap:1rem;align-items:start}
.card.book.withcov .bcov{grid-row:1/span 9;font-size:.6rem}
.card.book.withcov .bcov .cover{margin:0}
.card.book.withcov>.bmain{min-width:0}
/* carregando */
.skel{padding:.9rem 1rem}
.sk{height:12px;border-radius:8px;margin:.65rem 0;background:linear-gradient(90deg,var(--track) 25%,color-mix(in srgb,var(--track) 45%,var(--card)) 50%,var(--track) 75%);background-size:200% 100%;animation:shimmer 1.4s linear infinite}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important}}
</style>
<script>
/* ====================================================================
   PARTE 4: capas reais (Open Library), carregamento elegante e animações
   ==================================================================== */
const CVINFO = {}, cvQ = [], cvPending = new Set();
let cvBusy = 0;
const CV = (() => { try { return JSON.parse(localStorage.getItem('paginas.cv') || '{}'); } catch (e) { return {}; } })();
const cvSave = () => { try { localStorage.setItem('paginas.cv', JSON.stringify(CV)); } catch (e) {} };
const cleanTitle = t => String(t || '').split(/[:;—–]|\s\/\s|\s-\s/)[0].replace(/\(.*?\)/g, '').replace(/\s+/g, ' ').trim();
const cleanAuthor = a => (!a || a === 'Autor desconhecido') ? '' : String(a).replace(/\(.*?\)/g, '').replace(/\s+/g, ' ').trim();

function cv(g) {
  CVINFO[g.gid] = { gid: g.gid, title: g.title, author: g.author };
  return `<div class="cover" data-cv="${g.gid}" style="--h:${hue(g.gid + g.title)}"><div class="cfb"><i></i><b>${esc(g.title)}</b><small>${esc(g.author || '')}</small></div></div>`;
}
coverHtml = cv;
tile = function (g) {
  return `<article class="tile">${cv(g)}<div class="tt" title="${esc(g.title)}">${esc(g.title)}</div>
    <div class="au">${esc(g.author)}${g.lang ? `<span class="tag">${esc(g.lang.toUpperCase())}</span>` : ''}</div><div class="tact">${tileAct(g)}</div></article>`;
};
const _bookCard = bookCard;
bookCard = function (b) {
  const h = _bookCard(b), k = '<article class="card book">', i = h.lastIndexOf('</article>');
  if (!b.gid || !h.startsWith(k) || i < 0) return h;
  return '<article class="card book withcov"><div class="bcov">' + cv(b) + '</div><div class="bmain">' + h.slice(k.length, i) + '</div></article>';
};

async function cvFind(g) {
  const t = cleanTitle(g.title); if (!t) return '';
  const a = cleanAuthor(g.author);
  const r = await api('/api/cover?title=' + encodeURIComponent(t) + (a ? '&author=' + encodeURIComponent(a) : ''));
  const d = await r.json();
  const hit = (d.docs || []).find(x => x.cover_i);
  return hit ? 'https://covers.openlibrary.org/b/id/' + hit.cover_i + '-M.jpg?default=false' : '';
}
function setCover(el, url) {
  const key = el.dataset.cv, img = new Image();
  img.alt = ''; img.referrerPolicy = 'no-referrer';
  img.onload = () => { el.appendChild(img); requestAnimationFrame(() => img.classList.add('in')); };
  img.onerror = () => { if (CV[key] === url) { CV[key] = ''; cvSave(); } };
  img.src = url;
}
function applyCover(key) {
  const url = CV[key];
  document.querySelectorAll('.cover[data-cv="' + key + '"]').forEach(el => {
    el.classList.remove('load');
    if (url && !el.querySelector('img')) setCover(el, url);
  });
}
function cvPump() {
  while (cvBusy < 3 && cvQ.length) {
    const g = cvQ.shift(); cvBusy++;
    cvFind(g).catch(() => null).then(url => {
      cvBusy--;
      if (url !== null) { CV[g.gid] = url; cvSave(); }
      cvPending.delete(String(g.gid));
      applyCover(String(g.gid));
      cvPump();
    });
  }
}
function hydrateCovers() {
  if (!IS_APP) return;
  document.querySelectorAll('.cover[data-cv]:not([data-done])').forEach(el => {
    el.dataset.done = '1';
    const key = el.dataset.cv, g = CVINFO[key]; if (!g) return;
    if (key in CV) { if (CV[key]) setCover(el, CV[key]); return; }
    el.classList.add('load');
    if (!cvPending.has(key)) { cvPending.add(key); cvQ.push(g); cvPump(); }
  });
}

/* ---------- esqueletos de carregamento ---------- */
const SKEL = '<div class="post skel"><div class="sk" style="width:40%"></div><div class="sk"></div><div class="sk" style="width:85%"></div><div class="sk" style="width:60%"></div></div>'.repeat(2);
const _forYou = renderForYou2;
VIEWS.foryou = () => _forYou().replace('<p class="empty">Montando seu feed…</p>', SKEL);
const _libRes = libResults;
libResults = function () { return _libRes().replace('<p class="empty">Buscando…</p>', '<div class="srows">' + '<div class="srow skel" style="flex-direction:column;gap:.2rem"><div class="sk" style="width:50%"></div><div class="sk" style="width:30%"></div></div>'.repeat(3) + '</div>'); };
const _libPaint = libPaint;
libPaint = function () { _libPaint(); hydrateCovers(); };

/* ---------- animação de entrada ao trocar de tela ---------- */
let _sig = '', _enterT;
const _r4 = render;
render = function () {
  _r4();
  const sig = view + (view === 'foryou' ? '|' + (feed.items.length ? 'i' : 'e') : '');
  const m = $('#main');
  if (sig !== _sig) {
    _sig = sig; m.classList.remove('enter'); void m.offsetWidth; m.classList.add('enter');
    clearTimeout(_enterT); _enterT = setTimeout(() => m.classList.remove('enter'), 1300);
  }
  hydrateCovers();
};
(function () { let s = ''; for (let i = 2; i <= 9; i++) s += `#main.enter .feed>:nth-child(${i}),#main.enter #sres>:nth-child(${i}),#main.enter>:nth-child(${i}):not(.feed){animation-delay:${(i - 1) * 55}ms}`; s += '#main.enter .bgrid .tile:nth-child(n){animation-delay:.12s}'; const st = document.createElement('style'); st.textContent = s; document.head.appendChild(st); })();
render();
</script>
<style>
.brgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,430px),1fr));gap:1rem}
.brc{display:flex;gap:1rem;padding:1rem;margin:0}
.brc .cover{width:96px;flex:none;margin:0;font-size:.64rem}
.brc .brm{min-width:0;display:flex;flex-direction:column}
.brc h3{font-size:1.1rem;margin:.1rem 0 0}
.brth{font-size:.72rem;font-weight:700;color:var(--accent);text-transform:uppercase;letter-spacing:.07em}
.brc .by{color:var(--muted);font-size:.85rem;margin-bottom:.4rem}
.brc p{margin:0 0 .6rem;font-size:.9rem}
.bdgs{display:flex;gap:.35rem;flex-wrap:wrap;margin-bottom:.6rem}
.bdg{font-size:.7rem;font-weight:700;border-radius:999px;padding:.1rem .6rem;border:1px solid var(--line);color:var(--muted)}
.bdg.v{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}
.bract{margin-top:auto;display:flex;gap:.4rem;flex-wrap:wrap;align-items:center}
#main.enter #brgrid>*{animation:fadeUp .5s var(--ease) both}
</style>
<script>
/* ====================================================================
   PARTE 5: aba Brasil (um livro para cada tema)
   ==================================================================== */
const norm = s => String(s || '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
/* id, tema, emoji, título, autor, ano, termo p/ achar no catálogo, ainda protegido?, selo de vestibular 2027, por que ler */
const BRB = [
  { id: 'dc', th: 'Realismo', e: '🎩', t: 'Dom Casmurro', a: 'Machado de Assis', y: 1899, mt: 'dom casmurro', v: '', why: 'Bentinho jura que Capitu o traiu com o melhor amigo. O livro nunca confirma, e a dúvida rende debate há mais de um século.' },
  { id: 'mp', th: 'Ironia e humor', e: '⚰️', t: 'Memórias Póstumas de Brás Cubas', a: 'Machado de Assis', y: 1881, mt: 'bras cubas', v: 'Unicentro 2027', why: 'Quem conta a história é um defunto, e sem nenhuma pressa de ser simpático. Sátira afiada da elite do Império.' },
  { id: 'oc', th: 'Naturalismo', e: '🏘️', t: 'O Cortiço', a: 'Aluísio Azevedo', y: 1890, mt: 'cortico', v: '', why: 'O cortiço é o grande personagem: ambição, miséria e desejo num mesmo quintal do Rio de Janeiro.' },
  { id: 'ir', th: 'Indianismo', e: '🌿', t: 'Iracema', a: 'José de Alencar', y: 1865, mt: 'iracema', v: '', why: 'A “lenda do Ceará”: o amor entre a indígena Iracema e o colonizador Martim, escrito como poema em prosa.' },
  { id: 'lu', th: 'Epopeia', e: '⛵', t: 'Os Lusíadas', a: 'Luís de Camões', y: 1572, mt: 'lusiadas', v: '', why: 'O grande poema épico em língua portuguesa, sobre a viagem de Vasco da Gama à Índia.' },
  { id: 'ef', th: 'Poesia romântica', e: '🪶', t: 'Espumas Flutuantes', a: 'Castro Alves', y: 1870, mt: 'espumas flutuantes', v: '', why: 'Único livro que Castro Alves publicou em vida: poesia de amor e de natureza, de um poeta que ficou famoso como voz abolicionista.' },
  { id: 'pq', th: 'Crítica social', e: '🇧🇷', t: 'Triste Fim de Policarpo Quaresma', a: 'Lima Barreto', y: 1915, mt: 'policarpo quaresma', v: '', why: 'Um patriota exagerado e idealista esbarra na realidade do país. Lima Barreto também está na lista da UFSC 2027, com Clara dos Anjos.' },
  { id: 'os', th: 'Reportagem e história', e: '🏜️', t: 'Os Sertões', a: 'Euclides da Cunha', y: 1902, mt: 'sertoes', v: '', why: 'Nascido da cobertura da Guerra de Canudos, une jornalismo, ciência e literatura numa obra monumental.' },
  { id: 'vs', th: 'Regionalismo', e: '🌵', t: 'Vidas Secas', a: 'Graciliano Ramos', y: 1938, mt: 'vidas secas', v: '', why: 'A família de Fabiano foge da seca no sertão. Prosa seca e enxuta, com a cachorra Baleia como um dos personagens mais lembrados.' },
  { id: 'ma', th: 'Modernismo', e: '🎭', t: 'Macunaíma', a: 'Mário de Andrade', y: 1928, mt: 'macunaima', v: '', why: 'O “herói sem nenhum caráter” mistura lendas indígenas, humor e o Brasil de várias línguas e culturas.' },
  { id: 'gs', th: 'Sertão e linguagem', e: '🐎', t: 'Grande Sertão: Veredas', a: 'Guimarães Rosa', y: 1956, c: true, v: '', why: 'O ex-jagunço Riobaldo conta sua vida num monólogo que reinventa a língua portuguesa.' },
  { id: 'ca', th: 'Realismo social', e: '🌆', t: 'Capitães da Areia', a: 'Jorge Amado', y: 1937, c: true, v: '', why: 'Meninos de rua que vivem num trapiche abandonado em Salvador, entre a violência e a vontade de liberdade.' },
  { id: 'gh', th: 'Introspecção', e: '🪲', t: 'A Paixão Segundo G.H.', a: 'Clarice Lispector', y: 1964, c: true, v: 'Fuvest e UFSC 2027', why: 'Uma mulher entra no quarto da empregada e encontra uma barata. O encontro vira uma crise sobre quem ela é. Seu livro mais popular é A Hora da Estrela.' },
  { id: 'ac', th: 'Teatro', e: '🎪', t: 'Auto da Compadecida', a: 'Ariano Suassuna', y: 1955, c: true, v: '', why: 'João Grilo e Chicó, dois pobres espertos do sertão, enfrentam padre, bispo, cangaceiros e até o Diabo.' },
  { id: 'ai', th: 'Memória e ditadura', e: '📷', t: 'Ainda Estou Aqui', a: 'Marcelo Rubens Paiva', y: 2015, c: true, v: 'UERJ 2027', why: 'O filho conta como a mãe, Eunice, reconstruiu a vida depois do desaparecimento do pai durante a ditadura militar.' },
  { id: 'mm', th: 'Autoria feminina', e: '✒️', t: 'Memórias de Martha', a: 'Júlia Lopes de Almeida', y: 1899, mt: 'martha', v: 'Fuvest 2027', why: 'Romance de 1899 que está na lista da Fuvest 2027, um ciclo que reúne só autoras de língua portuguesa.' },
  { id: 'rn', th: 'Infantil', e: '🧸', t: 'Reinações de Narizinho', a: 'Monteiro Lobato', y: 1931, mt: 'narizinho', v: '', why: 'A porta de entrada para o Sítio do Picapau Amarelo, com Emília, Visconde e a imaginação sem limite.' }
];
const BR = { started: false, filter: 'all', res: {} };

function brAct(b) {
  const r = BR.res[b.id];
  if (b.c) return '<span class="muted small">Obra ainda protegida por direitos autorais.</span>';
  if (r === undefined) return '<span class="muted small">Verificando na biblioteca…</span>';
  if (r > 0) return tileAct({ gid: r });
  return `<span class="muted small">${r === -1 ? 'Sem conexão para verificar.' : 'Não encontrei o texto gratuito.'}</span><button class="btn sm" data-x="psearch" data-q="${esc(b.t)}">Procurar</button>`;
}
function brCard(b, i) {
  const cl = b.y <= 1950;
  return `<article class="card brc" data-br="${b.id}" style="animation-delay:${Math.min(i, 10) * 45}ms">${cv({ gid: 'br_' + b.id, title: b.t, author: b.a })}
    <div class="brm"><div class="brth">${b.e} ${esc(b.th)}</div><h3>${esc(b.t)}</h3><div class="by">${esc(b.a)} · ${b.y}</div>
    <div class="bdgs">${b.v ? `<span class="bdg v">${esc(b.v)}</span>` : ''}${cl ? '<span class="bdg">Clássico</span>' : ''}</div>
    <p>${esc(b.why)}</p><div class="bract">${brAct(b)}</div></div></article>`;
}
function brList() {
  const f = BR.filter;
  return BRB.filter(b => f === 'all' || (f === 'v' && b.v) || (f === 'c' && b.y <= 1950));
}
function renderBrasil() {
  if (!BR.started) { BR.started = true; setTimeout(brResolveAll, 0); }
  const fl = [['all', 'Todos'], ['v', 'Vestibular 2027'], ['c', 'Clássicos']].map(([k, l]) => `<button class="gchip ${BR.filter === k ? 'on' : ''}" data-x="brfilter" data-id="${k}">${l}</button>`).join('');
  return `<section class="card"><h2>Brasil: um livro para cada tema</h2>
    <p class="muted small" style="margin-top:0">Obras de referência da nossa literatura, dos clássicos que atravessam gerações às leituras cobradas nos vestibulares. Quando o texto é de domínio público e está na biblioteca gratuita, dá para ler aqui dentro.</p>
    <div class="gchips" style="margin-top:.4rem">${fl}</div>
    <p class="muted small" style="margin:.8rem 0 0">Selos de 2027 seguem as listas divulgadas por Fuvest, UFSC, UERJ e Unicentro. As listas mudam todo ano, então confira o edital da sua prova.</p></section>
  <div class="brgrid" id="brgrid">${brList().map(brCard).join('')}</div>`;
}
async function brResolve(b) {
  if (b.c || BR.res[b.id] !== undefined) return;
  const last = norm(b.a.split(' ').pop());
  const find = items => items.find(g => norm(g.title).includes(b.mt) && norm(g.author).includes(last));
  try {
    let hit = find(await fetchList({ search: b.a, languages: 'pt' }));
    if (!hit) hit = find(await fetchList({ search: b.mt }));
    BR.res[b.id] = hit ? hit.gid : 0;
  } catch (e) { BR.res[b.id] = -1; }
  const el = document.querySelector('[data-br="' + b.id + '"] .bract');
  if (el) el.innerHTML = brAct(b);
}
async function brResolveAll() {
  const q = BRB.filter(b => !b.c && BR.res[b.id] === undefined);
  const worker = async () => { while (q.length) await brResolve(q.shift()); };
  await Promise.all([worker(), worker(), worker()]);
}
VIEWS.brasil = renderBrasil;
document.addEventListener('click', e => {
  const el = e.target.closest('[data-x="brfilter"]'); if (!el) return;
  BR.filter = el.dataset.id; render();
  Object.keys(BR.res).forEach(k => { if (BR.res[k] === -1) delete BR.res[k]; });
  brResolveAll();
});
render();
</script>
<style>
:root{--ui:'Nunito',system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;--serif:'Lora',Georgia,'Times New Roman',serif}
body{font-family:var(--ui)}
h1,h2,h3,.brand,.big,.ringtxt b,.stat b,.onbbrand,.pquote p,.cfb b,.cover,.rbody h4{font-family:var(--serif)!important}
.rbody article{font-family:var(--serif)!important}
.hl{background:rgba(255,213,79,.5);color:inherit;border-radius:3px;padding:.05em 0;cursor:pointer;-webkit-box-decoration-break:clone;box-decoration-break:clone}
.hl.has{border-bottom:2px solid var(--accent)}
.reader.th-dark .hl{background:rgba(255,213,79,.28)}
@keyframes sheet{from{opacity:0;transform:translate(-50%,16px)}}
.rtool{position:fixed;z-index:70;display:flex;gap:.2rem;background:#2a2420;color:#fff;border-radius:12px;padding:.3rem;box-shadow:0 12px 28px -8px rgba(0,0,0,.55);animation:pop .25s var(--ease)}
.rtool button{background:none;border:0;color:#fff;font:inherit;font-size:.88rem;font-weight:600;padding:.4rem .7rem;border-radius:8px;cursor:pointer}
.rtool button:hover{background:rgba(255,255,255,.16)}
.hpanel{position:absolute;left:50%;bottom:4.6rem;transform:translateX(-50%);width:min(640px,94vw);max-height:55vh;overflow:auto;z-index:60;background:var(--rbg);color:var(--rink);border:1px solid var(--rline);border-radius:16px;padding:1rem 1.1rem;box-shadow:0 20px 44px -12px rgba(0,0,0,.5);animation:sheet .28s var(--ease)}
.hph{display:flex;justify-content:space-between;align-items:center;margin-bottom:.5rem;font-weight:700}
.hph button{background:none;border:0;color:var(--rmut);font-size:1.4rem;cursor:pointer;line-height:1}
.hpanel blockquote{margin:0 0 .7rem;padding:.3rem .8rem;border-left:3px solid var(--accent);color:var(--rmut);font-style:italic}
.hans{white-space:pre-wrap;line-height:1.6}
.hpa{display:flex;gap:.4rem;flex-wrap:wrap;margin-top:.8rem}
.hli{display:block;width:100%;text-align:left;background:none;border:0;border-top:1px solid var(--rline);padding:.6rem 0;color:var(--rink);cursor:pointer;font:inherit}
.hli small{display:block;color:var(--rmut)}
.gsteps{margin:.4rem 0 .8rem;padding-left:1.2rem;font-size:.88rem;color:var(--muted)}
.gsteps li{margin:.2rem 0}
.gsteps code{background:var(--bg);border:1px solid var(--line);border-radius:6px;padding:0 .3rem}
</style>
<script>
/* ====================================================================
   PARTE 6: grifos com explicação por IA, chave de IA e conta Google
   ==================================================================== */
const CFG = { loaded: false, hasKey: false, googleClientId: '', port: 0 };
async function loadCfg() {
  if (!IS_APP) return;
  try {
    const r = await api('/api/config');
    Object.assign(CFG, await r.json(), { loaded: true });
    if (view === 'settings') render();
  } catch (e) {}
}
async function cfgPost(o) {
  const r = await api('/api/config', { method: 'POST', body: JSON.stringify(o) });
  Object.assign(CFG, await r.json(), { loaded: true });
}
function cfgDo(o, msg) {
  cfgPost(o).then(() => { toast(msg); render(); }).catch(e => toast(e.message));
}

/* ---------- grifos ---------- */
const HS = { sel: null, panel: null, t: null };
const hls = () => (R && R.b.hl) || [];
const flat = x => String(x).replace(/\s+/g, ' ').trim();
const reEsc = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const fmtAns = t => esc(t).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>');

function paraHtml(t, hs, used) {
  const s = esc(t), rs = [];
  for (const h of hs) {
    if (used.has(h.id)) continue;
    const pat = esc(h.text).split(/\s+/).filter(Boolean).map(reEsc).join('\\s+');
    if (!pat) continue;
    let m = null;
    try { m = new RegExp(pat).exec(s); } catch (e) {}
    if (!m) continue;
    const a = m.index, z = a + m[0].length;
    if (rs.some(r => a < r.z && z > r.a)) continue;
    used.add(h.id); rs.push({ a, z, h });
  }
  rs.sort((x, y) => x.a - y.a);
  let out = '', pos = 0;
  for (const r of rs) {
    out += s.slice(pos, r.a) + `<mark class="hl${r.h.note ? ' has' : ''}" data-hid="${r.h.id}">` + s.slice(r.a, r.z) + '</mark>';
    pos = r.z;
  }
  return out + s.slice(pos);
}
function pageBody() {
  if (!R) return '';
  const hs = hls().filter(h => h.page === R.idx), used = new Set();
  return R.pages[R.idx].map(x => x.h ? `<h4>${esc(x.t)}</h4>` : `<p>${paraHtml(x.t, hs, used)}</p>`).join('');
}
function repaintPage() { const a = $('#rbody article'); if (a) a.innerHTML = pageBody(); }
function ctxFor(text, page) {
  const f = (R.pages[page] || []).find(x => flat(x.t).includes(text));
  return f ? flat(f.t).slice(0, 2500) : '';
}
function readerSelection() {
  if (!R) return null;
  const s = getSelection(); if (!s || s.isCollapsed || !s.rangeCount) return null;
  const art = $('#rbody article'); if (!art) return null;
  const rg = s.getRangeAt(0);
  if (!art.contains(rg.commonAncestorContainer)) return null;
  const text = flat(s.toString());
  if (!text || text.length > 600) return null;
  let n = rg.startContainer; n = n.nodeType === 3 ? n.parentElement : n;
  const p = n && n.closest ? n.closest('p, h4') : null;
  return { text, rect: rg.getBoundingClientRect(), ctx: p ? flat(p.textContent).slice(0, 2500) : '', single: !!p && p.contains(rg.endContainer) };
}
function hideTool() { const el = $('#rtool'); if (el) el.remove(); }
function clearSel() { const s = getSelection(); if (s) s.removeAllRanges(); hideTool(); }
function showTool(sel) {
  hideTool();
  const w = 230, rc = sel.rect;
  const left = Math.max(8, Math.min(innerWidth - w - 8, rc.left + rc.width / 2 - w / 2));
  let top = rc.top - 52; if (top < 56) top = rc.bottom + 10;
  const el = document.createElement('div');
  el.id = 'rtool'; el.className = 'rtool';
  el.style.left = left + 'px'; el.style.top = top + 'px';
  el.setAttribute('onmousedown', 'event.preventDefault()');
  el.innerHTML = '<button data-x="hlmark">🖍 Grifar</button><button data-x="hlexplain">✨ Significado</button>';
  $('#reader').appendChild(el);
}
document.addEventListener('selectionchange', () => {
  clearTimeout(HS.t);
  HS.t = setTimeout(() => {
    if (!R) return;
    const s = readerSelection();
    if (s) { HS.sel = s; showTool(s); }
    else { const g = getSelection(); if (!g || g.isCollapsed) hideTool(); }
  }, 200);
});

function addHl(sel, note) {
  if (!sel || !R) return null;
  if (!sel.single) { toast('Grife um trecho dentro de um único parágrafo.'); return null; }
  const b = R.b; b.hl = b.hl || [];
  let h = b.hl.find(x => x.page === R.idx && x.text === sel.text);
  if (h) { if (note) h.note = note; }
  else { h = { id: uid(), page: R.idx, text: sel.text, color: 'y', note: note || '', ts: Date.now() }; b.hl.push(h); }
  Store.save(state);
  return h;
}
async function explain(o) {
  if (!R) return;
  const b = R.b, tok = {};
  HS.panel = { tok, mode: 'one', text: o.text, ctx: o.ctx || '', sel: o.sel || null, hid: o.hid || null, status: 'loading', ans: '', err: '' };
  paintPanel();
  let ans = '', err = '';
  try {
    const r = await api('/api/ai', { method: 'POST', body: JSON.stringify({ text: o.text, context: o.ctx || '', title: b.title, author: b.author }) });
    ans = String((await r.json()).text || '').trim();
    if (!ans) err = 'A IA não devolveu resposta. Tente de novo.';
  } catch (e) { err = e.message; }
  const p = HS.panel; if (!p || p.tok !== tok) return;
  if (err) { p.status = 'error'; p.err = err; }
  else {
    p.status = 'done'; p.ans = ans;
    if (p.hid) { const h = hls().find(x => x.id === p.hid); if (h) { h.note = ans; Store.save(state); repaintPage(); } }
  }
  paintPanel();
}
function openHl(id) {
  const h = hls().find(x => x.id === id); if (!h) return;
  HS.panel = { tok: {}, mode: 'one', text: h.text, ctx: ctxFor(h.text, h.page), sel: null, hid: h.id, status: h.note ? 'done' : 'idle', ans: h.note || '', err: '' };
  paintPanel();
}
function paintPanel() {
  let el = $('#hpanel'); const p = HS.panel;
  if (!p) { if (el) el.remove(); return; }
  if (!el) { el = document.createElement('div'); el.id = 'hpanel'; el.className = 'hpanel'; $('#reader').appendChild(el); }
  let h = '';
  if (p.mode === 'list') {
    const L = hls().slice().sort((a, b) => a.page - b.page || a.ts - b.ts);
    h = `<div class="hph"><span>Seus grifos (${L.length})</span><button data-x="hlclose" aria-label="Fechar">×</button></div>` +
      (L.length ? L.map(x => `<button class="hli" data-x="hlgo" data-id="${x.id}">“${esc(x.text.length > 110 ? x.text.slice(0, 110) + '…' : x.text)}”<small>Página ${x.page + 1}${x.note ? ' · com explicação' : ''}</small></button>`).join('')
        : '<p>Selecione um trecho do livro para grifar ou pedir o significado.</p>');
  } else {
    const q = p.text.length > 300 ? p.text.slice(0, 300) + '…' : p.text;
    let body = '';
    if (p.status === 'loading') body = '<p>Consultando a IA…</p>';
    else if (p.status === 'error') body = `<p>${esc(p.err)}</p>`;
    else if (p.status === 'done') body = `<div class="hans">${fmtAns(p.ans)}</div>`;
    const a = [];
    if (p.status === 'error' && /Configure/.test(p.err)) a.push('<button class="btn sm primary" data-x="hlsettings">Abrir Ajustes</button>');
    if (p.status !== 'loading') a.push(`<button class="btn sm ${p.status === 'idle' ? 'primary' : ''}" data-x="hlagain">✨ ${p.status === 'done' || p.status === 'error' ? 'Explicar de novo' : 'Explicar'}</button>`);
    if (!p.hid && p.sel) a.push('<button class="btn sm primary" data-x="hlsave">🖍 Grifar e guardar</button>');
    if (p.hid) a.push('<button class="btn sm" data-x="hldel">Remover grifo</button>');
    h = `<div class="hph"><span>${p.hid ? 'Trecho grifado' : 'Significado'}</span><button data-x="hlclose" aria-label="Fechar">×</button></div><blockquote>“${esc(q)}”</blockquote>${body}<div class="hpa">${a.join('')}</div>`;
  }
  el.innerHTML = h;
}

const _renderPage6 = renderPage;
renderPage = function () { HS.panel = null; _renderPage6(); };
const _closeReader6 = closeReader;
closeReader = function (a) { HS.panel = null; hideTool(); _closeReader6(a); };

document.addEventListener('keydown', e => {
  if (e.key === 'Escape' && R && (HS.panel || $('#rtool'))) {
    e.stopImmediatePropagation(); e.preventDefault();
    HS.panel = null; paintPanel(); hideTool();
  }
}, true);

/* ---------- Conta Google: login e cópia dos dados no Google Drive (pasta privada do app) ---------- */
const GS = { loaded: false, available: false, connected: false, email: '', name: '', picture: '', busy: false, last: 0, err: '', poll: null };
async function gStatus() {
  if (!IS_APP) return;
  try { Object.assign(GS, await (await api('/api/google/status')).json(), { loaded: true }); } catch (e) {}
}
function quietSave() { Sync.quiet = true; try { Store.save(state); } finally { Sync.quiet = false; } }
function adoptCloud(c) {
  const d = defaults();
  state = Object.assign({}, d, c, { settings: Object.assign({}, d.settings, c.settings || {}), rests: Array.isArray(c.rests) ? c.rests : [] });
  state.syncMod = state.mod || 0;
  quietSave(); _map = null; render();
}
window.Sync = {
  quiet: false, t: null,
  later() { if (!GS.connected || loadFailed) return; clearTimeout(this.t); this.t = setTimeout(() => Sync.push(), 20000); },
  async push() {
    clearTimeout(this.t);
    if (!GS.connected || GS.busy || loadFailed) return false;
    GS.busy = true;
    try {
      state.syncMod = state.mod || 0;
      quietSave();
      await flushSave();
      await api('/api/google/push', { method: 'POST' });
      GS.last = Date.now(); GS.err = '';
      return true;
    } catch (e) { GS.err = e.message; return false; }
    finally { GS.busy = false; if (view === 'settings') render(); }
  },
  async pull(manual) {
    if (!GS.connected || GS.busy || loadFailed) return;
    if (typeof R !== 'undefined' && R) { if (manual) toast('Feche o livro antes de sincronizar.'); return; }
    GS.busy = true;
    let c = null, msg = '', enviar = false;
    try {
      const r = await api('/api/google/pull');
      const txt = r.status === 204 ? '' : await r.text();
      if (txt) { try { c = JSON.parse(txt); } catch (e) {} }
      if (!c || !Array.isArray(c.books)) enviar = true;
      else {
        const cm = c.mod || 0, base = state.syncMod || 0, lm = state.mod || 0;
        const vazio = !state.books.length && !state.logs.length;
        if (cm === lm) { msg = 'Tudo em dia: este aparelho e a sua conta Google têm os mesmos dados.'; if (state.syncMod !== lm) { state.syncMod = lm; quietSave(); } }
        else if (cm > base) {
          if (vazio || lm <= base || confirm('Há mudanças neste aparelho e também na sua conta Google (feitas em outro aparelho).\n\nOK: usar os dados da conta Google.\nCancelar: manter os deste aparelho e enviar para a conta.')) {
            adoptCloud(c); msg = 'Seus dados foram trazidos da conta Google.';
          } else enviar = true;
        } else enviar = true;
      }
      GS.err = '';
    } catch (e) { GS.err = e.message; msg = 'Não consegui sincronizar: ' + e.message; }
    finally { GS.busy = false; }
    if (enviar) { const ok = await Sync.push(); msg = ok ? 'Dados deste aparelho guardados na sua conta Google.' : 'Não consegui sincronizar: ' + GS.err; }
    else GS.last = GS.err ? GS.last : Date.now();
    if (msg && (manual || /trazidos/.test(msg))) toast(msg);
    if (view === 'settings') render();
  }
};
function gConectado() { clearInterval(GS.poll); toast('Conta Google conectada.'); render(); Sync.pull(false); }
async function googleConnect() {
  if (!GS.available) return toast('O login com Google não está ativado nesta cópia do programa.');
  let u = '';
  try { u = (await (await api('/api/google/start')).json()).url; } catch (e) { return toast(e.message); }
  if (APP.plat === 'android') location.href = u;  // abre no navegador do celular (o Google não aceita login dentro do app)
  toast('Continue o login na página do Google que abriu no navegador.');
  const t0 = Date.now();
  clearInterval(GS.poll);
  GS.poll = setInterval(async () => {
    if (Date.now() - t0 > 300000) { clearInterval(GS.poll); return; }
    const antes = GS.connected; await gStatus();
    if (GS.connected && !antes) gConectado();
  }, 2000);
}
window.googleVoltou = async function (qs) {  // Android: o navegador devolve o login para o app
  try { Object.assign(GS, await (await api('/api/google/finish?' + qs)).json(), { loaded: true }); }
  catch (e) { clearInterval(GS.poll); return toast(e.message); }
  if (GS.connected) gConectado();
};
async function googleLogout() {
  if (!confirm('Desconectar a conta Google deste aparelho? Seus dados continuam aqui e também na conta.')) return;
  try { Object.assign(GS, await (await api('/api/google/logout')).json()); } catch (e) { toast(e.message); }
  render();
}

/* ---------- versão e atualização ---------- */
const UPD = { tag: '', notes: '', busy: false };
const verNum = v => String(v || '').replace(/^[vV]/, '').split('.').map(n => parseInt(n, 10) || 0);
function isNewer(a, b) { const x = verNum(a), y = verNum(b); for (let i = 0; i < Math.max(x.length, y.length); i++) { const d = (x[i] || 0) - (y[i] || 0); if (d) return d > 0; } return false; }
const siteUrl = () => { const [o, r] = APP.repo.split('/'); return o && r ? 'https://' + o.toLowerCase() + '.github.io/' + r + '/' : ''; };
async function checkUpdate() {
  if (!IS_APP || !APP.repo) return;
  try {
    const r = await fetch('https://api.github.com/repos/' + APP.repo + '/releases/latest', { headers: { Accept: 'application/vnd.github+json' } });
    if (!r.ok) return;
    const j = await r.json();
    if (j.tag_name && isNewer(j.tag_name, APP.versao)) {
      UPD.tag = j.tag_name; UPD.notes = String(j.body || '').split('\n')[0].slice(0, 160);
      toast('Nova versão do Páginas disponível (' + j.tag_name + '). Veja em Ajustes.');
      if (view === 'settings') render();
    }
  } catch (e) {}
}
async function doUpdate() {
  if (APP.plat === 'android') { location.href = 'https://github.com/' + APP.repo + '/releases/latest/download/Paginas.apk'; toast('Baixando a versão nova. Abra o arquivo para instalar.'); return; }
  if (UPD.busy) return;
  UPD.busy = true; render();
  try {
    await flushSave(); if (GS.connected) await Sync.push();
    await api('/api/atualizar', { method: 'POST' });
    toast('Atualizado! O Páginas vai reabrir na versão nova.');
    setTimeout(() => { try { window.close(); } catch (e) {} }, 1500);
  } catch (e) { UPD.busy = false; toast('Não consegui atualizar: ' + e.message); render(); }
}

/* ---------- Ajustes ---------- */
function settingsAI() {
  if (IS_APP && !CFG.loaded) setTimeout(loadCfg, 0);
  if (IS_APP && !GS.loaded) setTimeout(() => gStatus().then(() => { if (view === 'settings' && GS.loaded) render(); }), 0);
  const status = !IS_APP ? 'disponível só dentro do programa' : !CFG.loaded ? 'verificando…' : CFG.hasKey ? '✅ usando a sua chave da Anthropic' : CFG.proxy ? '✅ pronta para usar' : 'sem IA configurada nesta cópia';
  let gh;
  if (!IS_APP) gh = '<p class="muted small" style="margin-top:0">Disponível só dentro do programa.</p>';
  else if (!GS.loaded) gh = '<p class="muted small" style="margin-top:0">Verificando…</p>';
  else if (!GS.available) gh = `<p class="muted small" style="margin-top:0">O login com Google não está ativado nesta cópia do programa.${siteUrl() ? ` Baixe a versão oficial em <a href="${esc(siteUrl())}" target="_blank" rel="noopener">${esc(siteUrl())}</a>.` : ''}</p>`;
  else if (GS.connected) {
    const quando = GS.busy ? 'sincronizando…' : GS.err ? '⚠️ ' + esc(GS.err) : GS.last ? 'última sincronização às ' + new Date(GS.last).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : 'sincroniza sozinho quando você usa o app';
    gh = `<div class="gacct">${GS.picture ? `<img src="${esc(GS.picture)}" alt="" referrerpolicy="no-referrer">` : '<span class="gav">👤</span>'}<div><b>${esc(GS.name || GS.email)}</b>${GS.name && GS.email ? `<br><span class="muted small">${esc(GS.email)}</span>` : ''}</div></div>
      <p class="muted small">Seus livros, metas, progresso e grifos ficam guardados na sua conta Google (numa pasta privada do Páginas no seu Google Drive) e aparecem iguais no computador e no celular.</p>
      <p class="small" style="margin:.2rem 0 .8rem"><b>Situação:</b> ${quando}</p>
      <div class="bookact"><button class="btn primary" data-x="gsync" ${GS.busy ? 'disabled' : ''}>Sincronizar agora</button><button class="btn danger" data-x="gdisc">Desconectar</button></div>`;
  } else gh = `<p class="muted small" style="margin-top:0">Entre com sua conta Google para guardar seus dados na nuvem e continuar a leitura em outro aparelho (computador ou celular). O login abre no seu navegador.</p>
      <div class="bookact"><button class="btn primary" data-x="gconnect">Entrar com Google</button></div>`;
  const ver = APP.versao.charAt(0) === '_' ? 'em desenvolvimento' : APP.versao;
  const plat = APP.plat === 'android' ? 'Android' : APP.plat === 'windows' ? 'Windows' : '';
  const up = UPD.tag ? `<p style="margin:.4rem 0">🎉 <b>Nova versão ${esc(UPD.tag)} disponível.</b>${UPD.notes ? ' ' + esc(UPD.notes) : ''}</p>
      <div class="bookact"><button class="btn primary" data-x="doupd" ${UPD.busy ? 'disabled' : ''}>${UPD.busy ? 'Atualizando…' : APP.plat === 'android' ? 'Baixar a versão nova' : 'Atualizar agora'}</button></div>` : '';
  return `<section class="card"><h2>Conta Google</h2>${gh}</section>
  <section class="card"><h2>Assistente de IA (significado dos trechos)</h2>
    <p class="muted small" style="margin-top:0">Ao selecionar uma palavra ou frase no leitor, a IA explica o significado. Já vem pronta para usar, sem configurar nada.</p>
    <p style="margin:.2rem 0 .8rem"><b>Situação:</b> ${status}</p>
    <details ${IS_APP && CFG.loaded && !CFG.proxy && !CFG.hasKey ? 'open' : ''}><summary class="small">Usar a minha própria chave da Anthropic (opcional)</summary>
    <p class="muted small">Crie a chave em console.anthropic.com. Ela fica guardada só neste aparelho e não entra no backup. O uso é cobrado na sua conta da API.</p>
    <div class="row"><label style="flex:3">Chave da API<input id="cfgKey" type="password" autocomplete="off" placeholder="${CFG.hasKey ? 'Já configurada. Cole outra para trocar' : 'sk-ant-…'}"></label>
    <button class="btn primary" data-x="cfgkey">Salvar</button>${CFG.hasKey ? '<button class="btn danger" data-x="cfgkeydel">Remover</button>' : ''}</div></details>
  </section>
  <section class="card"><h2>Versão</h2><p class="muted small" style="margin-top:0">Páginas ${esc(ver)}${plat ? ' para ' + plat : ''}${siteUrl() ? ` · <a href="${esc(siteUrl())}" target="_blank" rel="noopener">site do Páginas</a>` : ''}</p>${up}</section>
  <style>.card a{color:var(--accent)}.gacct{display:flex;align-items:center;gap:.7rem;margin:.2rem 0 .4rem}.gacct img,.gacct .gav{width:44px;height:44px;border-radius:50%;object-fit:cover;display:flex;align-items:center;justify-content:center;background:var(--line);font-size:1.3rem}</style>`;
}
const _vsettings6 = VIEWS.settings;
VIEWS.settings = function () { return _vsettings6() + settingsAI(); };

/* ---------- cliques ---------- */
document.addEventListener('click', e => {
  const mk = e.target.closest && e.target.closest('mark.hl');
  if (mk && R) { const s = getSelection(); if (!s || s.isCollapsed) { openHl(mk.dataset.hid); return; } }
  const el = e.target.closest && e.target.closest('[data-x]'); if (!el) return;
  const x = el.dataset.x, id = el.dataset.id;
  switch (x) {
    case 'hlmark': {
      const s = HS.sel; if (!s) break;
      if (addHl(s, '')) { clearSel(); repaintPage(); toast('Trecho grifado.'); }
      break;
    }
    case 'hlexplain': {
      const s = HS.sel; if (!s) break;
      clearSel(); explain({ text: s.text, ctx: s.ctx, sel: s });
      break;
    }
    case 'hlagain': { const p = HS.panel; if (p) explain({ text: p.text, ctx: p.ctx, sel: p.sel, hid: p.hid }); break; }
    case 'hlsave': {
      const p = HS.panel; if (!p || p.hid || !p.sel) break;
      const h = addHl(p.sel, p.status === 'done' ? p.ans : '');
      if (h) { p.hid = h.id; repaintPage(); paintPanel(); }
      break;
    }
    case 'hldel': {
      const p = HS.panel; if (!p || !p.hid || !R) break;
      R.b.hl = hls().filter(h => h.id !== p.hid); Store.save(state);
      HS.panel = null; repaintPage(); paintPanel();
      break;
    }
    case 'hlclose': HS.panel = null; paintPanel(); break;
    case 'hllist': HS.panel = { tok: {}, mode: 'list' }; paintPanel(); break;
    case 'hlgo': {
      const h = hls().find(z => z.id === id); if (!h) break;
      if (h.page !== R.idx) goPage(h.page);
      openHl(id);
      const m = document.querySelector('mark[data-hid="' + id + '"]'); if (m) m.scrollIntoView({ block: 'center' });
      break;
    }
    case 'hlsettings': closeReader(); view = 'settings'; render(); break;
    case 'cfgkey': { const v = ($('#cfgKey').value || '').trim(); if (!v) { toast('Cole a chave primeiro.'); break; } cfgDo({ apiKey: v }, 'Chave salva.'); break; }
    case 'cfgkeydel': cfgDo({ apiKey: '' }, 'Chave removida.'); break;
    case 'gconnect': googleConnect(); break;
    case 'gsync': Sync.pull(true); break;
    case 'gdisc': googleLogout(); break;
    case 'doupd': doUpdate(); break;
  }
});
loadCfg();
if (IS_APP) setTimeout(async () => {
  await gStatus();
  if (GS.connected) {
    for (let i = 0; i < 100 && !window.__booted; i++) await new Promise(r => setTimeout(r, 100));
    Sync.pull(false);
  }
  setTimeout(checkUpdate, 3000);
}, 500);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden' && GS.connected) Sync.push(); });
/* ======================================================================
   PARTE 7: tema, jogo (XP, níveis, missões, conquistas), tutorial,
   reflexões e comunidade (amigos, posts, rankings, comunidades)
   ====================================================================== */

/* ---------- tema claro / escuro / automático ---------- */
const temaEscolhido = () => (state.settings && state.settings.tema) || 'auto';
function aplicaTema() {
  const t = temaEscolhido();
  const escuro = t === 'escuro' || (t === 'auto' && matchMedia('(prefers-color-scheme: dark)').matches);
  const h = document.documentElement;
  h.classList.toggle('escuro', escuro); h.classList.toggle('claro', !escuro);
  try { localStorage.setItem('pg_tema', t); } catch (e) {}
  const m = document.querySelector('meta[name=theme-color]');
  if (m) m.content = escuro ? '#1b1815' : '#f6f1e7';
}
try { matchMedia('(prefers-color-scheme: dark)').addEventListener('change', aplicaTema); } catch (e) {}

/* ---------- utilidades ---------- */
const G = () => {
  if (!state.game) state.game = {};
  const g = state.game;
  g.conq = g.conq || {}; g.cont = g.cont || {}; g.miss = g.miss || {};
  if (!g.dia || g.dia.d !== todayStr()) g.dia = { d: todayStr(), ia: 0, quiz: 0, posts: 0, curtidas: 0 };
  return g;
};
function gameConta(k, n) {
  const g = G(); n = n || 1;
  g.cont[k] = (g.cont[k] || 0) + n;
  if (k in g.dia) g.dia[k] += n;
  Store.save(state);
}
const nf = n => Number(n || 0).toLocaleString('pt-BR');
function hashStr(s) { let h = 2166136261; for (let i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }

/* ---------- números do jogador (tudo calculado a partir dos registros) ---------- */
let _st = null, _stKey = '';
function jogoStats() {
  const g = G();
  const key = state.logs.length + '|' + state.books.length + '|' + JSON.stringify(g.cont) + '|' + Object.keys(g.conq).length + '|' + Object.keys(g.miss).length + '|' + todayStr();
  if (_st && key === _stKey) return _st;
  let min = 0, pg = 0, noite = false, manha = false;
  const logs = state.logs.slice().sort((a, b) => (a.ts || 0) - (b.ts || 0));
  const dias = new Set(); let maxSess = 0, sess = 0, prev = null;
  for (const l of logs) {
    min += l.minutes || 0; pg += l.pages || 0; dias.add(l.date);
    const h = new Date(l.ts || 0).getHours();
    if ((l.minutes || l.pages) && (h >= 22 || h < 4)) noite = true;
    if ((l.minutes || l.pages) && h >= 4 && h < 7) manha = true;
    if (prev && prev.bookId === l.bookId && (l.ts - prev.ts) <= ((l.minutes || 0) * 60000 + 180000)) sess += l.minutes || 0; else sess = l.minutes || 0;
    maxSess = Math.max(maxSess, sess); prev = l;
  }
  let fds = false;
  for (const d of dias) { const dt = new Date(d + 'T12:00:00'); if (dt.getDay() === 6 && dias.has(addDays(d, 1))) { fds = true; break; } }
  const fin = state.books.filter(b => b.status === 'finished').length;
  const hl = state.books.reduce((n, b) => n + ((b.hl || []).length), 0);
  const autores = new Set(state.books.filter(b => b.status === 'finished' || logs.some(l => l.bookId === b.id)).map(b => (b.author || '').toLowerCase()).filter(Boolean)).size;
  let metas = 0; for (const d of dias) if (goalMet(d)) metas++;
  const miss = Object.values(g.miss).reduce((n, l) => n + l.length, 0);
  const s = { min, pg, fin, hl, autores, metas, miss, noite, manha, fds, maxSess, best: Math.max(bestStreak(), computeStreak()), streak: computeStreak(),
    ia: g.cont.ia || 0, quizOk: g.cont.quizOk || 0, posts: g.cont.posts || 0, seguindo: g.cont.seguindo || 0, comunidades: g.cont.comunidades || 0,
    top10: !!g.cont.top10, tut: !!g.cont.tutorial };
  // XP: leitura vale mais; conquistas e missões dão bônus
  let xp = min * 2 + pg + fin * 150 + hl * 5 + s.ia * 3 + s.quizOk * 10 + s.posts * 15 + miss * 40;
  for (const id in g.conq) { const c = CQ_BY[id]; if (c) xp += c[5]; }
  for (const d in g.miss) if (g.miss[d].length >= 3) xp += 60;
  s.xp = xp;
  Object.assign(s, nivelDe(xp));
  _st = s; _stKey = key;
  return s;
}
const xpPara = L => 100 + 40 * (L - 1);
function nivelDe(xp) {
  let L = 1, r = xp;
  while (r >= xpPara(L) && L < 999) { r -= xpPara(L); L++; }
  return { nivel: L, dentro: r, prox: xpPara(L) };
}
const TITULOS = [[1, 'Leitor curioso'], [3, 'Aprendiz de biblioteca'], [5, 'Devorador de páginas'], [8, 'Explorador de mundos'], [12, 'Guardião das estantes'], [16, 'Sábio das letras'], [20, 'Lenda da biblioteca'], [30, 'Imortal da Academia']];
const tituloDe = L => TITULOS.filter(t => L >= t[0]).pop()[1];

/* ---------- conquistas: [id, emoji, nome, descrição, progresso(s) -> [atual, meta], XP] ---------- */
const CQ = [
  ['streak3', '🔥', 'Chama acesa', '3 dias seguidos de leitura', s => [s.best, 3], 50],
  ['streak7', '🔥', 'Semana inteira', '7 dias seguidos de leitura', s => [s.best, 7], 100],
  ['streak14', '🌶️', 'Duas semanas', '14 dias seguidos de leitura', s => [s.best, 14], 180],
  ['streak30', '🌋', 'Hábito de ferro', '30 dias seguidos de leitura', s => [s.best, 30], 300],
  ['streak100', '☄️', 'Lenda da constância', '100 dias seguidos de leitura', s => [s.best, 100], 800],
  ['streak365', '🌞', 'Um ano lendo', '365 dias seguidos de leitura', s => [s.best, 365], 2000],
  ['min60', '⏱️', 'Primeira hora', '1 hora de leitura no total', s => [s.min, 60], 40],
  ['min600', '⌛', 'Dez horas de mundos', '10 horas de leitura', s => [s.min, 600], 150],
  ['min3000', '🕰️', 'Cinquenta horas', '50 horas de leitura', s => [s.min, 3000], 400],
  ['min6000', '🏛️', 'Cem horas de biblioteca', '100 horas de leitura', s => [s.min, 6000], 800],
  ['pg100', '📄', 'Cem páginas', '100 páginas lidas', s => [s.pg, 100], 40],
  ['pg1000', '📚', 'Mil páginas', '1.000 páginas lidas', s => [s.pg, 1000], 200],
  ['pg5000', '🗻', 'Montanha de papel', '5.000 páginas lidas', s => [s.pg, 5000], 600],
  ['liv1', '🏁', 'Primeiro da estante', 'Termine um livro', s => [s.fin, 1], 100],
  ['liv5', '🎖️', 'Cinco histórias', 'Termine 5 livros', s => [s.fin, 5], 250],
  ['liv10', '🏆', 'Dez livros', 'Termine 10 livros', s => [s.fin, 10], 500],
  ['liv25', '👑', 'Devorador de livros', 'Termine 25 livros', s => [s.fin, 25], 1000],
  ['hl1', '🖍️', 'Marca-texto', 'Grife o primeiro trecho', s => [s.hl, 1], 20],
  ['hl50', '🖌️', 'Colecionador de frases', 'Grife 50 trechos', s => [s.hl, 50], 200],
  ['ia1', '✨', 'Curiosidade', 'Peça à IA o significado de um trecho', s => [s.ia, 1], 20],
  ['ia30', '🔎', 'Detetive das palavras', 'Use a IA 30 vezes', s => [s.ia, 30], 150],
  ['quiz1', '🧠', 'Primeira resposta', 'Acerte um quiz na aba Para você', s => [s.quizOk, 1], 20],
  ['quiz25', '🎓', 'Sabe-tudo', 'Acerte 25 quizzes', s => [s.quizOk, 25], 250],
  ['noite', '🦉', 'Coruja', 'Leia depois das 22h', s => [s.noite ? 1 : 0, 1], 30],
  ['manha', '🐦', 'Madrugador', 'Leia antes das 7h da manhã', s => [s.manha ? 1 : 0, 1], 30],
  ['marat', '🏃', 'Maratona', 'Leia 60 minutos seguidos', s => [s.maxSess, 60], 80],
  ['fds', '🛋️', 'Fim de semana literário', 'Leia no sábado e no domingo', s => [s.fds ? 1 : 0, 1], 40],
  ['meta10', '🎯', 'Na mosca', 'Cumpra a meta diária em 10 dias', s => [s.metas, 10], 120],
  ['meta50', '🏹', 'Arqueiro da leitura', 'Cumpra a meta diária em 50 dias', s => [s.metas, 50], 400],
  ['autores5', '🗺️', 'Explorador', 'Leia livros de 5 autores diferentes', s => [s.autores, 5], 120],
  ['missoes10', '📜', 'Missão cumprida', 'Complete 10 missões diárias', s => [s.miss, 10], 120],
  ['missoes100', '🗡️', 'Aventureiro', 'Complete 100 missões diárias', s => [s.miss, 100], 500],
  ['nivel5', '⭐', 'Nível 5', 'Chegue ao nível 5', s => [s.nivel, 5], 0],
  ['nivel10', '🌟', 'Nível 10', 'Chegue ao nível 10', s => [s.nivel, 10], 0],
  ['nivel20', '💫', 'Nível 20', 'Chegue ao nível 20', s => [s.nivel, 20], 0],
  ['post1', '💬', 'Primeira palavra', 'Publique algo na Comunidade', s => [s.posts, 1], 30],
  ['post10', '📣', 'Voz ativa', 'Publique 10 vezes', s => [s.posts, 10], 120],
  ['seg1', '🤝', 'Primeira amizade', 'Siga um leitor', s => [s.seguindo, 1], 30],
  ['seg10', '👥', 'Clube do livro', 'Siga 10 leitores', s => [s.seguindo, 10], 100],
  ['comun1', '🏘️', 'Em comunidade', 'Entre numa comunidade de leitura', s => [s.comunidades, 1], 30],
  ['top10', '🥇', 'Destaque da cidade', 'Fique entre os 10 da sua cidade na semana', s => [s.top10 ? 1 : 0, 1], 200],
  ['tutorial', '🧭', 'Guia completo', 'Termine o tutorial do Páginas', s => [s.tut ? 1 : 0, 1], 20],
];
const CQ_BY = Object.fromEntries(CQ.map(c => [c[0], c]));

/* ---------- missões diárias ---------- */
function hojeLido() {
  const t = todayStr(); let m = 0, p = 0;
  for (const l of state.logs) if (l.date === t) { m += l.minutes || 0; p += l.pages || 0; }
  if (typeof R !== 'undefined' && R) { m += Math.floor(R.secs / 60); p += R.pagesAcc || 0; }
  return { m, p };
}
function grifosHoje() {
  const ini = new Date(todayStr() + 'T00:00:00').getTime();
  return state.books.reduce((n, b) => n + (b.hl || []).filter(h => (h.ts || 0) >= ini).length, 0);
}
const MP = {
  ler15: { e: '📖', t: 'Leia 15 minutos', alvo: 15, prog: () => hojeLido().m },
  ler30: { e: '📖', t: 'Leia 30 minutos', alvo: 30, prog: () => hojeLido().m },
  pag10: { e: '📄', t: 'Leia 10 páginas', alvo: 10, prog: () => hojeLido().p },
  pag25: { e: '📄', t: 'Leia 25 páginas', alvo: 25, prog: () => hojeLido().p },
  meta: { e: '🎯', t: 'Cumpra sua meta do dia', alvo: 1, prog: () => goalMet(todayStr()) ? 1 : 0 },
  grifo: { e: '🖍️', t: 'Grife 2 trechos', alvo: 2, prog: grifosHoje },
  ia: { e: '✨', t: 'Peça à IA o significado de uma palavra', alvo: 1, prog: () => G().dia.ia },
  quiz: { e: '🧠', t: 'Responda um quiz em Para você', alvo: 1, prog: () => G().dia.quiz },
  post: { e: '💬', t: 'Compartilhe algo na Comunidade', alvo: 1, prog: () => G().dia.posts, social: true },
  curtir: { e: '❤️', t: 'Curta 3 posts de outros leitores', alvo: 3, prog: () => G().dia.curtidas, social: true },
};
function missoesHoje() {
  const t = todayStr(), h = hashStr(t + (state.profile && state.profile.name || ''));
  const leitura = ['ler15', 'ler30', 'pag10', 'pag25', 'meta'];
  const outras = ['grifo', 'ia', 'quiz'].concat(SOC.token ? ['post', 'curtir'] : []);
  const a = leitura[h % leitura.length];
  const b = outras[(h >>> 4) % outras.length];
  const rest = outras.filter(x => x !== b);
  const c = rest[(h >>> 9) % rest.length];
  return [a, b, c].map(id => {
    const m = MP[id], v = Math.min(m.alvo, m.prog() || 0);
    return { id, ...m, v, ok: v >= m.alvo };
  });
}

/* ---------- verificação: conquistas e missões novas ---------- */
let _jogoT = null, _jogoAndando = false;
function agendaJogo() { clearTimeout(_jogoT); _jogoT = setTimeout(verificaJogo, 700); }
function verificaJogo() {
  if (_jogoAndando || loadFailed || !window.__booted) return;
  _jogoAndando = true;
  try {
    const g = G(), t = todayStr(), novas = [];
    // missões
    const feitas = g.miss[t] || [];
    for (const m of missoesHoje()) if (m.ok && !feitas.includes(m.id)) { feitas.push(m.id); novas.push({ tipo: 'missao', e: m.e, nome: 'Missão cumprida!', desc: m.t, xp: 40 }); }
    if (feitas.length) g.miss[t] = feitas;
    if (feitas.length >= 3 && !g.bau) g.bau = {};
    if (feitas.length >= 3 && g.bau && !g.bau[t]) { g.bau[t] = 1; novas.push({ tipo: 'bau', e: '🎁', nome: 'Baú do dia!', desc: 'Você completou as 3 missões de hoje.', xp: 60 }); }
    _st = null;
    // conquistas (mais de uma rodada: uma conquista pode subir o nível e liberar outra)
    const primeira = !g.iniciado;
    for (let volta = 0; volta < 3; volta++) {
      const s = jogoStats(); let achou = false;
      for (const c of CQ) {
        if (g.conq[c[0]]) continue;
        const [v, meta] = c[4](s);
        if (v >= meta) { g.conq[c[0]] = Date.now(); achou = true; if (!primeira) novas.push({ tipo: 'conq', e: c[1], nome: c[2], desc: c[3], xp: c[5] }); _st = null; }
      }
      if (!achou) break;
    }
    const nv = jogoStats().nivel;
    if (g.nivel && nv > g.nivel && !primeira && !novas.some(x => x.nome === 'Nível ' + nv)) novas.push({ tipo: 'nivel', e: '⬆️', nome: 'Nível ' + nv + '!', desc: tituloDe(nv), xp: 0 });
    const mudou = novas.length || primeira || g.nivel !== nv;
    g.nivel = nv;
    if (primeira) { g.iniciado = Date.now(); const n = Object.keys(g.conq).length; if (n) setTimeout(() => toast(`Você já tem ${n} ${n === 1 ? 'conquista' : 'conquistas'} e está no nível ${nv}! Veja em Estatísticas.`), 2500); }
    if (mudou) { Sync.quiet = !novas.length; try { Store.save(state); } finally { Sync.quiet = false; } }
    if (novas.length) { CEL.fila.push(...novas); celebra(); socPerfilDepois(); if (view === 'today' && !R) render(); }
  } finally { _jogoAndando = false; }
}

/* ---------- comemoração ---------- */
const CEL = { fila: [], aberta: false };
function celebra() {
  if (CEL.aberta || !CEL.fila.length) return;
  const c = CEL.fila.shift(); CEL.aberta = true;
  const el = document.createElement('div');
  el.id = 'cel'; el.className = 'cel';
  const cores = ['#e08a5c', '#e0b04a', '#7bc08a', '#6aa6e0', '#c47bd6'];
  const conf = Array.from({ length: 28 }, (_, i) => `<i style="left:${(i * 37) % 100}%;background:${cores[i % 5]};animation-delay:${(i % 7) * 0.08}s;--r:${(i * 53) % 360}deg"></i>`).join('');
  const rot = { conq: 'Conquista desbloqueada', missao: 'Missão diária', bau: 'Recompensa', nivel: 'Você subiu de nível' }[c.tipo];
  el.innerHTML = `<div class="celconf">${conf}</div><div class="celbox"><small>${rot}</small><div class="cele">${c.e}</div><h2>${esc(c.nome)}</h2><p>${esc(c.desc)}</p>${c.xp ? `<b class="celxp">+${c.xp} XP</b>` : ''}
    <div class="bookact" style="justify-content:center">${c.tipo === 'conq' && SOC.token ? '<button class="btn" data-g="celshare">Compartilhar</button>' : ''}<button class="btn primary" data-g="celok">Continuar</button></div></div>`;
  el.dataset.nome = c.nome; el.dataset.e = c.e;
  document.body.appendChild(el);
  try { if (navigator.vibrate) navigator.vibrate(60); } catch (e) {}
}
function fechaCel() { const el = $('#cel'); if (el) el.remove(); CEL.aberta = false; setTimeout(celebra, 250); }

/* ---------- cartão do jogo na aba Hoje ---------- */
function cartaoJogo() {
  const s = jogoStats(), ms = missoesHoje(), g = G(), feitas = (g.miss[todayStr()] || []).length;
  const pct = Math.round(s.dentro / s.prox * 100);
  const nconq = Object.keys(g.conq).length;
  return `<section class="card jogo" id="jogo">
    <div class="jtop"><div class="jlvl"><span>${s.nivel}</span></div><div style="flex:1;min-width:0"><b>${esc(tituloDe(s.nivel))}</b>
      <div class="xpbar"><i style="width:${pct}%"></i></div><small class="muted">${nf(s.dentro)} / ${nf(s.prox)} XP para o nível ${s.nivel + 1} · ${nf(s.xp)} XP no total</small></div>
      <button class="jstreak" data-g="irconq" title="Sequência de dias">🔥<b>${s.streak}</b></button></div>
    <div class="jmiss"><div class="jmh"><b>Missões de hoje</b><span class="muted small">${feitas}/3 ${feitas >= 3 ? '· 🎁 baú aberto!' : '· complete as 3 e ganhe um baú'}</span></div>
      ${ms.map(m => `<div class="jm ${m.ok ? 'ok' : ''}"><span class="jme">${m.ok ? '✅' : m.e}</span><div style="flex:1"><div>${esc(m.t)}</div><div class="mbar"><i style="width:${Math.round(m.v / m.alvo * 100)}%"></i></div></div><small>${m.v}/${m.alvo}</small><small class="jxp">+40</small></div>`).join('')}
    </div>
    <div class="jfoot"><button class="btn sm" data-g="irconq">🏅 Conquistas (${nconq}/${CQ.length})</button>${SOC.url ? '<button class="btn sm" data-g="irrank">🏆 Rankings</button>' : ''}</div>
  </section>${cartaoReflexao()}`;
}
function gradeConquistas() {
  const s = jogoStats(), g = G();
  const l = CQ.map(c => {
    const [v, meta] = c[4](s), ok = !!g.conq[c[0]];
    return `<div class="cq ${ok ? 'ok' : ''}" title="${esc(c[3])}"><div class="cqe">${ok ? c[1] : '🔒'}</div><b>${esc(c[2])}</b><small>${esc(c[3])}</small>
      ${ok ? `<small class="cqd">${new Date(g.conq[c[0]]).toLocaleDateString('pt-BR')}</small>` : `<div class="mbar"><i style="width:${Math.min(100, Math.round(v / meta * 100))}%"></i></div><small>${nf(Math.min(v, meta))}/${nf(meta)}</small>`}</div>`;
  }).join('');
  return `<section class="card" id="conq"><h2>🏅 Conquistas <span class="muted small">${Object.keys(g.conq).length} de ${CQ.length}</span></h2><div class="cqgrid">${l}</div></section>`;
}

/* ---------- reflexões (notificações e cartão do dia) ---------- */
let _refl = null;
function reflexoes() {
  if (_refl) return _refl;
  try { _refl = JSON.parse(document.getElementById('reflexoes').textContent); } catch (e) { _refl = []; }
  return _refl;
}
function reflexaoDoDia() { const l = reflexoes(); return l.length ? l[hashStr('r' + todayStr()) % l.length] : null; }
function cartaoReflexao() {
  const r = reflexaoDoDia(); if (!r) return '';
  return `<section class="card refl"><small class="muted">💭 Reflexão do dia</small><p>${esc(r.t)}</p>${r.a ? `<small class="muted">— ${esc(r.a)}</small>` : ''}
    ${SOC.token ? '<div style="margin-top:.5rem"><button class="btn sm" data-g="reflshare">💬 Comentar com a comunidade</button></div>' : ''}</section>`;
}
const notifCfg = () => Object.assign({ on: false, horas: ['09:00', '20:00'] }, state.settings.reflex || {});
async function aplicaNotif(avisar) {
  const c = notifCfg();
  try {
    if (APP.plat === 'android' && window.PaginasAndroid && PaginasAndroid.agendarReflexoes) {
      PaginasAndroid.agendarReflexoes(JSON.stringify(c));
    } else if (IS_APP) {
      const r = await api('/api/notif', { method: 'POST', body: JSON.stringify(c) });
      await r.json();
    }
    if (avisar) toast(c.on ? `Pronto: reflexões às ${c.horas.join(' e ')}.` : 'Reflexões desligadas.');
  } catch (e) { toast('Não consegui agendar as reflexões: ' + e.message); }
}

/* ---------- tutorial ---------- */
const TUT_PASSOS = [
  { t: 'Bem-vindo(a) ao Páginas! 📖', x: 'Em 1 minuto eu te mostro onde fica cada coisa. Você pode pular quando quiser e rever em Ajustes.' },
  { sel: '.tab[data-v=today]', v: 'today', t: 'Hoje', x: 'Sua meta do dia, a sequência de dias seguidos 🔥 e o cronômetro. Leia um pouco todo dia para não perder a sequência.' },
  { sel: '#jogo', v: 'today', t: 'Nível, XP e missões', x: 'Cada minuto lido dá XP e sobe o seu nível. Todo dia aparecem 3 missões novas: complete as três e ganhe um baú de bônus.' },
  { sel: '.tab[data-v=foryou]', v: 'foryou', t: 'Para você', x: 'Um feed com sugestões de livros, frases, curiosidades e quizzes, misturado com os posts dos seus amigos.' },
  { sel: '.tab[data-v=social]', v: 'social', t: 'Comunidade', x: 'Siga outros leitores, publique resenhas e frases, entre em comunidades de leitura e dispute os rankings da sua cidade, do estado, do país e do mundo.' },
  { sel: '.tab[data-v=library]', v: 'library', t: 'Pesquisar', x: 'Milhares de livros gratuitos para ler aqui dentro. Busque por título, autor ou tema.' },
  { sel: '.tab[data-v=shelf]', v: 'shelf', t: 'Estante', x: 'Seus livros. No leitor, selecione um trecho para grifar 🖍, pedir o significado à IA ✨ ou compartilhar 💬.' },
  { sel: '.tab[data-v=stats]', v: 'stats', t: 'Estatísticas e conquistas', x: 'Seus números de leitura e as conquistas para desbloquear. Tem conquista para coruja, madrugador, maratona e muito mais.' },
  { sel: '.tab[data-v=settings]', v: 'settings', t: 'Ajustes', x: 'Tema claro ou escuro, sua conta Google (para sincronizar e usar a Comunidade) e as reflexões diárias.' },
  { t: 'Tudo pronto! 🎉', x: 'Comece pela aba Pesquisar ou pela Estante e leia alguns minutos hoje. Boa leitura!' },
];
const TUT = { i: -1 };
function tutorialInicia() { TUT.i = 0; tutorialMostra(); }
function tutorialFim(concluiu) {
  TUT.i = -1; const el = $('#tut'); if (el) el.remove();
  const g = G(); g.tutVisto = 1;
  if (concluiu && !g.cont.tutorial) gameConta('tutorial'); else Store.save(state);
  view = 'today'; render(); window.scrollTo(0, 0);
}
function tutorialMostra() {
  const p = TUT_PASSOS[TUT.i]; if (!p) return tutorialFim(true);
  if (p.v && view !== p.v) { view = p.v; render(); }
  let el = $('#tut');
  if (!el) { el = document.createElement('div'); el.id = 'tut'; document.body.appendChild(el); }
  const alvo = p.sel ? document.querySelector(p.sel) : null;
  if (alvo) alvo.scrollIntoView({ block: 'nearest', inline: 'center' });
  const n = TUT_PASSOS.length;
  const caixa = `<div class="tutbox"><small class="muted">${TUT.i + 1} de ${n}</small><h3>${esc(p.t)}</h3><p>${esc(p.x)}</p>
    <div class="bookact">${TUT.i < n - 1 ? '<button class="btn" data-g="tutpular">Pular</button>' : ''}${TUT.i > 0 ? '<button class="btn" data-g="tutvolta">Voltar</button>' : ''}<button class="btn primary" data-g="tutprox">${TUT.i === n - 1 ? 'Começar' : 'Próximo'}</button></div></div>`;
  requestAnimationFrame(() => {
    if (alvo) {
      const r = alvo.getBoundingClientRect(), pad = 6;
      const lt = Math.max(4, r.left - pad), tp = Math.max(4, r.top - pad);
      const w = Math.min(innerWidth - 8, r.width + pad * 2), h = Math.min(innerHeight * 0.6, r.height + pad * 2);
      const embaixo = tp + h + 220 < innerHeight;
      el.innerHTML = `<div class="tutspot" style="left:${lt}px;top:${tp}px;width:${w}px;height:${h}px"></div>${caixa}`;
      const bx = el.querySelector('.tutbox');
      bx.style.top = (embaixo ? tp + h + 12 : Math.max(8, tp - bx.offsetHeight - 12)) + 'px';
      bx.style.left = Math.max(8, Math.min(innerWidth - bx.offsetWidth - 8, lt + w / 2 - bx.offsetWidth / 2)) + 'px';
    } else {
      el.innerHTML = `<div class="tutspot meio"></div>${caixa}`;
      const bx = el.querySelector('.tutbox'); bx.classList.add('meio');
    }
  });
}
addEventListener('resize', () => { if (TUT.i >= 0) tutorialMostra(); });

/* ======================================================================
   COMUNIDADE (servidor social do Páginas)
   ====================================================================== */
const SOC = { url: '__SOCIAL__', token: '', eu: null, aba: 'feed', feed: null, feedErr: '', desc: false, rank: null, rq: { tipo: 'tempo', periodo: 'semana', escopo: 'cidade' },
  pessoas: null, pq: '', comus: null, cq: '', comu: null, perfil: null, coment: {}, carregando: false, sid: '', ultimoPulso: 0, entrando: false };
if (SOC.url.charAt(0) === '_') SOC.url = '';
SOC.url = SOC.url.replace(/\/+$/, '');
try { SOC.token = localStorage.getItem('pg_soc') || ''; SOC.eu = JSON.parse(localStorage.getItem('pg_soc_eu') || 'null'); } catch (e) {}
function socGuarda() { try { localStorage.setItem('pg_soc', SOC.token || ''); localStorage.setItem('pg_soc_eu', JSON.stringify(SOC.eu)); } catch (e) {} }
async function socApi(path, o) {
  o = o || {};
  if (!SOC.url) throw new Error('A Comunidade ainda não foi ativada nesta versão.');
  const h = { 'Content-Type': 'application/json' };
  if (SOC.token) h.Authorization = 'Bearer ' + SOC.token;
  let r;
  try { r = await fetch(SOC.url + path, { method: o.method || 'GET', headers: h, body: o.body ? JSON.stringify(o.body) : undefined }); }
  catch (e) { throw new Error('Sem conexão com a Comunidade. Confira a internet.'); }
  let j = {}; try { j = await r.json(); } catch (e) {}
  if (r.status === 401 && path !== '/auth/google') { SOC.token = ''; SOC.eu = null; socGuarda(); }
  if (!r.ok) throw new Error(j.erro || ('Erro ' + r.status));
  return j;
}
async function socEntrar(silencioso) {
  if (SOC.entrando) return;
  if (!SOC.url) return silencioso || toast('A Comunidade ainda não foi ativada nesta versão.');
  if (!GS.connected) { if (!silencioso) { toast('Primeiro entre com sua conta Google.'); googleConnect(); } return; }
  SOC.entrando = true; if (view === 'social') render();
  try {
    const at = (await (await api('/api/google/token')).json()).token;
    const j = await socApi('/auth/google', { method: 'POST', body: { access_token: at, tz: -new Date().getTimezoneOffset() } });
    SOC.token = j.token; SOC.eu = j.eu; socGuarda();
    SOC.feed = null; socPerfilDepois(true);
    if (!silencioso) toast('Bem-vindo(a) à Comunidade, ' + (j.eu.nome || '').split(' ')[0] + '!');
  } catch (e) { if (!silencioso) toast(e.message); }
  finally { SOC.entrando = false; if (view === 'social') render(); }
}
let _perfT = null, _perfUlt = 0;
function socPerfilDepois(ja) {
  if (!SOC.token) return;
  clearTimeout(_perfT);
  _perfT = setTimeout(async () => {
    _perfUlt = Date.now();
    const s = jogoStats(), lendo = state.books.filter(b => b.status === 'reading').sort((a, b) => (b.lastRead || 0) - (a.lastRead || 0))[0];
    try { await socApi('/perfil', { method: 'POST', body: { nivel: s.nivel, conquistas: Object.keys(G().conq).length, lendo: lendo ? lendo.title : '' } }); } catch (e) {}
  }, ja ? 500 : Math.max(5000, 300000 - (Date.now() - _perfUlt)));
}

/* ---------- tempo de leitura contado pelo servidor (vale para os rankings) ---------- */
async function socLeitura() {
  if (!SOC.token) return;
  const lendo = typeof R !== 'undefined' && R;
  try {
    if (lendo && (!SOC.sid || SOC.sidLivro !== R.b.id)) {
      if (SOC.sid) { try { await socApi('/leitura/fim', { method: 'POST', body: { sid: SOC.sid } }); } catch (e) {} }
      const j = await socApi('/leitura/inicio', { method: 'POST', body: { livro: R.b.title, autor: R.b.author } });
      SOC.sid = j.sid; SOC.sidLivro = R.b.id; SOC.ultimoPulso = Date.now();
    } else if (lendo && SOC.sid) {
      const ativo = document.visibilityState === 'visible' && Date.now() - R.lastAct < 120000;
      if (ativo && Date.now() - SOC.ultimoPulso >= 58000) {
        SOC.ultimoPulso = Date.now();
        const j = await socApi('/leitura/pulso', { method: 'POST', body: { sid: SOC.sid } });
        if (j.streak != null && SOC.eu) { SOC.eu.streak = j.streak; socGuarda(); }
      }
    } else if (!lendo && SOC.sid) {
      const sid = SOC.sid; SOC.sid = '';
      await socApi('/leitura/fim', { method: 'POST', body: { sid } });
    }
  } catch (e) { if (/encerrada/.test(e.message)) SOC.sid = ''; }
}
setInterval(socLeitura, 5000);

/* ---------- desenho dos posts ---------- */
const TIPO_POST = { texto: ['💬', ''], resenha: ['⭐', 'Resenha'], frase: ['❝', 'Frase'], pagina: ['📄', 'Trecho'], pergunta: ['❓', 'Pergunta'], progresso: ['📈', 'Progresso'], conquista: ['🏅', 'Conquista'] };
function avatar(u, cls) {
  const ini = esc(((u && u.nome) || '?').trim().charAt(0).toUpperCase());
  return u && u.foto ? `<img class="av ${cls || ''}" src="${esc(u.foto)}" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer">` : `<span class="av ${cls || ''}" style="--h:${hashStr((u && u.id) || '') % 360}">${ini}</span>`;
}
function quando(ts) {
  const d = Date.now() / 1000 - ts;
  if (d < 60) return 'agora'; if (d < 3600) return Math.floor(d / 60) + ' min'; if (d < 86400) return Math.floor(d / 3600) + ' h';
  if (d < 7 * 86400) return Math.floor(d / 86400) + ' d';
  return new Date(ts * 1000).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short' });
}
function socPostHtml(p) {
  const [ic, rot] = TIPO_POST[p.tipo] || TIPO_POST.texto;
  const corpo = p.tipo === 'frase' || p.tipo === 'pagina'
    ? `<blockquote class="spq">${esc(p.texto)}</blockquote>`
    : `<p class="spt">${esc(p.texto)}</p>`;
  const livro = p.livro ? `<button class="splv" data-g="buscalivro" data-q="${esc(p.livro)}">📘 ${esc(p.livro)}${p.livro_autor ? ' · ' + esc(p.livro_autor) : ''}${p.pagina ? ' · pág. ' + p.pagina : ''}</button>` : '';
  const nota = p.nota ? `<span class="spst">${'★'.repeat(p.nota)}${'☆'.repeat(5 - p.nota)}</span>` : '';
  const com = SOC.coment[p.id];
  return `<article class="post spost" data-sp="${esc(p.id)}">
    <div class="sph">${avatar(p.autor)}<div style="flex:1;min-width:0"><button class="spn" data-g="perfil" data-id="${esc(p.autor.id)}">${esc(p.autor.nome)}</button> <span class="lv">nv ${p.autor.nivel || 1}</span>
      <div class="muted small">${rot ? ic + ' ' + rot + ' · ' : ''}${quando(p.criado)}${p.comunidade ? ` · <button class="spc" data-g="comu" data-id="${esc(p.comunidade.id)}">${esc(p.comunidade.emoji || '📚')} ${esc(p.comunidade.nome)}</button>` : ''}</div></div>
      <button class="spm" data-g="postmenu" data-id="${esc(p.id)}" aria-label="Mais opções">⋯</button></div>
    <div class="pbody">${nota}${corpo}${livro}</div>
    <div class="spa"><button class="${p.curti ? 'on' : ''}" data-g="curtir" data-id="${esc(p.id)}">${p.curti ? '❤️' : '🤍'} ${p.curtidas || ''}</button>
      <button data-g="coments" data-id="${esc(p.id)}">💬 ${p.comentarios || ''}</button></div>
    ${com ? `<div class="spcm">${com.lista ? com.lista.map(c => `<div class="cmi">${avatar(c.autor, 'sm')}<div><button class="spn" data-g="perfil" data-id="${esc(c.autor.id)}">${esc(c.autor.nome)}</button> ${esc(c.texto)} <small class="muted">${quando(c.criado)}</small>${c.meu ? ` <button class="lnk" data-g="cmdel" data-id="${esc(c.id)}" data-p="${esc(p.id)}">apagar</button>` : ''}</div></div>`).join('') || '<p class="muted small">Seja o primeiro a comentar.</p>' : '<p class="muted small">Carregando…</p>'}
      <form class="cmf" data-p="${esc(p.id)}"><input name="t" maxlength="500" placeholder="Escreva um comentário…" autocomplete="off"><button class="btn sm primary">Enviar</button></form></div>` : ''}
  </article>`;
}
function achaPost(id) {
  for (const l of [SOC.feed, SOC.comu && SOC.comu.posts, SOC.perfil && SOC.perfil.posts]) if (l) { const p = l.find(x => x.id === id); if (p) return p; }
  return null;
}
function repintaPost(id) {
  const p = achaPost(id); if (!p) return;
  document.querySelectorAll(`[data-sp="${CSS.escape(id)}"]`).forEach(el => { el.outerHTML = socPostHtml(p); });
}

/* ---------- compor post ---------- */
const COMP = { aberto: false, d: {} };
function abrirComposer(d) {
  if (!SOC.token) { view = 'social'; render(); return toast('Entre na Comunidade para publicar.'); }
  COMP.d = Object.assign({ tipo: 'texto', texto: '', livro: '', livro_autor: '', gid: '', pagina: 0, nota: 0, comunidade: (SOC.aba === 'comu' && SOC.comu && SOC.comu.comunidade.eu_membro) ? SOC.comu.comunidade.id : '' }, d || {});
  COMP.aberto = true; pintaComposer();
}
function pintaComposer() {
  let el = $('#scomp');
  if (!COMP.aberto) { if (el) el.remove(); return; }
  if (!el) { el = document.createElement('div'); el.id = 'scomp'; el.className = 'smodal'; document.body.appendChild(el); }
  const d = COMP.d;
  const livros = state.books.filter(b => b.status !== 'want' || b.lastRead).slice(0, 40);
  const comus = (SOC.minhas || []);
  el.innerHTML = `<form class="smbox" id="compForm"><div class="hph"><span>Nova publicação</span><button type="button" data-g="compfecha" aria-label="Fechar">×</button></div>
    <div class="ctipos">${['texto', 'resenha', 'frase', 'pergunta', 'pagina'].map(t => `<button type="button" class="chip ${d.tipo === t ? 'on' : ''}" data-g="comptipo" data-v="${t}">${TIPO_POST[t][0]} ${TIPO_POST[t][1] || 'Texto'}</button>`).join('')}</div>
    ${d.tipo === 'resenha' ? `<div class="cstars">${[1, 2, 3, 4, 5].map(n => `<button type="button" class="star ${n <= d.nota ? 'on' : ''}" data-g="compnota" data-v="${n}">★</button>`).join('')}</div>` : ''}
    <textarea id="compTxt" rows="${d.tipo === 'pagina' ? 7 : 4}" maxlength="2000" placeholder="${{ texto: 'O que você está pensando sobre o que lê?', resenha: 'O que achou do livro? (sem spoilers, por favor!)', frase: 'Cole a frase que te marcou', pergunta: 'Pergunte algo aos outros leitores', pagina: 'Cole o trecho que quer compartilhar' }[d.tipo]}">${esc(d.texto)}</textarea>
    <label class="small">Livro (opcional)<select id="compLivro"><option value="">Nenhum</option>${livros.map(b => `<option value="${esc(b.id)}" ${b.title === d.livro ? 'selected' : ''}>${esc(b.title)}</option>`).join('')}${d.livro && !livros.some(b => b.title === d.livro) ? `<option value="__x" selected>${esc(d.livro)}</option>` : ''}</select></label>
    <label class="small">Publicar em<select id="compComu"><option value="">Meu perfil (seguidores)</option>${comus.map(c => `<option value="${esc(c.id)}" ${c.id === d.comunidade ? 'selected' : ''}>${esc(c.emoji)} ${esc(c.nome)}</option>`).join('')}</select></label>
    <div class="bookact" style="justify-content:flex-end"><button type="button" class="btn" data-g="compfecha">Cancelar</button><button class="btn primary" ${COMP.enviando ? 'disabled' : ''}>${COMP.enviando ? 'Publicando…' : 'Publicar'}</button></div></form>`;
  setTimeout(() => { const t = $('#compTxt'); if (t) t.focus(); }, 30);
}
function lerComposer() {
  const d = COMP.d, t = $('#compTxt'), lv = $('#compLivro'), cm = $('#compComu');
  if (t) d.texto = t.value;
  if (lv && lv.value && lv.value !== '__x') { const b = state.books.find(x => x.id === lv.value); if (b) { d.livro = b.title; d.livro_autor = b.author || ''; d.gid = b.gid || ''; } }
  else if (lv && !lv.value) { d.livro = ''; d.livro_autor = ''; d.gid = ''; }
  if (cm) d.comunidade = cm.value;
}
async function publicar() {
  lerComposer();
  const d = COMP.d;
  if ((d.texto || '').trim().length < 2) return toast('Escreva alguma coisa antes de publicar.');
  COMP.enviando = true; pintaComposer();
  try {
    const j = await socApi('/posts', { method: 'POST', body: d });
    COMP.aberto = false; COMP.enviando = false; pintaComposer();
    if (SOC.feed) SOC.feed.unshift(j.post);
    if (SOC.comu && SOC.comu.comunidade.id === d.comunidade) SOC.comu.posts.unshift(j.post);
    gameConta('posts'); toast('Publicado!');
    if (view === 'social' || view === 'foryou') render();
  } catch (e) { COMP.enviando = false; pintaComposer(); toast(e.message); }
}

/* ---------- carregar dados ---------- */
async function carrega(fn) {
  try { await fn(); SOC.erro = ''; } catch (e) { SOC.erro = e.message; SOC.erroEm = Date.now(); toast(e.message); }
  SOC.carregando = false;
  if (view === 'social' || view === 'foryou') render();
}
// não tenta de novo sozinho por 15 s depois de um erro (evita repetir pedidos sem parar)
const podeCarregar = () => !SOC.carregando && Date.now() - (SOC.erroEm || 0) > 15000;
const falhou = () => SOC.erro && !podeCarregar() ? `<div class="card empty">${esc(SOC.erro)}<br><button class="btn sm" data-g="retry">Tentar de novo</button></div>` : SKEL;
async function carregaFeed(mais) {
  const antes = mais && SOC.feed && SOC.feed.length ? '?antes=' + SOC.feed[SOC.feed.length - 1].criado : '';
  const j = await socApi('/feed' + antes);
  let posts = j.posts;
  if (!mais && posts.length < 5) { const d = await socApi('/descobrir'); const ids = new Set(posts.map(p => p.id)); posts = posts.concat(d.posts.filter(p => !ids.has(p.id))); SOC.desc = true; }
  SOC.feed = mais ? (SOC.feed || []).concat(posts) : posts;
  SOC.feedFim = j.posts.length < 30;
}
async function carregaMinhas() { SOC.minhas = (await socApi('/comunidades?minhas=1')).comunidades; G().cont.comunidades = SOC.minhas.length; }

/* ---------- tela da Comunidade ---------- */
const ESCOPOS = [['amigos', '👥 Amigos'], ['cidade', '🏙️ Cidade'], ['estado', '🗺️ Estado'], ['pais', '🏳️ País'], ['global', '🌎 Mundo']];
let _nomePais = null;
function nomePais(c) { try { _nomePais = _nomePais || new Intl.DisplayNames(['pt-BR'], { type: 'region' }); return _nomePais.of(c); } catch (e) { return c; } }
function renderSocial() {
  if (!SOC.url) return `<section class="card"><h2>Comunidade</h2><p class="muted">A Comunidade (amigos, posts, rankings e comunidades de leitura) ainda não foi ativada nesta versão do Páginas. Ela chega numa próxima atualização.</p></section>`;
  if (!SOC.token) {
    if (GS.connected && !SOC.entrando && !SOC.tentou) { SOC.tentou = true; setTimeout(() => socEntrar(true), 0); }
    return `<section class="card center socin"><div style="font-size:3rem">👥</div><h2>Leia junto com outras pessoas</h2>
      <p class="muted">Siga amigos, compartilhe frases e resenhas, entre em comunidades de leitura e dispute os rankings da sua cidade, do estado, do país e do mundo.</p>
      <p class="small muted">Os rankings usam só o tempo lido no leitor do Páginas, contado pelo servidor, para ninguém conseguir inventar horas.</p>
      <button class="btn primary" data-g="socentrar" ${SOC.entrando ? 'disabled' : ''}>${SOC.entrando ? 'Entrando…' : GS.connected ? 'Entrar na Comunidade' : 'Entrar com Google'}</button></section>`;
  }
  const abas = [['feed', '🏠 Feed'], ['rank', '🏆 Rankings'], ['pessoas', '👥 Amigos'], ['comus', '🏘️ Comunidades'], ['eu', '👤 Perfil']];
  let h = `<div class="stabs">${abas.map(([k, l]) => `<button class="chip ${SOC.aba === k || (SOC.aba === 'comu' && k === 'comus') || (SOC.aba === 'perfil' && k === 'pessoas') ? 'on' : ''}" data-g="saba" data-v="${k}">${l}</button>`).join('')}</div>`;
  if (SOC.aba === 'feed') h += telaFeed();
  else if (SOC.aba === 'rank') h += telaRank();
  else if (SOC.aba === 'pessoas') h += telaPessoas();
  else if (SOC.aba === 'comus') h += telaComus();
  else if (SOC.aba === 'comu') h += telaComu();
  else if (SOC.aba === 'perfil' || SOC.aba === 'eu') h += telaPerfil();
  return `<div class="feed social">${h}</div>`;
}
function caixaPublicar(dica) {
  return `<button class="card scomp" data-g="compor">${avatar(SOC.eu)}<span class="muted">${esc(dica || 'Compartilhe o que você está lendo…')}</span></button>`;
}
function telaFeed() {
  if (!SOC.feed) { if (podeCarregar()) { SOC.carregando = true; carrega(() => Promise.all([carregaFeed(false), carregaMinhas()])); } return caixaPublicar() + falhou(); }
  return caixaPublicar() + (SOC.desc && SOC.feed.length ? '<p class="muted small" style="margin:.2rem .3rem .8rem">Novidades de leitores de todo lugar. Siga pessoas e entre em comunidades para montar o seu feed.</p>' : '') +
    (SOC.feed.length ? SOC.feed.map(socPostHtml).join('') : '<div class="card empty">Ainda não há publicações. Que tal a primeira?</div>') +
    (SOC.feed.length && !SOC.feedFim ? '<p class="center"><button class="btn" data-g="feedmais">Ver mais</button></p>' : '');
}
function fmtValor(v, tipo) {
  if (tipo === 'streak') return v + (v === 1 ? ' dia' : ' dias');
  const m = Math.round(v / 60); return m >= 60 ? (Math.floor(m / 60) + ' h ' + (m % 60) + ' min') : (m + ' min');
}
function telaRank() {
  const q = SOC.rq;
  const sel = (k, op) => `<div class="rsel">${op.map(([v, l]) => `<button class="chip ${q[k] === v ? 'on' : ''}" data-g="rq" data-k="${k}" data-v="${v}">${l}</button>`).join('')}</div>`;
  let h = `<section class="card"><h2>🏆 Rankings de leitura</h2>
    ${sel('tipo', [['tempo', '⏱️ Tempo lendo'], ['streak', '🔥 Sequência']])}
    ${q.tipo === 'tempo' ? sel('periodo', [['semana', 'Últimos 7 dias'], ['mes', '30 dias'], ['total', 'Desde sempre']]) : ''}
    ${sel('escopo', ESCOPOS)}
    <p class="muted small" style="margin:.4rem 0 0">Só conta o tempo lido no leitor do Páginas, medido pelo servidor a cada minuto (máximo de 8 h por dia). A cidade vem da sua conexão de internet.</p></section>`;
  const r = SOC.rank;
  const chave = q.tipo + q.periodo + q.escopo;
  if (!r || r.chave !== chave) {
    if (podeCarregar()) { SOC.carregando = true; carrega(async () => { try { const j = await socApi(`/ranking?tipo=${q.tipo}&periodo=${q.periodo}&escopo=${q.escopo}`); j.chave = chave; SOC.rank = j; if (q.escopo === 'cidade' && q.tipo === 'tempo' && q.periodo === 'semana' && j.eu && j.eu.pos && j.eu.pos <= 10 && j.eu.valor >= 600 && j.lista.length >= 3 && !G().cont.top10) gameConta('top10'); } finally { SOC.carregando = false; } }); }
    return h + falhou();
  }
  const local = { cidade: r.local.cidade, estado: r.local.estado, pais: nomePais(r.local.pais) }[q.escopo];
  const med = p => p === 1 ? '🥇' : p === 2 ? '🥈' : p === 3 ? '🥉' : p;
  const linha = x => `<button class="rk ${x.usuario.id === SOC.eu.id ? 'eu' : ''}" data-g="perfil" data-id="${esc(x.usuario.id)}"><span class="rkp">${x.pos ? med(x.pos) : '–'}</span>${avatar(x.usuario, 'sm')}<span class="rkn">${esc(x.usuario.nome)}<small class="muted"> ${esc([x.usuario.cidade, x.usuario.estado].filter(Boolean).join(', '))}</small></span><b>${fmtValor(x.valor, r.tipo)}</b></button>`;
  h += `<section class="card"><h3 style="margin-bottom:.6rem">${esc(ESCOPOS.find(e => e[0] === q.escopo)[1])}${local ? ': ' + esc(local) : ''}</h3>
    ${r.lista.length ? r.lista.map(linha).join('') : '<p class="muted">Ninguém leu neste período ainda. Leia alguns minutos e seja o primeiro!</p>'}
    ${r.eu && !r.lista.some(x => x.usuario.id === SOC.eu.id) ? '<div class="rksep">⋯</div>' + linha(r.eu) : ''}
    ${q.escopo === 'amigos' && r.lista.length <= 1 ? '<p class="small muted">Siga outros leitores na aba Amigos para disputar com eles.</p>' : ''}</section>`;
  return h;
}
function cartaoPessoa(u) {
  return `<div class="pess">${avatar(u)}<button class="pessn" data-g="perfil" data-id="${esc(u.id)}"><b>${esc(u.nome)}</b><small class="muted">nível ${u.nivel} · 🔥 ${u.streak} · ${u.horas} h lidas${u.cidade ? ' · ' + esc(u.cidade) : ''}</small></button>
    ${u.id !== (SOC.eu && SOC.eu.id) ? `<button class="btn sm ${u.eu_sigo ? '' : 'primary'}" data-g="seguir" data-id="${esc(u.id)}" data-v="${u.eu_sigo ? 1 : 0}">${u.eu_sigo ? 'Seguindo' : 'Seguir'}</button>` : ''}</div>`;
}
function telaPessoas() {
  if (!SOC.pessoas) { if (podeCarregar()) { SOC.carregando = true; carrega(async () => { try { SOC.pessoas = (await socApi('/usuarios?q=' + encodeURIComponent(SOC.pq))).usuarios; } finally { SOC.carregando = false; } }); } }
  return `<section class="card"><h2>👥 Encontre leitores</h2>
    <form class="fsearch" id="pessForm"><input id="pessQ" type="search" value="${esc(SOC.pq)}" placeholder="Nome de um amigo…" autocomplete="off"><button class="btn primary">Buscar</button></form>
    <p class="muted small">${SOC.pq ? 'Resultados' : 'Sugestões perto de você'}</p>
    ${SOC.pessoas ? (SOC.pessoas.length ? SOC.pessoas.map(cartaoPessoa).join('') : '<p class="muted">Ninguém encontrado.</p>') : '<p class="muted">Carregando…</p>'}
    <div class="bookact" style="margin-top:.6rem"><button class="btn sm" data-g="lista" data-v="seguindo" data-id="${esc(SOC.eu.id)}">Quem eu sigo</button><button class="btn sm" data-g="lista" data-v="seguidores" data-id="${esc(SOC.eu.id)}">Meus seguidores</button></div></section>`;
}
function cartaoComu(c) {
  return `<button class="comuc" data-g="comu" data-id="${esc(c.id)}"><span class="comue">${esc(c.emoji || '📚')}</span><span style="flex:1;min-width:0"><b>${esc(c.nome)}</b><small class="muted">${c.membros} ${c.membros === 1 ? 'membro' : 'membros'} · ${c.posts} posts${c.eu_membro ? ' · ✓ você participa' : ''}</small>${c.descricao ? `<small>${esc(c.descricao)}</small>` : ''}</span></button>`;
}
function telaComus() {
  if (!SOC.comus) { if (podeCarregar()) { SOC.carregando = true; carrega(async () => { try { const [a] = await Promise.all([socApi('/comunidades?q=' + encodeURIComponent(SOC.cq)), carregaMinhas()]); SOC.comus = a.comunidades; } finally { SOC.carregando = false; } }); } }
  const minhas = SOC.minhas || [];
  return `${minhas.length ? `<section class="card"><h2>Minhas comunidades</h2>${minhas.map(cartaoComu).join('')}</section>` : ''}
    <section class="card"><h2>🏘️ Comunidades de leitura</h2>
    <form class="fsearch" id="comuForm"><input id="comuQ" type="search" value="${esc(SOC.cq)}" placeholder="Tema, livro ou autor…" autocomplete="off"><button class="btn primary">Buscar</button></form>
    ${SOC.comus ? (SOC.comus.length ? SOC.comus.map(cartaoComu).join('') : '<p class="muted">Nenhuma comunidade encontrada. Crie a primeira!</p>') : '<p class="muted">Carregando…</p>'}</section>
    <section class="card"><h2>Criar comunidade</h2><form id="novaComu" class="ncomu">
      <div class="row"><label style="flex:0 0 5rem">Emoji<input name="emoji" maxlength="4" value="📚"></label><label style="flex:1">Nome<input name="nome" maxlength="60" required placeholder="Ex.: Clube do Machado de Assis"></label></div>
      <label>Tema<input name="tema" maxlength="60" placeholder="Ex.: literatura brasileira, terror, vestibular…"></label>
      <label>Descrição<textarea name="descricao" rows="2" maxlength="300" placeholder="Sobre o que vocês vão conversar?"></textarea></label>
      <button class="btn primary">Criar</button></form></section>`;
}
function telaComu() {
  const c = SOC.comu;
  if (!c) return falhou();
  const k = c.comunidade;
  return `<section class="card comuh"><button class="lnk" data-g="saba" data-v="comus">← Comunidades</button><div class="comut"><span class="comue big">${esc(k.emoji || '📚')}</span><div style="flex:1"><h2 style="margin:0">${esc(k.nome)}</h2><small class="muted">${k.membros} membros · ${k.posts} posts${k.tema ? ' · ' + esc(k.tema) : ''}</small></div>
    <button class="btn ${k.eu_membro ? '' : 'primary'}" data-g="comuentra" data-id="${esc(k.id)}" data-v="${k.eu_membro ? 1 : 0}">${k.eu_membro ? 'Sair' : 'Participar'}</button></div>${k.descricao ? `<p>${esc(k.descricao)}</p>` : ''}</section>
    ${k.eu_membro ? caixaPublicar('Escreva para a comunidade ' + k.nome + '…') : ''}
    ${c.posts.length ? c.posts.map(socPostHtml).join('') : '<div class="card empty">Nenhuma publicação ainda.</div>'}`;
}
function telaPerfil() {
  const alvo = SOC.aba === 'eu' ? SOC.eu.id : SOC.perfilId;
  const P = SOC.perfil;
  if (!P || P.usuario.id !== alvo) {
    if (podeCarregar()) { SOC.carregando = true; carrega(async () => { try { SOC.perfil = await socApi('/usuarios/' + encodeURIComponent(alvo)); } finally { SOC.carregando = false; } }); }
    return falhou();
  }
  const u = P.usuario, eu = u.eu;
  const local = [u.cidade, u.estado, u.pais ? nomePais(u.pais) : ''].filter(Boolean).join(', ');
  return `<section class="card perf">${avatar(u, 'lg')}<div style="flex:1;min-width:0"><h2 style="margin:0">${esc(u.nome)}</h2><small class="muted">Nível ${u.nivel} · ${esc(tituloDe(u.nivel))}${local ? ' · ' + esc(local) : ''}</small>
      ${u.bio ? `<p style="margin:.4rem 0">${esc(u.bio)}</p>` : ''}${u.lendo ? `<p class="small" style="margin:.3rem 0">📖 Lendo: <b>${esc(u.lendo)}</b></p>` : ''}
      <div class="pstats"><span><b>🔥 ${u.streak}</b>sequência</span><span><b>${u.horas} h</b>lidas</span><span><b>${u.conquistas}</b>conquistas</span><button data-g="lista" data-v="seguidores" data-id="${esc(u.id)}"><b>${u.seguidores}</b>seguidores</button><button data-g="lista" data-v="seguindo" data-id="${esc(u.id)}"><b>${u.seguindo}</b>seguindo</button></div>
      <div class="bookact">${eu ? '<button class="btn sm" data-g="editbio">✏️ Editar perfil</button><button class="btn sm" data-g="socsair">Sair da Comunidade</button>'
        : `<button class="btn sm ${u.eu_sigo ? '' : 'primary'}" data-g="seguir" data-id="${esc(u.id)}" data-v="${u.eu_sigo ? 1 : 0}">${u.eu_sigo ? 'Seguindo' : 'Seguir'}</button><button class="btn sm" data-g="bloquear" data-id="${esc(u.id)}" data-v="${u.bloqueado ? 1 : 0}">${u.bloqueado ? 'Desbloquear' : 'Bloquear'}</button>`}</div></div></section>
    ${P.lista ? `<section class="card"><h3>${P.lista.titulo}</h3>${P.lista.usuarios.length ? P.lista.usuarios.map(cartaoPessoa).join('') : '<p class="muted">Ninguém por aqui ainda.</p>'}</section>` : ''}
    ${eu ? caixaPublicar() : ''}
    ${P.posts.length ? P.posts.map(socPostHtml).join('') : '<div class="card empty">Nenhuma publicação ainda.</div>'}
    ${eu ? '<p class="center"><button class="btn sm danger" data-g="apagaconta">Apagar minha conta da Comunidade</button></p>' : ''}`;
}

/* ---------- posts dos amigos dentro do "Para você" ---------- */
function misturaSocial(html) {
  if (!SOC.token || !SOC.feed || !SOC.feed.length || feed.filter === 'saved') return html;
  const partes = html.split('<article class="post"');
  if (partes.length < 3) return html;
  const sp = SOC.feed.slice(0, 8);
  let out = partes[0], k = 0;
  for (let i = 1; i < partes.length; i++) {
    out += '<article class="post"' + partes[i];
    if (i % 3 === 0 && k < sp.length) out += socPostHtml(sp[k++]);
  }
  return out;
}

/* ---------- ligações com as telas que já existem ---------- */
const _vToday7 = VIEWS.today;
VIEWS.today = () => cartaoJogo() + _vToday7();
const _vStats7 = VIEWS.stats;
VIEWS.stats = () => _vStats7() + gradeConquistas();
const _vFor7 = VIEWS.foryou;
VIEWS.foryou = () => {
  if (SOC.token && !SOC.feed && podeCarregar()) { SOC.carregando = true; carrega(async () => { try { await carregaFeed(false); } finally { SOC.carregando = false; } }); }
  const h = _vFor7();
  const comp = SOC.token ? caixaPublicar() : '';
  return misturaSocial(h.replace('<div class="stories">', comp + '<div class="stories">'));
};
VIEWS.social = renderSocial;
const _vSet7 = VIEWS.settings;
VIEWS.settings = () => {
  const t = temaEscolhido(), n = notifCfg();
  const ap = `<section class="card"><h2>Aparência</h2><div class="rsel">${[['auto', '🌗 Automático'], ['claro', '☀️ Claro'], ['escuro', '🌙 Escuro']].map(([v, l]) => `<button class="chip ${t === v ? 'on' : ''}" data-g="tema" data-v="${v}">${l}</button>`).join('')}</div>
    <p class="muted small" style="margin:.5rem 0 0">Automático segue o tema do celular ou do computador.</p></section>
    <section class="card"><h2>💭 Reflexões</h2><p class="muted small" style="margin-top:0">Notificações com frases e perguntas que puxam o pensamento crítico, ${APP.plat === 'android' ? 'no celular' : 'no Windows'}, mesmo com o app fechado.</p>
      <label class="tgl"><input type="checkbox" id="notOn" ${n.on ? 'checked' : ''} data-g="notif"> Receber reflexões</label>
      <div class="row" style="margin-top:.4rem">${[0, 1, 2].map(i => `<label style="flex:1">${i + 1}º horário<input type="time" class="notH" value="${esc(n.horas[i] || '')}" ${n.on ? '' : 'disabled'}></label>`).join('')}</div>
      <div class="bookact" style="margin-top:.5rem"><button class="btn sm primary" data-g="notifsalva">Salvar horários</button><button class="btn sm" data-g="notifteste">Ver uma agora</button></div></section>
    <section class="card"><h2>🧭 Tutorial</h2><p class="muted small" style="margin-top:0">Reveja o passo a passo de como usar o Páginas.</p><button class="btn sm" data-g="tutorial">Ver o tutorial</button></section>`;
  return _vSet7() + ap;
};

/* ---------- compartilhar a partir do leitor, do livro e das resenhas ---------- */
const _showTool7 = showTool;
showTool = function (sel) {
  _showTool7(sel);
  const el = $('#rtool');
  if (el && SOC.token) { el.insertAdjacentHTML('beforeend', '<button data-g="sharesel">💬 Compartilhar</button>'); el.style.width = 'auto'; }
};
const _readerShell7 = readerShell;
readerShell = function (inner, theme) {
  if (SOC.token) inner = inner.replace('<button class="btn sm" data-x="hllist"', '<button class="btn sm" data-g="sharepage" title="Compartilhar este trecho">💬</button><button class="btn sm" data-x="hllist"');
  return _readerShell7(inner, theme);
};
const _paintPanel7 = paintPanel;
paintPanel = function () {
  _paintPanel7();
  const p = HS.panel, a = document.querySelector('.hpa');
  if (SOC.token && p && p.text && a && !a.querySelector('[data-g=sharepanel]')) a.insertAdjacentHTML('beforeend', '<button class="btn sm" data-g="sharepanel">💬 Compartilhar</button>');
};
const _explain7 = explain;
explain = function (o) { gameConta('ia'); return _explain7.apply(this, arguments); };
function trechoDaPagina() {
  const el = $('#rbody article'); if (!el) return '';
  const t = el.innerText.replace(/\s+\n/g, '\n').trim();
  return t.length > 700 ? t.slice(0, 700).replace(/\s+\S*$/, '') + '…' : t;
}
document.addEventListener('submit', e => {
  const f = e.target;
  if (f.id === 'finForm' && SOC.token) {
    const b = state.books.find(x => x.id === fin.id), note = (f.note && f.note.value || '').trim(), nota = fin.rating;
    if (b) setTimeout(() => { if (confirm('Livro concluído! 🎉 Quer compartilhar ' + (note ? 'sua resenha' : 'que terminou') + ' com a Comunidade?')) abrirComposer({ tipo: 'resenha', texto: note || ('Terminei de ler “' + b.title + '”!'), nota, livro: b.title, livro_autor: b.author || '', gid: b.gid || '' }); }, 400);
  }
  if (f.id === 'compForm') { e.preventDefault(); publicar(); }
  if (f.classList.contains('cmf')) {
    e.preventDefault();
    const id = f.dataset.p, t = f.t.value.trim(); if (!t) return;
    f.t.value = '';
    carrega(async () => { await socApi('/posts/' + id + '/comentarios', { method: 'POST', body: { texto: t } }); const p = achaPost(id); if (p) p.comentarios++; SOC.coment[id] = { lista: (await socApi('/posts/' + id + '/comentarios')).comentarios }; repintaPost(id); });
  }
  if (f.id === 'pessForm') { e.preventDefault(); SOC.pq = $('#pessQ').value.trim(); SOC.pessoas = null; render(); }
  if (f.id === 'comuForm') { e.preventDefault(); SOC.cq = $('#comuQ').value.trim(); SOC.comus = null; render(); }
  if (f.id === 'novaComu') {
    e.preventDefault();
    const d = { nome: f.nome.value, emoji: f.emoji.value, tema: f.tema.value, descricao: f.descricao.value };
    carrega(async () => { const j = await socApi('/comunidades', { method: 'POST', body: d }); gameConta('comunidades'); SOC.comus = null; SOC.minhas = null; await abreComu(j.comunidade.id); toast('Comunidade criada!'); });
  }
}, true);
async function abreComu(id) {
  SOC.aba = 'comu'; SOC.comu = null; render();
  SOC.comu = await socApi('/comunidades/' + encodeURIComponent(id));
}
function irSocial(aba) { view = 'social'; SOC.aba = aba || SOC.aba; render(); window.scrollTo(0, 0); }

/* ---------- cliques ---------- */
document.addEventListener('click', e => {
  // quiz respondido (conta para missões e conquistas)
  const qz = e.target.closest('[data-x=pquiz]');
  if (qz && !(qz.dataset.id in feed.quiz)) {
    const id = qz.dataset.id, v = Number(qz.dataset.v);
    setTimeout(() => { const p = feed.byId[id]; gameConta('quiz'); if (p && p.a === v) gameConta('quizOk'); }, 0);
  }
  const el = e.target.closest('[data-g]'); if (!el) return;
  const a = el.dataset.g, id = el.dataset.id, v = el.dataset.v;
  switch (a) {
    case 'tema': state.settings.tema = v; Store.save(state); aplicaTema(); render(); break;
    case 'irconq': view = 'stats'; render(); setTimeout(() => { const c = $('#conq'); if (c) c.scrollIntoView({ behavior: 'smooth' }); }, 50); break;
    case 'irrank': irSocial('rank'); break;
    case 'celok': fechaCel(); break;
    case 'celshare': { const c = $('#cel'); const n = c && c.dataset.nome, em = c && c.dataset.e; fechaCel(); abrirComposer({ tipo: 'conquista', texto: `${em} Desbloqueei a conquista “${n}” no Páginas!` }); break; }
    case 'tutorial': tutorialInicia(); break;
    case 'tutprox': TUT.i++; tutorialMostra(); break;
    case 'tutvolta': TUT.i = Math.max(0, TUT.i - 1); tutorialMostra(); break;
    case 'tutpular': tutorialFim(false); break;
    case 'notif': {
      const on = el.checked;
      document.querySelectorAll('.notH').forEach(i => { i.disabled = !on; });
      if (on && APP.plat === 'android' && window.PaginasAndroid && PaginasAndroid.pedirPermissao) PaginasAndroid.pedirPermissao();
      state.settings.reflex = Object.assign(notifCfg(), { on }); Store.save(state); aplicaNotif(true);
      break;
    }
    case 'notifsalva': {
      const horas = [...document.querySelectorAll('.notH')].map(i => i.value).filter(Boolean);
      state.settings.reflex = Object.assign(notifCfg(), { horas: horas.length ? horas : ['09:00'] }); Store.save(state); aplicaNotif(true);
      break;
    }
    case 'notifteste': {
      const l = reflexoes(), r = l[Math.floor(Math.random() * l.length)];
      if (APP.plat === 'android' && window.PaginasAndroid && PaginasAndroid.reflexaoAgora) PaginasAndroid.reflexaoAgora();
      else if (IS_APP && APP.plat === 'windows') api('/api/notif/teste', { method: 'POST' }).catch(() => toast('💭 ' + r.t));
      else toast('💭 ' + r.t);
      break;
    }
    case 'reflshare': { const r = reflexaoDoDia(); abrirComposer({ tipo: 'frase', texto: r.t + (r.a ? ' — ' + r.a : '') }); break; }
    case 'socentrar': socEntrar(false); break;
    case 'socsair': if (confirm('Sair da Comunidade neste aparelho?')) { socApi('/sair', { method: 'POST' }).catch(() => {}); SOC.token = ''; SOC.eu = null; SOC.tentou = true; socGuarda(); render(); } break;
    case 'apagaconta':
      if (confirm('Apagar sua conta da Comunidade? Seus posts, comentários, seguidores e posição nos rankings serão apagados para sempre. Seus livros e progresso neste aparelho continuam.'))
        carrega(async () => { await socApi('/eu', { method: 'DELETE' }); SOC.token = ''; SOC.eu = null; SOC.tentou = true; socGuarda(); toast('Conta da Comunidade apagada.'); });
      break;
    case 'saba': SOC.aba = v; if (v === 'eu') SOC.perfil = null; if (v === 'feed') SOC.feed = SOC.feed; render(); window.scrollTo(0, 0); break;
    case 'compor': abrirComposer(); break;
    case 'compfecha': COMP.aberto = false; pintaComposer(); break;
    case 'comptipo': lerComposer(); COMP.d.tipo = v; pintaComposer(); break;
    case 'compnota': lerComposer(); COMP.d.nota = Number(v); pintaComposer(); break;
    case 'feedmais': carrega(() => carregaFeed(true)); break;
    case 'curtir': {
      const p = achaPost(id); if (!p) break;
      p.curti = !p.curti; p.curtidas += p.curti ? 1 : -1; repintaPost(id);
      socApi('/posts/' + id + '/curtir', { method: 'POST' }).then(j => { p.curti = j.curti; p.curtidas = j.curtidas; repintaPost(id); if (j.curti && !p.meu) gameConta('curtidas'); })
        .catch(err => { p.curti = !p.curti; p.curtidas += p.curti ? 1 : -1; repintaPost(id); toast(err.message); });
      break;
    }
    case 'coments':
      if (SOC.coment[id]) { delete SOC.coment[id]; repintaPost(id); break; }
      SOC.coment[id] = {}; repintaPost(id);
      socApi('/posts/' + id + '/comentarios').then(j => { SOC.coment[id] = { lista: j.comentarios }; repintaPost(id); }).catch(err => toast(err.message));
      break;
    case 'cmdel': if (confirm('Apagar este comentário?')) carrega(async () => { await socApi('/comentarios/' + id, { method: 'DELETE' }); const p = achaPost(el.dataset.p); if (p) p.comentarios--; SOC.coment[el.dataset.p] = { lista: (await socApi('/posts/' + el.dataset.p + '/comentarios')).comentarios }; repintaPost(el.dataset.p); }); break;
    case 'postmenu': {
      const p = achaPost(id); if (!p) break;
      if (p.meu) { if (confirm('Apagar esta publicação?')) carrega(async () => { await socApi('/posts/' + id, { method: 'DELETE' }); for (const l of [SOC.feed, SOC.comu && SOC.comu.posts, SOC.perfil && SOC.perfil.posts]) if (l) { const i = l.findIndex(x => x.id === id); if (i >= 0) l.splice(i, 1); } toast('Publicação apagada.'); }); }
      else if (confirm('Denunciar esta publicação como ofensiva, spam ou imprópria?\n\nCom algumas denúncias ela some para todos.')) carrega(async () => { await socApi('/denunciar', { method: 'POST', body: { alvo: id } }); toast('Obrigado. A denúncia foi registrada.'); });
      break;
    }
    case 'perfil': SOC.perfilId = id; SOC.aba = id === (SOC.eu && SOC.eu.id) ? 'eu' : 'perfil'; SOC.perfil = null; irSocial(); break;
    case 'lista': {
      const tit = v === 'seguidores' ? 'Seguidores' : 'Seguindo';
      carrega(async () => {
        const j = await socApi('/usuarios/' + encodeURIComponent(id) + '/' + v);
        if (!SOC.perfil || SOC.perfil.usuario.id !== id) { SOC.perfilId = id; SOC.aba = id === SOC.eu.id ? 'eu' : 'perfil'; SOC.perfil = await socApi('/usuarios/' + encodeURIComponent(id)); view = 'social'; }
        SOC.perfil.lista = { titulo: tit, usuarios: j.usuarios };
      });
      break;
    }
    case 'seguir': {
      const segue = v === '1';
      carrega(async () => {
        const j = await socApi('/seguir/' + id, { method: segue ? 'DELETE' : 'POST' });
        for (const l of [SOC.pessoas, SOC.perfil && SOC.perfil.lista && SOC.perfil.lista.usuarios]) if (l) l.forEach(u => { if (u.id === id) u.eu_sigo = j.eu_sigo; });
        if (SOC.perfil && SOC.perfil.usuario.id === id) { SOC.perfil.usuario.eu_sigo = j.eu_sigo; SOC.perfil.usuario.seguidores += j.eu_sigo ? 1 : -1; }
        G().cont.seguindo = Math.max(0, (G().cont.seguindo || 0) + (j.eu_sigo ? 1 : -1)); Store.save(state);
        SOC.feed = null; SOC.rank = null;
      });
      break;
    }
    case 'bloquear': {
      const bl = v === '1';
      if (!bl && !confirm('Bloquear esta pessoa? Vocês deixam de se seguir e você não verá mais as publicações dela.')) break;
      carrega(async () => { await socApi('/bloquear/' + id, { method: bl ? 'DELETE' : 'POST' }); SOC.perfil = null; SOC.feed = null; toast(bl ? 'Desbloqueado.' : 'Bloqueado.'); });
      break;
    }
    case 'editbio': {
      const u = SOC.perfil.usuario;
      const nome = prompt('Seu nome na Comunidade:', u.nome); if (nome == null) break;
      const bio = prompt('Uma frase sobre você como leitor(a):', u.bio || ''); if (bio == null) break;
      carrega(async () => { await socApi('/perfil', { method: 'POST', body: { nome, bio } }); SOC.perfil = null; SOC.eu = Object.assign(SOC.eu || {}, { nome }); socGuarda(); });
      break;
    }
    case 'comu': carrega(() => abreComu(id)); view = 'social'; break;
    case 'comuentra': {
      const sair = v === '1';
      carrega(async () => { await socApi('/comunidades/' + id + (sair ? '/sair' : '/entrar'), { method: 'POST' }); await abreComu(id); await carregaMinhas(); SOC.comus = null; SOC.feed = null; if (!sair) toast('Você entrou na comunidade!'); Store.save(state); });
      break;
    }
    case 'retry': SOC.erroEm = 0; SOC.erro = ''; render(); break;
    case 'rq': SOC.rq[el.dataset.k] = v; render(); break;
    case 'buscalivro': view = 'library'; render(); setTimeout(() => { const q = $('#libQ') || document.querySelector('#libForm input,[type=search]'); if (q) { q.value = el.dataset.q; const f = q.closest('form'); if (f) f.requestSubmit(); } }, 30); break;
    case 'sharesel': { const s = HS.sel; if (!s || !R) break; clearSel(); abrirComposer({ tipo: 'frase', texto: s.text, livro: R.b.title, livro_autor: R.b.author || '', gid: R.b.gid || '', pagina: R.idx + 1 }); break; }
    case 'sharepanel': { const p = HS.panel; if (!p || !R) break; abrirComposer({ tipo: 'frase', texto: p.text, livro: R.b.title, livro_autor: R.b.author || '', gid: R.b.gid || '', pagina: R.idx + 1 }); break; }
    case 'sharepage': if (R) abrirComposer({ tipo: 'pagina', texto: trechoDaPagina(), livro: R.b.title, livro_autor: R.b.author || '', gid: R.b.gid || '', pagina: R.idx + 1 }); break;
  }
});
document.addEventListener('keydown', e => { if (e.key === 'Escape') { if (COMP.aberto) { COMP.aberto = false; pintaComposer(); } if ($('#cel')) fechaCel(); } });

/* ---------- aba ativa sempre visível na barra (celular) ---------- */
const _render7 = render;
render = function () { _render7(); const t = document.querySelector('.tab.on'); if (t && t.parentNode.scrollWidth > t.parentNode.clientWidth) t.parentNode.scrollTo({ left: t.offsetLeft - 40, behavior: 'smooth' }); };

/* ---------- início ---------- */
aplicaTema();
const _save7 = Store.save;
Store.save = function (s) { const r = _save7.call(Store, s); if (!_jogoAndando) agendaJogo(); return r; };
setTimeout(function inicio7() {
  if (!window.__booted) return setTimeout(inicio7, 200);
  aplicaTema(); verificaJogo();
  const n = notifCfg(); if (n.on) aplicaNotif(false);
  // tutorial na primeira vez (depois do questionário de gostos)
  const onbAberto = () => { const o = $('#onb'); return o && !o.hidden; };
  (function espera() {
    if (onbAberto() || $('#splash')) return setTimeout(espera, 600);
    if (!G().tutVisto && state.profile) setTimeout(tutorialInicia, 400);
  })();
  if (SOC.token) { socApi('/eu').then(j => { SOC.eu = j.eu; socGuarda(); }).catch(() => {}); socPerfilDepois(true); }
  else if (SOC.url) setTimeout(async () => { await gStatus(); if (GS.connected) socEntrar(true); }, 2500);
}, 300);
setInterval(() => { if (typeof R !== 'undefined' && R) agendaJogo(); }, 60000);

(function () {
  const sp = document.getElementById('splash'); if (!sp) return;
  const t0 = performance.now();
  const hide = () => { sp.classList.add('out'); setTimeout(() => sp.remove(), 700); };
  const tick = () => {
    const t = performance.now() - t0;
    if ((window.__booted && t > 1100) || t > 9000) hide(); else setTimeout(tick, 120);
  };
  tick();
})();
</script>
<script type="application/json" id="reflexoes">[{"t": "Pense numa opinião forte que você tem. Em que fatos ela se apoia, e quais desses fatos você já conferiu de verdade?", "a": ""}, {"t": "Qual foi a última vez que você mudou de ideia sobre algo importante? O que te convenceu?", "a": ""}, {"t": "Lembre de um personagem de quem você não gosta. Que motivos ele teria para agir como age, do ponto de vista dele?", "a": ""}, {"t": "Se alguém defendesse o oposto do que você pensa sobre um assunto, qual seria o melhor argumento dessa pessoa?", "a": ""}, {"t": "Uma notícia que te deixou indignado(a) esta semana: você leu a fonte original ou só o título?", "a": ""}, {"t": "O que você sabe hoje que, há cinco anos, acharia impossível de entender?", "a": ""}, {"t": "Qual pergunta você evita fazer a si mesmo(a)? Por quê?", "a": ""}, {"t": "Que livro mudou a forma como você vê alguma coisa? O que exatamente mudou?", "a": ""}, {"t": "Diferencie: o que você acredita porque pensou, e o que acredita porque sempre ouviu dizer?", "a": ""}, {"t": "Se você pudesse fazer uma única pergunta a um autor que já morreu, quem seria e o que perguntaria?", "a": ""}, {"t": "Que hábito pequeno, repetido por um ano, mudaria mais a sua vida?", "a": ""}, {"t": "Quando foi a última vez que você disse “não sei” sem medo? Saber que não sabe também é saber.", "a": ""}, {"t": "Uma história é contada de um ponto de vista. Como seria a última coisa que você leu contada por outro personagem?", "a": ""}, {"t": "O que torna um argumento convincente para você: a lógica, a emoção ou quem está falando?", "a": ""}, {"t": "Qual é a diferença entre ter informação e ter conhecimento?", "a": ""}, {"t": "Que ideia você já defendeu e hoje acha errada? O que isso ensina sobre as ideias que você defende agora?", "a": ""}, {"t": "Ler é conversar com alguém que não está aqui. Com quem você conversou hoje?", "a": ""}, {"t": "O que você faria diferente se ninguém nunca soubesse o que você fez?", "a": ""}, {"t": "Pense numa decisão recente. Você escolheu, ou só seguiu o que era mais fácil?", "a": ""}, {"t": "Que palavra você usa sempre sem saber exatamente o que ela significa? Que tal descobrir hoje?", "a": ""}, {"t": "Um bom leitor desconfia até do livro de que gosta. Qual trecho do seu livro atual você questionaria?", "a": ""}, {"t": "Se o mundo inteiro lesse um único livro, qual você escolheria? E qual seria o risco disso?", "a": ""}, {"t": "O que é mais difícil: aprender algo novo ou desaprender algo antigo?", "a": ""}, {"t": "Quando você discorda de alguém, você tenta entender ou tenta vencer?", "a": ""}, {"t": "Que assunto você acha chato? Será que é o assunto, ou o jeito como te apresentaram?", "a": ""}, {"t": "Escreva mentalmente uma frase sobre o seu dia que mereceria estar num livro.", "a": ""}, {"t": "Qual é a sua maior certeza? O que precisaria acontecer para você duvidar dela?", "a": ""}, {"t": "Liberdade é poder fazer qualquer coisa, ou poder escolher o que vale a pena fazer?", "a": ""}, {"t": "Uma pessoa pode ser boa e fazer algo errado? Pense num exemplo de um livro.", "a": ""}, {"t": "O que a sua leitura de hoje tem a ver com a sua vida? Toda história fala de alguém, mesmo que não pareça.", "a": ""}, {"t": "Se você explicasse o que está lendo para uma criança de dez anos, o que diria?", "a": ""}, {"t": "O que é justiça para você? E para o personagem do livro que está lendo?", "a": ""}, {"t": "Que voz falta na história que você está lendo? Quem não tem chance de falar?", "a": ""}, {"t": "Você lê para fugir do mundo ou para entendê-lo melhor? Os dois valem.", "a": ""}, {"t": "Que pergunta este dia deixou sem resposta?", "a": ""}, {"t": "Ser curioso é admitir que existe muito que não se sabe. O que você quer descobrir esta semana?", "a": ""}, {"t": "A primeira impressão sobre alguém costuma estar certa? Lembre de um personagem que te enganou.", "a": ""}, {"t": "Se você pudesse viver dentro de um livro por um dia, qual seria e o que faria?", "a": ""}, {"t": "Qual é a diferença entre uma opinião e um fato? Encontre um exemplo no que você leu hoje.", "a": ""}, {"t": "Por que algumas histórias de séculos atrás ainda falam com a gente hoje?", "a": ""}, {"t": "Conhece-te a ti mesmo.", "a": "Inscrição do templo de Apolo em Delfos"}, {"t": "Uma vida sem reflexão não vale a pena ser vivida.", "a": "Sócrates, segundo Platão"}, {"t": "Ninguém se banha duas vezes no mesmo rio.", "a": "Heráclito"}, {"t": "Penso, logo existo.", "a": "René Descartes"}, {"t": "O coração tem razões que a própria razão desconhece.", "a": "Blaise Pascal"}, {"t": "Não são as coisas que perturbam os homens, mas as opiniões que eles têm sobre elas.", "a": "Epicteto"}, {"t": "Não é porque as coisas são difíceis que não ousamos; é porque não ousamos que elas são difíceis.", "a": "Sêneca"}, {"t": "Enquanto adiamos, a vida passa.", "a": "Sêneca"}, {"t": "Ousa saber!", "a": "Horácio (lema adotado por Kant)"}, {"t": "Há mais coisas entre o céu e a terra, Horácio, do que sonha a tua filosofia.", "a": "William Shakespeare, Hamlet"}, {"t": "Não existe nada bom ou mau, mas o pensamento o faz assim.", "a": "William Shakespeare, Hamlet"}, {"t": "Quem tem um porquê para viver suporta quase qualquer como.", "a": "Friedrich Nietzsche"}, {"t": "Ao vencido, ódio ou compaixão; ao vencedor, as batatas.", "a": "Machado de Assis, Quincas Borba"}, {"t": "Mudam-se os tempos, mudam-se as vontades.", "a": "Luís de Camões"}, {"t": "Tudo vale a pena se a alma não é pequena.", "a": "Fernando Pessoa, Mensagem"}, {"t": "Ler é sonhar pela mão de outrem.", "a": "Fernando Pessoa, Livro do Desassossego"}, {"t": "Um país se faz com homens e livros.", "a": "Monteiro Lobato"}, {"t": "Todas as famílias felizes se parecem; cada família infeliz é infeliz à sua maneira.", "a": "Liev Tolstói, Anna Kariênina"}, {"t": "O essencial é invisível aos olhos.", "a": "Antoine de Saint-Exupéry, O Pequeno Príncipe"}, {"t": "Navegar é preciso; viver não é preciso.", "a": "Frase dos navegantes antigos, retomada por Fernando Pessoa"}]</script>
<style>
/* ---- parte 7: jogo, tutorial, comunidade ---- */
@media(max-width:760px){.bar{flex-wrap:nowrap;gap:.5rem}nav{flex-wrap:nowrap;overflow-x:auto;scrollbar-width:none;-webkit-overflow-scrolling:touch;min-width:0}nav::-webkit-scrollbar{display:none}.tab{flex:none;padding:.45rem .75rem}.brand{font-size:1.3rem}}
.post,.card.jogo{content-visibility:auto;contain-intrinsic-size:auto 260px}
.jogo{background:linear-gradient(135deg,color-mix(in srgb,var(--accent) 12%,var(--card)),var(--card) 60%)}
.jtop{display:flex;align-items:center;gap:.8rem}
.jlvl{width:54px;height:54px;flex:none;border-radius:16px;background:linear-gradient(135deg,var(--accent),var(--warn));display:grid;place-items:center;color:#fff;font:800 1.5rem Georgia,serif;box-shadow:0 6px 16px -6px var(--accent)}
.xpbar,.mbar{height:8px;border-radius:9px;background:var(--track);overflow:hidden;margin:.3rem 0 .15rem}
.xpbar i,.mbar i{display:block;height:100%;border-radius:9px;background:linear-gradient(90deg,var(--accent),var(--warn));transition:width .6s var(--ease,ease)}
.mbar{height:5px;margin:.25rem 0 0}
.jstreak{border:1px solid var(--line);background:var(--card);border-radius:14px;padding:.35rem .6rem;font-size:1.2rem;cursor:pointer;color:var(--ink)}
.jstreak b{font-size:1.1rem;margin-left:.15rem}
.jmiss{margin-top:.9rem;border-top:1px dashed var(--line);padding-top:.7rem}
.jmh{display:flex;justify-content:space-between;align-items:baseline;gap:.5rem;flex-wrap:wrap;margin-bottom:.3rem}
.jm{display:flex;align-items:center;gap:.6rem;padding:.4rem 0;font-size:.93rem}
.jm.ok{opacity:.65}.jm.ok>div>div:first-child{text-decoration:line-through}
.jme{width:1.6rem;text-align:center;font-size:1.15rem}
.jxp{color:var(--accent);font-weight:700}
.jfoot{display:flex;gap:.5rem;flex-wrap:wrap;margin-top:.6rem}
.refl p{font:italic 1.08rem/1.5 Georgia,serif;margin:.35rem 0}
.cqgrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:.6rem}
.cq{border:1px solid var(--line);border-radius:14px;padding:.7rem;display:flex;flex-direction:column;gap:.15rem;opacity:.7}
.cq.ok{opacity:1;background:color-mix(in srgb,var(--accent) 8%,var(--card));border-color:color-mix(in srgb,var(--accent) 35%,var(--line))}
.cqe{font-size:1.8rem}.cq b{font-size:.92rem}.cq small{font-size:.75rem;color:var(--muted)}.cqd{color:var(--accent)!important}
.cel{position:fixed;inset:0;z-index:100;background:rgba(0,0,0,.55);display:grid;place-items:center;padding:1rem;animation:fadein .25s}
.celbox{background:var(--card);border-radius:22px;padding:1.6rem 1.4rem;text-align:center;max-width:340px;width:100%;box-shadow:0 30px 60px -20px rgba(0,0,0,.6);animation:pop .45s cubic-bezier(.2,1.4,.4,1)}
.celbox small{text-transform:uppercase;letter-spacing:.08em;color:var(--muted);font-size:.72rem}
.cele{font-size:4.2rem;line-height:1.2;margin:.4rem 0;animation:bounce 1.2s .3s ease-in-out}
.celxp{display:inline-block;margin:.2rem 0 .9rem;padding:.25rem .8rem;border-radius:999px;background:linear-gradient(90deg,var(--accent),var(--warn));color:#fff}
.celconf{position:absolute;inset:0;overflow:hidden;pointer-events:none}
.celconf i{position:absolute;top:-12px;width:9px;height:14px;border-radius:2px;animation:conf 1.8s ease-in forwards;transform:rotate(var(--r))}
@keyframes conf{to{transform:translateY(105vh) rotate(calc(var(--r) + 540deg));opacity:.3}}
@keyframes pop{from{transform:scale(.6);opacity:0}to{transform:none;opacity:1}}
@keyframes bounce{0%,100%{transform:none}30%{transform:translateY(-14px) scale(1.1)}60%{transform:translateY(2px)}}
@keyframes fadein{from{opacity:0}}
#tut{position:fixed;inset:0;z-index:90}
.tutspot{position:fixed;border-radius:14px;box-shadow:0 0 0 9999px rgba(0,0,0,.62);transition:all .3s var(--ease,ease);pointer-events:none}
.tutspot.meio{left:50%;top:50%;width:0;height:0}
.tutbox{position:fixed;background:var(--card);color:var(--ink);border-radius:18px;padding:1rem 1.1rem;max-width:340px;width:calc(100% - 16px);box-shadow:0 20px 50px -15px rgba(0,0,0,.6);animation:pop .3s}
.tutbox.meio{left:50%;top:50%;transform:translate(-50%,-50%);animation:none}
.tutbox h3{margin:.2rem 0 .3rem}.tutbox p{margin:0 0 .8rem}
.stabs,.rsel{display:flex;gap:.4rem;overflow-x:auto;scrollbar-width:none;padding:.1rem 0 .7rem}
.rsel{padding:.3rem 0 0;flex-wrap:wrap}
.stabs .chip,.rsel .chip{flex:none}
.chip.on{background:var(--accent);color:var(--accent-ink);border-color:var(--accent)}
.av{width:38px;height:38px;border-radius:50%;object-fit:cover;flex:none;display:inline-grid;place-items:center;font-weight:700;color:#fff;background:hsl(var(--h,20) 45% 48%)}
.av.sm{width:28px;height:28px;font-size:.8rem}.av.lg{width:76px;height:76px;font-size:1.8rem}
.spost .sph{display:flex;gap:.6rem;align-items:center;padding:.8rem .9rem 0}
.spn,.spc,.lnk{background:none;border:0;padding:0;font:inherit;color:var(--ink);font-weight:700;cursor:pointer}
.spc,.lnk{font-weight:600;color:var(--accent)}.lnk{font-size:.85rem}
.lv{font-size:.7rem;background:var(--track);border-radius:6px;padding:.05rem .35rem;color:var(--muted)}
.spm{background:none;border:0;font-size:1.3rem;color:var(--muted);cursor:pointer;padding:.2rem .4rem}
.spt{white-space:pre-wrap;margin:.2rem 0}
.spq{margin:.3rem 0;padding:.2rem 0 .2rem .9rem;border-left:3px solid var(--accent);font:italic 1.05rem/1.55 Georgia,serif;white-space:pre-wrap}
.splv{display:inline-block;margin-top:.5rem;border:1px solid var(--line);background:var(--bg);border-radius:10px;padding:.3rem .6rem;font:inherit;font-size:.85rem;color:var(--ink);cursor:pointer}
.spst{color:var(--warn);letter-spacing:.1em}
.spa{display:flex;gap:.3rem;padding:0 .6rem .6rem}
.spa button{background:none;border:0;border-radius:10px;padding:.35rem .6rem;font:inherit;color:var(--muted);cursor:pointer}
.spa button:hover,.spa button.on{background:var(--track);color:var(--ink)}
.spcm{border-top:1px solid var(--line);padding:.6rem .9rem .8rem;display:flex;flex-direction:column;gap:.5rem}
.cmi{display:flex;gap:.5rem;font-size:.92rem}
.cmf{display:flex;gap:.4rem}.cmf input{flex:1;min-width:0}
.scomp{display:flex;align-items:center;gap:.7rem;width:100%;text-align:left;cursor:pointer;font:inherit;color:inherit}
.smodal{position:fixed;inset:0;z-index:80;background:rgba(0,0,0,.5);display:flex;align-items:flex-end;justify-content:center;animation:fadein .2s}
.smbox{background:var(--card);width:100%;max-width:560px;border-radius:20px 20px 0 0;padding:1rem;display:flex;flex-direction:column;gap:.6rem;max-height:92vh;overflow:auto}
@media(min-width:700px){.smodal{align-items:center}.smbox{border-radius:20px}}
.smbox textarea,.smbox select,.ncomu input,.ncomu textarea{width:100%}
.ctipos{display:flex;gap:.35rem;flex-wrap:wrap}
.rk{display:flex;align-items:center;gap:.6rem;width:100%;border:0;background:none;padding:.5rem .3rem;border-bottom:1px solid var(--line);font:inherit;color:inherit;cursor:pointer;text-align:left}
.rk.eu{background:color-mix(in srgb,var(--accent) 12%,transparent);border-radius:10px}
.rkp{width:2rem;text-align:center;font-weight:700}.rkn{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.rksep{text-align:center;color:var(--muted)}
.pess{display:flex;align-items:center;gap:.6rem;padding:.5rem 0;border-bottom:1px solid var(--line)}
.pessn{flex:1;min-width:0;background:none;border:0;text-align:left;font:inherit;color:inherit;cursor:pointer;display:flex;flex-direction:column}
.comuc{display:flex;gap:.7rem;align-items:flex-start;width:100%;text-align:left;border:1px solid var(--line);background:var(--bg);border-radius:14px;padding:.7rem;margin:.4rem 0;font:inherit;color:inherit;cursor:pointer}
.comuc small{display:block}
.comue{font-size:1.8rem;width:2.4rem;text-align:center}.comue.big{font-size:2.6rem}
.comut{display:flex;align-items:center;gap:.7rem;margin-top:.5rem}
.perf{display:flex;gap:1rem;align-items:flex-start}
.pstats{display:flex;gap:1rem;flex-wrap:wrap;margin:.6rem 0}
.pstats span,.pstats button{display:flex;flex-direction:column;font-size:.75rem;color:var(--muted);background:none;border:0;padding:0;font-family:inherit;cursor:default;text-align:left}
.pstats button{cursor:pointer}.pstats b{font-size:1.05rem;color:var(--ink)}
.socin{padding:2rem 1.2rem}
.tgl{display:flex;align-items:center;gap:.5rem;font-weight:600}
</style>
</body>
</html>
