"""Prepara os arquivos de distribuição a partir de Paginas.bat (o programa inteiro).

Gera:
  build/Paginas.bat                          versão para Windows, com a configuração abaixo
  android/app/src/main/assets/index.html     a mesma tela, para o app Android
  android/app/src/main/assets/config.json    a mesma configuração, para o app Android
  android/app/src/main/assets/icone.png

Variáveis de ambiente (todas opcionais; na publicação vêm dos segredos do GitHub):
  VERSAO          ex.: 1.2 ou v1.2
  ATUALIZA_REPO   "usuario/repositorio" do GitHub (aviso de versão nova e atualização em um clique)
  IA_PROXY_URL    endereço do intermediário de IA (o mesmo do Investe.AI)
  IA_PROXY_TOKEN  a senha APP_TOKEN do intermediário
  GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET   cliente OAuth do Google, tipo "App para computador" (pode ser o mesmo do Investe.AI)
"""
import json, os, re, shutil, sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(RAIZ, "Paginas.bat"), encoding="utf-8").read().replace("\r\n", "\n")

env = lambda k: (os.environ.get(k) or "").strip()
cfg = {
    "versao": env("VERSAO").lstrip("vV"),
    "repo": env("ATUALIZA_REPO"),
    "iaProxyUrl": env("IA_PROXY_URL").rstrip("/"),
    "iaProxyToken": env("IA_PROXY_TOKEN"),
    "googleClientId": env("GOOGLE_CLIENT_ID"),
    "googleClientSecret": env("GOOGLE_CLIENT_SECRET"),
}
nomes = {"versao": "APP_VERSAO", "repo": "ATUALIZA_REPO", "iaProxyUrl": "IA_PROXY_URL", "iaProxyToken": "IA_PROXY_TOKEN",
         "googleClientId": "G_CLIENT_ID", "googleClientSecret": "G_CLIENT_SECRET"}

for chave, nome in nomes.items():
    m = re.search(rf"^\${nome} = '((?:[^']|'')*)'$", src, re.M)
    if not m: sys.exit(f"não achei ${nome} no Paginas.bat")
    if cfg[chave]:
        val = cfg[chave].replace("'", "''")
        src = src[:m.start()] + f"${nome} = '{val}'" + src[m.end():]
    else:
        cfg[chave] = m.group(1).replace("''", "'")  # mantém o que está no arquivo

if cfg["iaProxyUrl"] and not re.match(r"https?://", cfg["iaProxyUrl"]):
    cfg["iaProxyUrl"] = "https://" + cfg["iaProxyUrl"]
    m = re.search(r"^\$IA_PROXY_URL = '.*'$", src, re.M)
    src = src[:m.start()] + "$IA_PROXY_URL = '" + cfg["iaProxyUrl"].replace("'", "''") + "'" + src[m.end():]
if not cfg["iaProxyUrl"]: print("AVISO: sem IA_PROXY_URL: a IA só funciona se a pessoa colocar a própria chave em Ajustes.")
if not (cfg["googleClientId"] and cfg["googleClientSecret"]): print("AVISO: sem GOOGLE_CLIENT_ID/SECRET: o login com Google fica desativado.")

marca = "\n::HTML_START\n"
i = src.find(marca)
if i < 0 or "#PS_START\n" not in src: sys.exit("Paginas.bat incompleto (marcas #PS_START / ::HTML_START)")
html = src[i + len(marca):]

os.makedirs(os.path.join(RAIZ, "build"), exist_ok=True)
with open(os.path.join(RAIZ, "build", "Paginas.bat"), "wb") as f:
    f.write(src.replace("\n", "\r\n").encode("utf-8"))

assets = os.path.join(RAIZ, "android", "app", "src", "main", "assets")
os.makedirs(assets, exist_ok=True)
with open(os.path.join(assets, "index.html"), "w", encoding="utf-8", newline="\n") as f:
    f.write(html)
with open(os.path.join(assets, "config.json"), "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False)
shutil.copyfile(os.path.join(RAIZ, "icone.png"), os.path.join(assets, "icone.png"))

print("ok: build/Paginas.bat e assets do Android, versão", cfg["versao"],
      "| IA:", "intermediário" if cfg["iaProxyUrl"] else "sem", "| Google:", "sim" if cfg["googleClientId"] else "não")
