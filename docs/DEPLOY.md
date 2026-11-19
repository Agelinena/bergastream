# Bergastream — subir no servidor

O que precisa: um servidor Linux com **Docker** e **Docker Compose v2**, e (para usar de fora de
casa e nos apps) um **domínio com HTTPS**, por exemplo `https://bergastream.example.com`.

```
proxy com HTTPS ──► bergastream-web :8080 (nginx: app web + /api/ → API)
(Traefik, Caddy…)        │  bergastream-internal (sem internet)
                         ├── bergastream-api ──┐
                         ├── bergastream-worker├─ bergastream-egress (internet:
                         ├── bergastream-deemix┘   Spotify, YouTube, Deezer)
                         ├── bergastream-db (Postgres 16)
                         └── bergastream-redis
```

Só o `web` recebe tráfego de fora; a API, o banco e o Redis ficam na rede interna.

## 1. Código e pastas

```bash
git clone https://github.com/Agelinena/bergastream.git
cd bergastream
cp .env.example .env
```

Por padrão os dados ficam em `./data` (banco, Redis, configs) e `./data/media` (músicas). Para
outro lugar (um disco maior para as músicas, por exemplo), mude `APPDATA_PATH`, `CACHE_PATH` e
`MEDIA_PATH` no `.env` e crie as pastas com o dono certo **antes** de subir (senão o Docker cria
como root e o Deemix/Lidarr não conseguem gravar):

```bash
# Use os mesmos valores do .env
APPDATA_PATH=./data CACHE_PATH=./data/cache MEDIA_PATH=./data/media

mkdir -p $APPDATA_PATH/bergastream/{postgres,redis,deemix,lidarr,youtube} \
         $CACHE_PATH/bergastream/pydeps \
         $MEDIA_PATH/musica/bergastream/deemix_dl $MEDIA_PATH/musica/lidarr
sudo chown -R 1000:1000 $APPDATA_PATH/bergastream/{deemix,lidarr} $CACHE_PATH/bergastream \
                        $MEDIA_PATH/musica/bergastream $MEDIA_PATH/musica/lidarr
```

## 2. `.env`

| Variável | O que pôr |
|---|---|
| `WEB_PORT` | porta do app web e da API no servidor (padrão 8080) |
| `TZ`, `PUID`, `PGID` | fuso horário e dono dos arquivos baixados |
| `APPDATA_PATH`, `CACHE_PATH`, `MEDIA_PATH` | onde ficam os dados (passo 1) |
| `POSTGRES_PASSWORD` | senha nova (gere abaixo) |
| `DATABASE_URL` | a mesma senha no lugar de `troque_esta_senha` |
| `JWT_SECRET` | segredo novo (gere abaixo) |
| `DEEMIX_ARL` | cookie `arl` do deezer.com logado — conta **Premium** para MP3 320/FLAC (grátis = 128) |
| `LASTFM_API_KEY` | chave grátis do Last.fm para a rádio (opcional, recomendado) |
| `OIDC_*`, `PASSWORD_LOGIN` | login pelo Authentik (opcional, [AUTHENTIK.md](AUTHENTIK.md)) |
| `SMTP_*`, `APP_URL` | e-mails de aviso, convite e "esqueci minha senha" (opcional) |
| `LIDARR_API_KEY` | FLAC das playlists pela Usenet (opcional, passo 7) |

O Spotify não precisa de conta nem de chave.

```bash
openssl rand -base64 36 | tr -d '/+=' | cut -c1-40   # rode duas vezes: senha do banco e JWT_SECRET
```

Use senhas só com letras e números (vão dentro da `DATABASE_URL`).

## 3. Subir

```bash
docker compose up -d --build      # 1ª vez: o build do app web leva ~5–10 min
docker compose ps                 # db/redis/api healthy, migrate "exited (0)"
docker compose logs migrate       # migrações aplicadas
```

O app web abre em `http://<servidor>:8080`.

## 4. HTTPS e domínio

Os apps (Android, Windows, Linux) e o login pelo Authentik precisam de um endereço com HTTPS.
Ponha um proxy reverso na frente da porta do `web`; tudo (app web e `/api/`) passa pela mesma
rota, e o WebSocket da sessão compartilhada (`/api/sessions/…/ws`) precisa passar também.

**Caddy** (certificado automático):

```
bergastream.example.com {
    reverse_proxy 127.0.0.1:8080
}
```

**Traefik** com Docker: tire a porta do `web` e ponha o `web` na rede do Traefik com os rótulos de
rota. Um arquivo extra do compose evita mexer no `docker-compose.yml` (que muda a cada versão):

```yaml
# docker-compose.proxy.yml
services:
  web:
    ports: !reset []
    networks: [traefik]
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik"
      - "traefik.http.routers.bergastream.rule=Host(`bergastream.example.com`)"
      - "traefik.http.routers.bergastream.entrypoints=websecure"
      - "traefik.http.routers.bergastream.tls=true"
      - "traefik.http.services.bergastream.loadbalancer.server.port=80"
networks:
  traefik:
    external: true
```

E no `.env`: `COMPOSE_FILE=docker-compose.yml:docker-compose.proxy.yml` (o `!reset` pede o Docker
Compose 2.24 ou mais novo).

Não ponha o Bergastream atrás de um login do proxy (forward-auth): o app faz o próprio login e
a API exige o token dela em toda chamada.

## 5. Usuários

Sem Authentik, as contas com senha são criadas pela linha de comando ([USUARIOS.md](USUARIOS.md)):

```bash
docker compose exec api python -m app.auth.cli create-user <usuario> --admin
docker compose exec api python -m app.auth.cli list-users
```

Com o Authentik configurado, as contas vêm de lá: quem está no grupo `bergastream_users` entra, e
a conta do Bergastream é criada (ou ligada à que já existia) no primeiro login. Veja
[AUTHENTIK.md](AUTHENTIK.md).

## 6. Testar

1. **Configuração do login:**

   ```bash
   curl -s https://bergastream.example.com/api/auth/config
   # {"registration_enabled":false,"oidc_enabled":false,"password_login_enabled":true}
   ```

2. **Navegador:** https://bergastream.example.com → entrar → buscar e tocar.
3. **App:** instale pela [página de releases](https://github.com/Agelinena/bergastream/releases),
   informe o servidor `bergastream.example.com` e entre. Teste também fora do Wi-Fi.

## 7. Atualizar o servidor depois

```bash
git pull
docker compose up -d --build      # as migrações novas rodam sozinhas (serviço migrate)
```

## 8. Qualidade: Deezer Premium e FLAC pela Usenet (Lidarr)

**Deezer Premium.** Depois de assinar, pegue o cookie `arl` de novo no deezer.com logado
(DevTools → Application → Cookies), troque `DEEMIX_ARL` no `.env` e:

```bash
docker compose up -d deemix api worker
```

Sob demanda as músicas passam a vir em MP3 320. As faixas de playlist tentam FLAC: se o plano
incluir, já resolve pelo próprio Deemix. Se o log do worker disser "a conta do ARL não tem FLAC",
fica o 320 e o Lidarr (opcional) cuida do FLAC.

**Lidarr** (opcional, perfil `lidarr` do compose). Baixa pela Usenet com um **SABnzbd** e os
indexadores de um **Prowlarr**, que você já precisa ter:

1. O Lidarr precisa alcançar o SABnzbd e o Prowlarr (ponha os três numa rede Docker em comum, com
   um arquivo extra do compose como o do passo 4) e ver os downloads do SABnzbd no mesmo caminho:
   o compose monta `${MEDIA_PATH}/downloads` como `/downloads`, que deve ser a mesma pasta do
   SABnzbd.
2. Suba: `docker compose --profile lidarr up -d` (ou `COMPOSE_PROFILES=lidarr` no `.env`).
3. Na interface do Lidarr (porta 8686; publique só na rede local), na primeira vez:
   - **Settings → General → Security:** crie usuário e senha (método "Forms").
   - **Settings → Media Management → Root Folders:** adicionar `/music`, perfil de qualidade
     **Lossless**, metadados **Standard**.
   - **Settings → Profiles → Metadata Profiles → Standard:** marcar **Album**, **EP** e **Single**.
   - **Settings → Download Clients → + → SABnzbd:** host e porta do SABnzbd, API key do SABnzbd,
     categoria `music` (crie a categoria no SABnzbd também).
   - **Prowlarr → Settings → Apps → + → Lidarr:** Lidarr Server `http://bergastream-lidarr:8686`,
     API key do Lidarr → Test → Save. Depois **Sync App Indexers**. Os indexadores precisam ter a
     categoria de música (3000).
   - **Settings → General → API Key:** copie.
4. No `.env`: `LIDARR_API_KEY=<a chave>` e:

   ```bash
   docker compose up -d worker
   docker compose logs worker | grep upgrade    # "[upgrade] iniciado (Lidarr ligado)"
   ```

Como funciona: faixa que entra numa playlist ganha uma fila de melhoria. O worker tenta o Deemix
no melhor formato e, sem FLAC, pede ao Lidarr o **álbum** da faixa (o Lidarr só baixa por álbum),
monitorando só esse álbum do artista. O álbum é o de estúdio da gravação (ISRC → MusicBrainz),
não a coletânea do Spotify. Busca na hora, todo dia nos primeiros 3 dias (`UPGRADE_DAILY_DAYS`)
e depois toda semana; entre uma e outra, o Lidarr vigia a Usenet sozinho (RSS). Para não estourar
o limite do indexador, no máximo 30 álbuns ficam na fase diária (`LIDARR_MAX_ACTIVE`) e são no
máximo 100 buscas por dia (`LIDARR_DAILY_SEARCHES`), das quais 30 ficam para pedidos novos
(`LIDARR_REQUEST_RESERVE`). Download travado há mais de 1 h, ou torrent parado há mais de 20 min
(`LIDARR_STALLED_MINUTES`), é removido, vai para a blocklist e o álbum é buscado de novo. Quando o
álbum chega, o FLAC da faixa é copiado e substitui o arquivo; quando nenhuma outra faixa de
playlist espera aquele álbum, os arquivos são apagados do Lidarr (`LIDARR_KEEP_ALBUMS=true`
mantém). Situação: `GET /api/server/status` → `quality`.

**O que cada aparelho recebe:** o servidor guarda um arquivo por música (o melhor que conseguiu)
e entrega no nível escolhido no app (Ajustes → Qualidade): Original (FLAC quando houver), Alta
(MP3 320), Normal (AAC 160) ou Econômica (AAC 96), já no volume normalizado. Versões convertidas
ficam em `music/variants` e são apagadas depois de 7 dias sem uso.

## 9. Backup

Banco e configs em `${APPDATA_PATH}/bergastream`; músicas em `${MEDIA_PATH}/musica`. As músicas
podem ser baixadas de novo, mas as playlists, o histórico e os usuários não:

```bash
docker compose exec -T db pg_dump -U bergastream bergastream | gzip > bergastream-$(date +%F).sql.gz
```

Restaurar num banco vazio:

```bash
gunzip -c bergastream-AAAA-MM-DD.sql.gz | docker compose exec -T db psql -U bergastream bergastream
```

## Problemas comuns

| Sintoma | Causa provável |
|---|---|
| App diz "Servidor não encontrado" | Confira o `curl` do passo 6.1. Se ele devolve HTML (uma página de login), o proxy está pedindo login antes do Bergastream: tire o forward-auth da rota. |
| Login pelo Authentik não termina | `docker compose logs api \| grep oidc`. Causas comuns em [AUTHENTIK.md](AUTHENTIK.md#problemas-comuns). |
| 502 no navegador | API parada ou reiniciando: `docker compose ps` e `docker compose logs api`. |
| Músicas não baixam do Deezer | ARL vencido: pegue o cookie de novo, troque no `.env`, `docker compose up -d deemix api worker`. O YouTube segue como alternativa. |
| Música falha no Deemix e no YouTube; log: "bloqueado pelo Modo Restrito" | O DNS da rede (AdGuard, Pi-hole com "pesquisa segura") força o Modo Restrito do YouTube. Libere a pesquisa segura só para o IP do servidor. |
| Log do worker: "Sign in to confirm you're not a bot" | O YouTube está bloqueando o IP. Confira se o `bergastream-pot` está de pé; se persistir, use cookies de uma conta **secundária** (`YT_COOKIES_FILE`, ver `.env.example`). |
| Aba Spotify da busca dá "O Spotify não respondeu" | O Spotify mudou o web player. O worker testa todo dia e instala a versão nova da biblioteca sozinho; para ver agora: `docker compose exec worker python -m app.search.spotify_health`. |
| Log do worker: "Lidarr fora do ar: ReadTimeout" | O Lidarr demorou mais de 30 s (normal enquanto carrega discografias). A faixa é conferida de novo em 1 h. |
| Lidarr não importa o que o SABnzbd baixou | O Lidarr e o SABnzbd precisam montar a mesma pasta de downloads como `/downloads`. |
| App web antigo depois de atualizar | Uma aba aberta há tempo mostra "Nova versão do Bergastream → Recarregar". Se nem assim: Ctrl+Shift+R. |
| "Muitas tentativas" no login | 5 senhas erradas em 15 min para aquele usuário e IP: espere ou troque a senha ([USUARIOS.md](USUARIOS.md)). |
