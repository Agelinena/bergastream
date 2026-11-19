# Bergastream

Servidor de música próprio, com app para **Android, Windows, Linux e navegador**. Você busca
qualquer música (Spotify, YouTube Music, Deezer), toca na hora e monta suas playlists; o servidor
baixa a música uma vez e guarda na sua máquina.

## O que ele faz

- **Busca e toca** pelo Spotify, YouTube Music e Deezer; cola links de músicas, álbuns e
  playlists e importa tudo.
- **Rádio:** tocar uma música da busca monta uma rádio de parecidas, cruzando YouTube Music,
  Last.fm, Deezer e ListenBrainz.
- **Playlists** compartilhadas entre pessoas, com capa, e **sincronização** entre aparelhos.
- **Offline:** baixe playlists no celular ou no computador e ouça sem internet.
- **Qualidade:** MP3 320 ou FLAC pelo Deezer (conta Premium) e, opcional, FLAC pela Usenet
  (Lidarr); o app escolhe o nível no Wi-Fi e nos dados móveis.
- **Volume normalizado** no servidor (−10 ou −14 LUFS), igual em todos os aparelhos.
- **Letras** sincronizadas (LRCLIB), com edição e marcação linha a linha.
- **Ouvir junto:** sessões em que todos ouvem a mesma música, ou só um aparelho toca e os outros
  controlam.
- **Tocar em…** outros aparelhos da sua conta, **Chromecast** e TVs **DLNA**.
- **Android Auto:** playlists, fila e busca no carro.
- Login por senha ou pelo **Authentik** (OIDC).

## Como subir

Precisa de um servidor com Docker:

```bash
git clone https://github.com/Agelinena/bergastream.git
cd bergastream
cp .env.example .env      # preencha senhas, JWT_SECRET e o ARL do Deezer
docker compose up -d --build
```

O app web abre em `http://<servidor>:8080`. Para os apps e o acesso de fora, ponha um proxy com
HTTPS na frente. Passo a passo completo: [docs/DEPLOY.md](docs/DEPLOY.md).

Os apps ficam nas [releases](https://github.com/Agelinena/bergastream/releases) e se atualizam
sozinhos.

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/DEPLOY.md](docs/DEPLOY.md) | subir, HTTPS, Lidarr, backup e problemas comuns |
| [docs/AUTHENTIK.md](docs/AUTHENTIK.md) | login pelo Authentik (OIDC) |
| [docs/USUARIOS.md](docs/USUARIOS.md) | contas com senha pela linha de comando |
| [docs/RELEASE.md](docs/RELEASE.md) | gerar e publicar os apps |
| [docs/API_MAP.md](docs/API_MAP.md) | rotas da API |
| [Documentação.md](Documentação.md) | especificação completa do app |
| [ja_implementado.md](ja_implementado.md) | o que já foi feito, versão por versão |

## Estrutura

```
backend/    API (FastAPI) e worker de downloads, migrações do banco (dbmate)
frontend/   app Flutter (Android, Windows, Linux e web) e o nginx do app web
docs/       guias
```

## Aviso

O Bergastream baixa músicas de serviços de terceiros para uso pessoal. Respeite as leis de direitos
autorais do seu país e os termos de uso dos serviços.

## Licença

[AGPL-3.0](LICENSE). Quem rodar uma versão modificada como serviço para outras pessoas precisa
publicar o código dela.
