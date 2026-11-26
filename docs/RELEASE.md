# Bergastream — versões dos apps (Android, Windows, Linux)

Os apps são gerados pelo GitHub Actions (`.github/workflows/release.yml`) quando uma tag
`vX.Y.Z` é enviada. A release fica em https://github.com/Agelinena/bergastream/releases com:

| Arquivo | Plataforma |
|---|---|
| `bergastream-android.apk` | Android 7+ (APK universal, assinado) |
| `bergastream-windows-x64-setup.exe` | Windows 10/11 64 bits: instalador (sem administrador) |
| `bergastream-windows-x64.zip` | Windows: a mesma pasta, para usar sem instalar |
| `bergastream-install-linux.sh` | Linux x64: instala o `.tar.gz` para o usuário, com atalho no menu |
| `bergastream-linux-x64.tar.gz` | Linux x64: a pasta do app |

Os apps instalados consultam essas releases ao abrir (no máximo uma vez a cada 20 h) e em
**Ajustes → Verificar atualizações**. Havendo versão nova, perguntam:

- **Baixar e instalar** (Android): baixa o APK e abre o instalador do sistema.
- **Atualizar agora** (Windows; Linux instalado pelo script ou numa pasta com permissão de
  escrita): baixa, instala e reabre o app sozinho.
  - Windows: roda o instalador em silêncio (`/VERYSILENT`); ele fecha o app, troca os arquivos
    e o abre de novo (`frontend/windows/installer/bergastream.iss`).
  - Linux: extrai o `.tar.gz` ao lado da pasta do app, troca as duas de nome e reabre; a pasta
    antiga (`<pasta>.old`) é apagada na abertura seguinte (`desktop_updater.dart`).
- **Baixar** (Linux sem permissão para trocar a pasta do app): salva o pacote em Downloads e
  abre a pasta.
- **Ver no GitHub**: abre a página da versão.
- **Agora não**: não pergunta de novo por essa versão (só por uma mais nova).

O app procura exatamente esses nomes de arquivo, em tags `vX.Y.Z` deste repositório e em tags
`bergastream-vX.Y.Z` do repositório de onde o app saiu (as versões até a 0.8.x foram publicadas
lá); fica com a mais nova (`AppRelease.repositories` em `frontend/lib/features/update/`).

## Publicar uma versão

```bash
git tag v0.9.0
git push origin v0.9.0
```

O workflow roda os testes, compila os três apps e publica a release (~20 min). O número da
versão vem da tag (`0.9.0`; código do Android `900`, ou seja, `X*10000 + Y*100 + Z`). Não é
preciso mexer no `pubspec.yaml`, mas mantenha a versão dele igual à última tag para os builds
locais.

## Assinatura do Android (uma vez)

O Android só aceita uma atualização assinada **com a mesma chave** do app instalado. A chave fica
**fora do repositório** (guarde com backup; perder a chave obriga a reinstalar o app em todos os
aparelhos). Para criar uma:

```bash
keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload.jks > upload.jks.base64
```

Cadastre no GitHub, em **Settings → Secrets and variables → Actions**:

| Secret | Valor |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | conteúdo de `upload.jks.base64` |
| `ANDROID_KEYSTORE_PASSWORD` | senha da chave (`storePassword`) |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | senha do alias (`keyPassword`) |

Sem esses secrets o job do Android falha de propósito (com aviso) e a release sai só com Windows
e Linux. Depois de cadastrar: **Actions → a execução → Re-run failed jobs** para acrescentar o APK.

## Build local

Precisa do Flutter (ou do Docker, com a imagem `ghcr.io/cirruslabs/flutter`, que tem o SDK do
Android).

```bash
cd frontend
cat > android/key.properties <<EOF
storeFile=upload.jks
storePassword=...
keyAlias=upload
keyPassword=...
EOF
cp /caminho/da/chave/upload.jks android/app/upload.jks
flutter build apk --release --build-name=0.9.0 --build-number=900
flutter build linux --release --build-name=0.9.0 --build-number=900   # precisa das libs abaixo
```

Sem `android/key.properties` o APK de release sai com a chave de debug (serve para testar,
**não** para distribuir). O Windows só compila no próprio Windows (ou no CI).

## Requisitos para quem instala

- **Android:** permitir "Instalar apps desconhecidos" para o navegador/gerenciador de arquivos
  (e para o Bergastream, na primeira atualização pelo app). Para o Android Auto mostrar o app
  (instalado fora da Play Store): no app Android Auto, toque 10 vezes em "Versão" e ligue
  **Fontes desconhecidas** nas configurações de desenvolvedor.
- **Windows:** o instalador não é assinado; na primeira instalação o SmartScreen pode avisar
  ("Mais informações → Executar assim mesmo"). Instala em `%LOCALAPPDATA%\Programs\Bergastream`.
- **Linux:** `libmpv` (áudio) e um chaveiro do sistema (`libsecret`, para guardar o login):
  `sudo apt install libmpv2 libsecret-1-0 gnome-keyring` (Debian/Ubuntu). Depois:
  `curl -fsSL https://github.com/Agelinena/bergastream/releases/latest/download/bergastream-install-linux.sh | sh`
  (instala em `~/.local/share/bergastream`; `--desinstalar` remove).

## Onde o app guarda os dados (desktop)

Banco (`bergastream.sqlite`) e músicas baixadas (`bergastream/audio`, `bergastream/capas`) ficam
na pasta de dados do app, nunca em Documentos:

- Linux: `~/.local/share/com.bergastream.app/`
- Windows: `%APPDATA%\com.bergastream\Bergastream\`

Até a 0.8.3 ficavam na pasta Documentos; na primeira abertura da 0.8.4 o app move tudo e
corrige os caminhos guardados (`frontend/lib/core/storage/app_dirs.dart`).
