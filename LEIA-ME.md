# Páginas: como publicar para qualquer pessoa baixar

Este projeto gera automaticamente, na nuvem do GitHub e de graça:

- **Paginas.bat**: Windows. Um arquivo só: abre com dois cliques, sem instalar nada, e cria o atalho com o ícone.
- **Paginas.apk**: o app para Android (8 ou mais novo).
- **O site de download** (pasta `docs`), com os dois botões, a Política de Privacidade e os Termos de Uso.

A **IA** usa o **mesmo intermediário (Cloudflare) do Investe.AI**: as chaves do Groq e do Gemini continuam só lá, nunca dentro dos arquivos baixados.
O **login com Google** usa o mesmo tipo de cliente do Investe.AI ("App para computador") e guarda uma cópia dos dados numa pasta oculta do Google Drive da pessoa, para o computador e o celular ficarem sincronizados.

---

## 1. Segredos do repositório (uma vez só)

No repositório `paginas`, vá em **Settings > Secrets and variables > Actions > New repository secret** e crie, **com os mesmos valores que você usou no Investe.AI**:

| Segredo | O que colar |
|---|---|
| `IA_PROXY_URL` | o endereço do intermediário, ex.: `https://investe-ai-ia.SEU-NOME.workers.dev` |
| `IA_PROXY_TOKEN` | a senha `APP_TOKEN` do intermediário |
| `GOOGLE_CLIENT_ID` | o ID do cliente OAuth do Google (termina em `.apps.googleusercontent.com`) |
| `GOOGLE_CLIENT_SECRET` | o segredo desse cliente (`GOCSPX-...`) |

Os valores ficam no painel da Cloudflare (Workers > investe-ai-ia > Settings) e no Google Cloud (APIs e serviços > Credenciais). Se não lembrar a senha `APP_TOKEN`, crie outra com `npx wrangler secret put APP_TOKEN` na pasta `proxy-ia` do Investe.AI e atualize o segredo nos **dois** repositórios.

**Sobre o Google:**
- Pode usar o mesmo cliente do Investe.AI. Clientes do tipo "App para computador" aceitam qualquer porta do `127.0.0.1`, então não há nada para cadastrar.
- A tela de permissão do Google vai mostrar o nome do projeto do Google Cloud (o do Investe.AI). Se quiser que apareça "Páginas", crie um projeto novo, ative a **Google Drive API**, configure a tela de consentimento com os escopos `email`, `profile`, `openid` e `.../auth/drive.appdata`, crie um cliente "App para computador" e use esse ID e segredo.
- Enquanto o app do Google estiver em modo **Teste**, só os e-mails cadastrados em "Usuários de teste" conseguem entrar. Para liberar para todo mundo, use **Publicar app**. Os links de privacidade e termos que o Google pede são `https://limabat.github.io/Paginas/privacidade.html` e `https://limabat.github.io/Paginas/termos.html`.

**Assinatura do APK (recomendado):** sem ela, cada versão sai com uma assinatura de teste diferente, e o Android só instala a nova depois de desinstalar a antiga. Crie também:

| Segredo | O que colar |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | o arquivo `.keystore` convertido para texto |
| `ANDROID_KEYSTORE_SENHA` | a senha dele |
| `ANDROID_KEY_ALIAS` | o apelido da chave dentro dele |

Pode reaproveitar a mesma chave do Investe.AI (nesse caso o apelido é `investe-ai`) ou criar uma com:
`keytool -genkeypair -v -keystore paginas.keystore -alias paginas -keyalg RSA -keysize 2048 -validity 10000`
e convertê-la no PowerShell com `[Convert]::ToBase64String([IO.File]::ReadAllBytes("paginas.keystore")) | Set-Clipboard`. **Guarde o arquivo**: sem ele não dá para publicar atualizações que instalem por cima.

## 2. Ligar o site

**Settings > Pages**: em "Source" escolha **Deploy from a branch**, branch **main**, pasta **/docs**, e salve. Em um ou dois minutos o site fica em:

```
https://limabat.github.io/Paginas/
```

## 3. Publicar uma versão

1. **Releases > Draft a new release**.
2. Em "Choose a tag", digite `v1.0` (depois `v1.1`, `v1.2`...) e confirme "Create new tag".
3. Escreva um título e uma descrição curta. A primeira linha da descrição aparece no aviso de versão nova dentro do app.
4. **Publish release**.
5. Em uns 15 minutos, a aba **Actions** termina e a release passa a ter `Paginas.bat` e `Paginas.apk`. Antes de anexar, o programa do Windows é aberto e testado, e o app Android é instalado e aberto num emulador.

Links diretos (sempre a versão mais nova), os mesmos dos botões do site:

```
https://github.com/LimaBat/Paginas/releases/latest/download/Paginas.bat
https://github.com/LimaBat/Paginas/releases/latest/download/Paginas.apk
```

## 4. Atualizações

- Quem já tem o app vê **"Nova versão disponível"** ao abrir. No Windows, **Ajustes > Versão > Atualizar agora** baixa, troca o programa e reabre. No Android, o botão baixa o APK novo para instalar por cima.
- **O número da tag precisa ser sempre maior que o anterior** (`v1.0` < `v1.1` < `v1.2`).

## O que tem em cada arquivo

| Arquivo | Para que serve |
|---|---|
| `Paginas.bat` | O programa inteiro: a parte em PowerShell (servidor local do Windows) e a tela (HTML) |
| `android/` | O app Android: abre a mesma tela num WebView, com um servidor local em Java que faz o mesmo que a parte em PowerShell |
| `ferramentas/preparar.py` | Coloca a versão, a IA e o Google no `Paginas.bat` e copia a tela para o Android antes de empacotar |
| `ferramentas/icone.py` | Desenha os ícones (o mesmo desenho do programa) |
| `ferramentas/testar_android.sh` | Teste do APK no emulador |
| `.github/workflows/publicar.yml` | Gera, testa e publica o `.bat` e o `.apk` a cada release |
| `docs/` | O site de download, a Política de Privacidade e os Termos |
