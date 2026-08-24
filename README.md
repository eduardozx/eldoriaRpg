# Eldoria

RPG top-down 2D multiplayer (Godot 4.7) preparado para **HTML5** e deploy estático no **Vercel**.

## Requisitos de runtime (web)

| Item | Escolha no projeto |
|------|-------------------|
| Renderer | **GL Compatibility** (`project.godot`) |
| Rede | `WebSocketMultiplayerPeer` (ENet **não** funciona no browser) |
| Host | O navegador **não abre porta** — o HTML5 é sempre **cliente** |
| Threads / SharedArrayBuffer | Headers COOP + COEP (ver `vercel.json`) |

O Vercel serve só o **cliente**. O servidor do jogo continua sendo uma instância **desktop** (ou VPS) do Eldoria com host WebSocket na porta `9080`.

---

## 1. Exportar para HTML5 no Godot

1. Abra o projeto no **Godot 4.7+**.
2. Instale o template Web, se ainda não tiver:
   - **Editor → Manage Export Templates… → Download and Install**
3. Vá em **Project → Export…**
4. Selecione o preset **Web** (já existe em `export_presets.cfg`).
5. Confirme as opções:
   - **Export Path:** `public/Eldoria.html`
   - **Thread Support:** desligado (configuração atual; não exige SharedArrayBuffer)
   - Renderer do projeto: **Compatibility** (já configurado)
6. Clique em **Export Project** e exporte para `public/Eldoria.html`.

Ao terminar, a pasta `public/` deve conter pelo menos:

- `index.html`
- `index.js`
- `index.wasm`
- `index.pck`
- (e arquivos de worker/threads, se Thread Support estiver ativo)

O arquivo `vercel.json` fica na **raiz** e também em `public/vercel.json` (mesmos headers, útil se o Root Directory do Vercel for `public/`).

---

## 2. Testar o export localmente

Os headers COOP/COEP são obrigatórios para SharedArrayBuffer. Um `python -m http.server` simples **não** basta para threads.

Opções:

### A) Preview no Vercel CLI

```bash
# Na raiz do repositório (onde estão vercel.json e public/)
npx vercel dev
```

### B) Servidor local com headers

Use qualquer static server que envie:

- `Cross-Origin-Opener-Policy: same-origin`
- `Cross-Origin-Embedder-Policy: require-corp`

### C) Fluxo de jogo em duas partes

1. Rode o Eldoria no **desktop** e entre com um nome (essa instância vira o **host** em `ws://0.0.0.0:9080`).
2. Abra o build web e conecte:
   - Localhost: `http://127.0.0.1:3000/?ws=ws://127.0.0.1:9080`
   - Rede local: `http://SEU_IP_LAN:3000/?ws=ws://IP_DO_HOST:9080`

Parâmetros de URL suportados:

| Query | Exemplo | Efeito |
|-------|---------|--------|
| `ws` | `?ws=ws://192.168.0.10:9080` | URL WebSocket completa |
| `server` + `port` | `?server=192.168.0.10&port=9080` | Monta `ws://` ou `wss://` conforme a página |

Sem query, o cliente tenta `ws://127.0.0.1:9080`.

> **HTTPS no Vercel:** browsers bloqueiam `ws://` a partir de páginas `https://`. Para produção pública você precisa de um host com **WSS** (proxy TLS / túnel) ou testar em LAN com HTTP.

---

## 3. Deploy no Vercel

### Pela CLI

```bash
# 1) Exporte o jogo para public/ (passo 1)
# 2) Na raiz do projeto:
npx vercel login
npx vercel --prod
```

### Pelo dashboard

1. Envie o repositório para o GitHub/GitLab/Bitbucket **depois** de gerar `public/` (ou use CI para exportar).
2. Em [vercel.com](https://vercel.com): **Add New Project** → importe o repo.
3. Configuração sugerida:
   - **Framework Preset:** Other
   - **Build Command:** deixe vazio (o export já foi feito no Godot)
   - **Output Directory:** `public`  
     (alternativa: **Root Directory** = `public`, usando `public/vercel.json`)
4. Deploy.

Os headers abaixo são aplicados pelo `vercel.json`:

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: same-origin
```

Isso evita erros de **SharedArrayBuffer** / threads da Godot 4 no Chrome/Firefox.

---

## 4. Servidor multiplayer no Render

O cliente Web é publicado no Vercel; a sala multiplayer é um serviço WebSocket
separado no Render. O repositório inclui `render.yaml` e `Dockerfile` para
executar o Godot em modo headless.

1. No Render, escolha **New → Blueprint** e importe este repositório.
2. Aguarde o serviço `eldoria-server` ficar disponível e copie sua URL pública.
3. Atualize `public/runtime-config.js` com a URL segura, por exemplo:

```js
window.ELDORIA_SERVER_URL = "wss://eldoria-server.onrender.com";
```

4. Faça novo deploy no Vercel. O cliente usará essa URL automaticamente fora
   de `localhost`; a query `?ws=wss://...` continua tendo prioridade.

O Render fornece TLS, portanto o navegador pode abrir a conexão `wss://` a
partir da página HTTPS do Vercel.

---

## 5. Checklist pós-deploy

- [ ] Abrir a URL do Vercel e confirmar que o canvas carrega sem erro de COOP/COEP no console.
- [ ] Host desktop (ou servidor) rodando com a porta `9080` acessível.
- [ ] Abrir o cliente com `?ws=...` apontando para esse host (e **WSS** se o site for HTTPS).
- [ ] Login com nome → mundo → chat / combate / missão.

---

## Contas persistentes (Supabase)

O progresso (nível, EXP, ouro, itens, arma equipada) fica salvo numa tabela do **Supabase** (grátis, 24h). O servidor do jogo é o único que fala com o banco — o cliente só envia nome/senha pelo WebSocket.

### Setup (uma vez)

1. Crie um projeto grátis em [supabase.com](https://supabase.com).
2. Abra **SQL Editor** → cole o conteúdo de `supabase.sql` → **Run**.
3. Pegue as chaves em **Settings → API**:
   - `Project URL` → `SUPABASE_URL`
   - `service_role key` → `SUPABASE_KEY` (**não** use a anon key)
4. Configure as variáveis de ambiente no servidor do jogo:
   - **Render:** Dashboard → Environment → adicione `SUPABASE_URL` e `SUPABASE_KEY`.
   - **Desktop local:** exporte as duas variáveis antes de abrir o jogo.

Sem as variáveis o jogo roda em **modo offline**: dá pra jogar normalmente, mas nada é persistido.

### Fluxo

- Tela de login tem abas **Entrar** e **Registrar** (só nome + senha).
- Senha vira hash SHA-256 com salt aleatório no servidor (nunca trafega ao banco em texto puro).
- Autosave a cada 20s quando há mudanças + ao desconectar.
- Registrar com nome já existente retorna "Este nome já está em uso."

---

## Estrutura relevante

```
eldoria/
├── public/              # Saída do export HTML5
│   └── vercel.json      # Mesmos headers (Root Directory = public)
├── vercel.json          # Headers COOP / COEP / CORP
├── render.yaml           # Blueprint do servidor multiplayer no Render
├── Dockerfile            # Runtime headless do Godot
├── export_presets.cfg
├── project.godot        # GL Compatibility + main scene
├── scenes/
├── scripts/             # NetworkManager (WebSocket), quests, combate…
└── ui/
```

## Controles rápidos

| Ação | Tecla |
|------|-------|
| Mover | WASD / setas |
| Atacar | Espaço / clique |
| Falar com NPC | E |
| Chat | Enter |
| Inventário | I |
