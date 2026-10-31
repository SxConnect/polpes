# Polpes — conteúdo de negócio

Repositório de **dados**, não de código.

O código-fonte do sistema (painel + cardápio) está em
[`SxConnect/cardapio-digital-fidelidade`](https://github.com/SxConnect/cardapio-digital-fidelidade).
Este repositório guarda **o que é da Polpes**: o cardápio, o clube de fidelidade,
as zonas de entrega, as formas de pagamento e as fotos do catálogo.

---

## Por que separar

O sistema é genérico; a Polpes é uma instância dele. Separar código de conteúdo
permite versionar o cardápio da cliente sem tocar no código, e reutilizar o mesmo
contêiner para outras instâncias no futuro.

## O que tem aqui

| Caminho | O que é |
|---|---|
| `seed/polpes-seed.sql` | Schema + dados de negócio (idempotente) |
| `statics/catalog/` | 40 fotos do catálogo (39 produtos), 37 MB |

## O que NÃO tem aqui (e por quê)

O seed é **conteúdo de negócio apenas**. Ficaram de fora, de propósito:

| Excluído | Motivo |
|---|---|
| `contacts`, `messages`, `executions`, `execution_steps`, `usage` | Dados de cliente (nome, telefone, histórico de conversa) |
| `orders`, `order_items`, `coupon_redemptions` | Histórico de pedidos e resgates do cliente |
| `club_members` | Membros do clube, ligados a contatos reais |
| `ai_api_key`, `openrouter_api_key` | Chaves de API |
| `web_password_hash`, `web_password_salt` | Credencial do painel |
| `chatstorage.db`, `whatsapp.db` | Sessão do WhatsApp — versionar isso desemparella o número |

## O que o seed contém

| Tabela | Linhas |
|---|---|
| `products` | 99 (nome, descrição, preço, preço do clube, foto) |
| `product_categories` | 8 |
| `category_addons` | 4 |
| `club_benefits` | 5 |
| `club_settings` | 3 |
| `delivery_zones` | 5 (km e taxa) |
| `payment_methods` | 6 |
| `cep_cache` | 77 |
| `config` | 52 (nome, horário, logo, redes, modelos de IA, prompt) |
| **Total** | **259 linhas** |

## Como aplicar

### SQLite (padrão — sem `DATABASE_URL`)

```bash
sqlite3 storages/whatsbot.db < seed/polpes-seed.sql
```

### PostgreSQL

Com `DATABASE_URL` definida, o app migra SQLite → Postgres sozinho no startup.
Ou manualmente:

```bash
DATABASE_URL=postgresql://user:pass@host:5432/db \
  python scripts/migrate_sqlite_to_postgres.py
```

### Fotos do catálogo

As fotos são servidas de `/app/statics/catalog/`. Copie para o volume do contêiner:

```bash
docker cp statics/catalog/. polpes:/app/statics/catalog/
docker restart polpes
```

---

## Regenerar o seed

Depois de alterar produtos, clube ou zonas pelo painel:

```bash
sqlite3 storages/whatsbot.db .dump \
  | grep -E "INSERT OR REPLACE INTO (products|product_categories|category_addons|club_benefits|club_settings|delivery_zones|payment_methods|cep_cache|config) "
```

Ou regenere o arquivo completo a partir da instância local em
`painel-whats-main/storages/whatsbot.db`, mantendo as 4 chaves de
segurança fora do arquivo (`ai_api_key`, `openrouter_api_key`,
`web_password_hash`, `web_password_salt`).
