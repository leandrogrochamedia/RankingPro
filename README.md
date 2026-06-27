# Ranking Pro — Shark Mode Núcleo

Infraestrutura de reputação verificada via QR Code. Escopo Semana 1–2: **QR → avaliação → perfil público**.

## Stack

- HTML estático + JavaScript vanilla
- Supabase (REST + RPC)
- Deploy: Netlify

## Estrutura

```
ranking-pro-shark/
├── qr/           → /qr/?token=XXX (valida e redireciona)
├── avaliar/      → formulário de nota + comentário
├── p/            → perfil público /p/?slug=...
├── dev/          → gerador de QR (MVP interno)
├── js/           → api, qr, reviews, profile services
├── sql/          → schema do núcleo
└── config.js     → credenciais (não versionado)
```

## Setup local

### 1. Supabase (projeto NOVO)

1. Crie um projeto em [supabase.com](https://supabase.com) — **não** reutilize `pyywdhjstvhmarvzijji`
2. No SQL Editor, execute o conteúdo de `sql/001_nucleo.sql`
3. Confirme o seed: profissional `joao-barbeiro-teste`

### 2. Config

```bash
cp config.example.js config.js
```

Preencha com **Project URL** e **anon key** (Settings → API).

### 3. Servidor local

```bash
cd ranking-pro-shark
python3 -m http.server 8765
```

Abra `http://localhost:8765`

## Fluxo de teste manual

1. Abra `http://localhost:8765/dev/gerar-qr.html`
2. Selecione o profissional de teste → **Gerar QR Code**
3. Copie a URL ou escaneie o QR no celular (mesma rede ou produção)
4. Avalie com nota + comentário
5. Abra `/p/?slug=joao-barbeiro-teste` — avaliação visível
6. Reabra o mesmo QR → bloqueado ("já registrada")
7. No Supabase, force `expires_at` no passado → bloqueado ("expirou")

## Deploy (Netlify)

### Opção A — CLI

```bash
npm i -g netlify-cli   # ou npx netlify
netlify login
netlify init
netlify deploy --prod
```

### Opção B — Git + UI

1. Push para GitHub/GitLab
2. Netlify → New site from Git → pasta raiz
3. Build command: *(vazio)* | Publish directory: `.`

### Variáveis no Netlify

Em **Site settings → Environment variables**, defina:

| Variável | Valor |
|----------|-------|
| `SUPABASE_URL` | `https://SEU-PROJETO.supabase.co` |
| `SUPABASE_ANON_KEY` | anon key do projeto |

O build (`scripts/build-config.sh`) gera `config.js` automaticamente — **nunca** commite secrets no git.

## Variáveis

| Variável | Onde | Descrição |
|----------|------|-----------|
| `SUPABASE_URL` | config.js | URL do projeto Supabase |
| `SUPABASE_ANON_KEY` | config.js | Chave anon (pública, RLS protege) |

## RPCs (backend)

| Função | Uso |
|--------|-----|
| `validate_qr_token(token)` | Valida QR antes de avaliar |
| `submit_qr_review(token, rating, comment)` | Único ponto de INSERT em reviews |
| `create_qr_session(professional_id, hours)` | Gera sessão QR (dev/MVP) |

## Segurança

- INSERT direto em `reviews` bloqueado por RLS
- Token single-use (`used_at`)
- Token com expiração (`expires_at`)
- `is_verified = true` implícito via QR

## Fora do escopo (Semana 3+)

Cadastro, estabelecimentos, busca, dashboard, Asaas, auth completa.

## Profissional de teste

- **Slug:** `joao-barbeiro-teste`
- **Nome:** João Barbeiro (Teste)