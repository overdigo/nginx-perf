# nginx-perf

Build reproduzível e instalação de uma versão customizada do NGINX para Debian e Ubuntu, com foco em performance, hardening, TLS, HTTP/2, HTTP/3, QUIC, proxy reverso e operação nativa via systemd.

O projeto não é um pacote de aplicação. O script pode instalar pacotes com `apt-get`, criar usuário e grupo de runtime, baixar fontes de vários repositórios, compilar dependências e instalar arquivos em `/usr/local`, `/etc`, `/var/log`, `/var/cache` e `/run`. Execute o fluxo completo somente em um host preparado e com autorização administrativa.

## Recursos

- Compilação do NGINX com Clang/LLVM por padrão.
- Tuning genérico ou específico do host com `CPU_OPT`.
- OpenSSL bundled ou OpenSSL da distribuição.
- HTTP/2, HTTP/3, QUIC, TLS e stream TCP/UDP.
- PCRE2 com JIT, zlib-ng em modo compatível, Brotli e zstd.
- Módulos `headers-more` e `cache-purge`.
- `echo-nginx-module` desativado intencionalmente.
- Patches para remoção do cabeçalho `Server` e do rodapé padrão de erros.
- Flags de hardening, PIE, LTO, stack protector, Fortify Source, CET/IBT e inicialização automática de variáveis.
- Configuração base com limites de conexão, compressão, cabeçalhos de segurança e fallback para hosts não configurados.
- Instalação opcional da configuração do repositório.

## Requisitos

- Debian ou Ubuntu.
- Bash e ferramentas GNU.
- Acesso root ou `sudo` sem interação depois da validação inicial.
- Acesso à rede para `nginx.org`, GitHub e repositórios das dependências.
- Espaço em disco para fontes e artefatos temporários.
- `OPENSSL_VERSION` quando `OPENSSL_MODE=bundled`.
- `libssl-dev` quando `OPENSSL_MODE=system`; o script instala esse pacote automaticamente, exceto com `SKIP_DEPS=1`.

O script instala as dependências automaticamente, salvo quando `SKIP_DEPS=1` ou `--skip-deps` for usado. Mesmo nesse caso, todos os comandos necessários precisam estar instalados.

## Início rápido

Inspecione a interface antes de executar:

```bash
./build-nginx.sh --help
```

O `.env` versionado contém um perfil operacional preenchido. No estado atual, ele seleciona CPU nativa, OpenSSL bundled, canal stable, OpenSSL `3.5.7`, oito jobs, inicialização automática com `zero` e UPX desativado.

Para executar com o perfil do `.env`:

```bash
./build-nginx.sh
```

O build completo é privilegiado, modifica o sistema e pode levar bastante tempo. Não o use como teste rotineiro de alterações de texto.

Para selecionar as opções diretamente na CLI:

```bash
./build-nginx.sh \
    --stable \
    --bundled-openssl \
    --native-arch \
    --auto-var-init zero \
    --jobs 8 \
    --no-upx
```

Para um build pinned, forneça a versão do NGINX:

```bash
APP_VERSION='<versao-do-nginx>' \
OPENSSL_VERSION='<versao-do-openssl>' \
NGINX_CHANNEL=pinned \
./build-nginx.sh
```

## Fluxo do build

O `build-nginx.sh` executa dez fases:

1. Valida o host e instala dependências Debian/Ubuntu.
2. Prepara usuário, flags de compilação e diretório de build.
3. Resolve versão do NGINX e referências das dependências.
4. Clona as fontes. O OpenSSL é ignorado no modo `system`.
5. Aplica os patches de hardening do NGINX.
6. Prepara zlib-ng em modo compatível.
7. Compila Brotli.
8. Configura o NGINX e os módulos selecionados.
9. Compila o NGINX.
10. Instala, opcionalmente comprime com UPX e valida o binário e a configuração.

As fases escrevem no log definido por `BUILD_LOG`. O padrão é `/tmp/nginx-build.log`.

## Opções da linha de comando

| Opção | Descrição |
| --- | --- |
| `--prefix PATH` | Prefixo de instalação. Default: `/usr/share`. |
| `--sbin-path PATH` | Caminho do binário. Default: `/usr/sbin/nginx`. |
| `--conf-path PATH` | Caminho da configuração principal. Default: `/etc/nginx/nginx.conf`. |
| `--stable` | Resolve e compila a release stable mais recente. |
| `--latest`, `--mainline` | Resolve e compila a release mainline mais recente. |
| `--interactive` | Permite selecionar o canal em um menu interativo. |
| `--version VERSION` | Fixa a versão do NGINX e muda o canal para `pinned`. |
| `--system-openssl` | Usa OpenSSL e `libssl-dev` da distribuição. |
| `--bundled-openssl` | Baixa e compila o OpenSSL. É o modo padrão do script. |
| `--native-arch` | Usa `-march=native -mtune=native` em hosts x86_64/amd64. |
| `--generic-arch` | Usa tuning portátil. Default: `-march=x86-64 -mtune=generic` em x86_64. |
| `--auto-var-init MODE` | Seleciona `zero`, `pattern` ou `uninitialized`. |
| `--log-path PATH` | Define o log detalhado do build. |
| `--jobs N` | Define o número de jobs paralelos. Por padrão usa `nproc`. |
| `--build-dir PATH` | Usa e preserva um diretório de build específico. |
| `--keep-build` | Preserva o diretório temporário de fontes e artefatos. |
| `--skip-deps` | Não executa instalação de pacotes com `apt-get`. |
| `--no-config` | Não instala `etc/nginx/nginx.conf` nem os arquivos `.conf` de `etc/nginx/conf.d/`. |
| `--no-upx` | Desativa compressão do binário com UPX. |
| `--debug` | Adiciona suporte de debug ao NGINX. |
| `-h`, `--help` | Exibe a ajuda. |

Argumentos da CLI têm precedência sobre valores carregados do `.env`.

## Configuração do `.env`

O carregador aceita somente as variáveis listadas nesta seção. Variáveis desconhecidas são ignoradas. Valores vazios normalmente permitem que o script use o default interno ou resolva uma referência automaticamente.

### Versão, canal e referências

| Variável | Default do script | Descrição |
| --- | --- | --- |
| `APP_VERSION` | vazio | Versão do NGINX. Obrigatória quando `NGINX_CHANNEL=pinned`; em `stable`/`mainline` é resolvida externamente. |
| `NGINX_CHANNEL` | `pinned` | Aceita `pinned`, `stable` ou `mainline`. |
| `NGINX_REF` | `release-$APP_VERSION` | Ref do repositório NGINX. Útil para fixar tag ou commit. |
| `OPENSSL_MODE` | `bundled` | Aceita `bundled` ou `system`. |
| `OPENSSL_VERSION` | vazio | Obrigatória no modo `bundled`. Define a versão padrão da ref `openssl-$OPENSSL_VERSION`. |
| `OPENSSL_REF` | `openssl-$OPENSSL_VERSION` | Ref exata do repositório OpenSSL bundled. |
| `PCRE_VERSION` | vazio | Versão de fallback usada para resolver PCRE2 quando `PCRE_REF` está vazio. |
| `PCRE_REF` | vazio | Tag ou commit do PCRE2. Vazio resolve a release mais recente. |
| `ZLIB_VERSION` | vazio | Versão de fallback do zlib-ng. |
| `ZLIB_REF` | vazio | Tag ou commit do zlib-ng. Vazio resolve a release mais recente. |
| `ZSTD_VERSION` | vazio | Versão de fallback do módulo zstd. |
| `ZSTD_REF` | vazio | Tag ou commit do `zstd-nginx-module`. Vazio resolve a release mais recente. |
| `BROTLI_REF` | vazio | Tag ou commit do `ngx_brotli`. Vazio usa a ref padrão do clone. |
| `HEADERS_MORE_REF` | vazio | Tag ou commit do `headers-more-nginx-module`. |
| `CACHE_PURGE_REF` | vazio | Tag ou commit do `ngx_cache_purge`. |
| `INTERACTIVE` | `0` | Use `1` para selecionar o canal interativamente. |

Para builds reproduzíveis, fixe `APP_VERSION`, `NGINX_REF`, `OPENSSL_VERSION`, `OPENSSL_REF` e todas as refs de dependências. Canais `stable` e `mainline` consultam fontes externas e podem mudar com o tempo.

### OpenSSL e KTLS

No modo bundled, o script clona o OpenSSL e passa ao configure:

```text
enable-quic enable-ktls
```

No modo system, o script instala `libssl-dev`, não clona o OpenSSL e omite `--with-openssl` e `--with-openssl-opt` do configure do NGINX.

`enable-ktls` é uma opção de compilação do OpenSSL. O NGINX não consegue ativá-la depois de vincular uma biblioteca OpenSSL da distribuição. Usar OpenSSL system não desativa KTLS automaticamente, mas o suporte depende de:

- OpenSSL da distribuição compilado com KTLS.
- Kernel com suporte a KTLS.
- Cifra e caminho TLS compatíveis.
- Suporte efetivo do hardware e do runtime.

O modo system também pode falhar no HTTP/3 se o OpenSSL da distribuição não fornecer a API QUIC exigida pela versão do NGINX. Não remova HTTP/3 silenciosamente para contornar essa incompatibilidade.

### Paths de instalação e logs

| Variável | Default |
| --- | --- |
| `BUILD_LOG` | `/tmp/nginx-build.log` |
| `PREFIX` | `/usr/share` |
| `SBIN_PATH` | `/usr/sbin/nginx` |
| `CONF_PATH` | `/etc/nginx/nginx.conf` |
| `PID_PATH` | `/var/run/nginx.pid` |
| `LOCK_PATH` | `/var/lock/nginx.lock` |
| `HTTP_LOG_PATH` | `/var/log/nginx/access.log` |
| `ERROR_LOG_PATH` | `/var/log/nginx/error.log` |
| `CLIENT_TEMP_PATH` | `/var/lib/nginx/body` |
| `PROXY_TEMP_PATH` | `/var/lib/nginx/proxy` |
| `FASTCGI_TEMP_PATH` | `/var/lib/nginx/fastcgi` |
| `LOG_DIR` | `/var/log/nginx` |
| `CACHE_DIR` | `/var/cache/nginx` |

Quando `INSTALL_CONFIG=1`, o script copia a configuração base, copia todos os arquivos `*.conf` de `etc/nginx/conf.d/` e adapta os includes ao diretório derivado de `CONF_PATH`. Arquivos `.conf.example` não são carregados nem copiados.

### Usuário e toolchain

| Variável | Default |
| --- | --- |
| `RUNTIME_USER` | `www-data` |
| `RUNTIME_GROUP` | `www-data` |
| `CC` | `clang` |
| `CXX` | `clang++` |
| `LD` | `lld` |
| `AR` | `llvm-ar` |
| `NM` | `llvm-nm` |
| `RANLIB` | `llvm-ranlib` |
| `STRIP` | `llvm-strip` |

Alternativa GCC recomendada para LTO:

```dotenv
CC=gcc
CXX=g++
LD=ld.lld
AR=gcc-ar
NM=gcc-nm
RANLIB=gcc-ranlib
STRIP=strip
```

### Controles do build

| Variável | Default | Descrição |
| --- | --- | --- |
| `CPU_OPT` | `native` | Aceita `generic` ou `native`. O perfil `native` (`-march=native -mtune=native`) é o padrão em x86_64/amd64. |
| `AUTO_VAR_INIT` | `pattern` | Aceita `zero`, `pattern` ou `uninitialized`. |
| `JOBS` | vazio | Vazio usa o resultado de `nproc`; caso contrário deve ser inteiro positivo. |
| `BUILD_DIR` | vazio | Vazio cria diretório temporário; preenchido preserva o diretório indicado. |
| `KEEP_BUILD` | `0` | Com `1`, preserva diretório temporário após o build. |
| `SKIP_DEPS` | `0` | Com `1`, pula `apt-get`, mas exige todas as ferramentas instaladas. |
| `INSTALL_CONFIG` | `1` | Com `0`, instala somente o NGINX e não copia a configuração do repositório. |
| `ENABLE_UPX` | `auto` | Aceita `auto`, `0` ou `1`. O perfil atual do `.env` usa `0`. |
| `NGINX_DEBUG` | `0` | Com `1`, adiciona suporte de debug ao NGINX. |

### Tuning de CPU

`CPU_OPT=generic` é o perfil portátil:

```text
-march=x86-64 -mtune=generic
```

`CPU_OPT=native` ou `--native-arch` usa:

```text
-march=native -mtune=native
```

As flags nativas também são usadas nas dependências compiladas pelo script. O binário gerado é específico para o host e não deve ser distribuído para CPUs incompatíveis. Para imagens genéricas, mantenha `CPU_OPT=generic`.

### Inicialização automática de variáveis

`AUTO_VAR_INIT` controla a flag `-ftrivial-auto-var-init` nas flags de hardening do NGINX e dos módulos compilados junto com ele.

| Valor | Comportamento |
| --- | --- |
| `pattern` | Preenche variáveis automáticas não inicializadas com um padrão conhecido. É o default do script. |
| `zero` | Inicializa essas variáveis com zero. Pode ter custo de escrita, mas oferece comportamento determinístico e proteção contra leituras não inicializadas. |
| `uninitialized` | Remove a inicialização automática para priorizar o menor overhead. Reduz a proteção contra bugs de memória e deve ser usado somente após análise de risco. |

Exemplos:

```bash
./build-nginx.sh --auto-var-init zero
./build-nginx.sh --auto-var-init pattern
./build-nginx.sh --auto-var-init uninitialized
```

### UPX

UPX comprime o executável instalado para reduzir seu tamanho em disco. Isso não é uma otimização de throughput do NGINX e pode complicar debugging, profiling, assinatura e ferramentas de segurança.

O modo `auto` pula UPX quando o binário x86_64 usa CET/IBT. Forçar `ENABLE_UPX=1` nessa combinação causa erro intencional. Para desativar:

```bash
./build-nginx.sh --no-upx
```

## Configuração NGINX

### Arquivos

| Arquivo | Função |
| --- | --- |
| `etc/nginx/nginx.conf` | Configuração base com eventos, HTTP, TLS, compressão, proxy, rate limits e fallback. |
| `etc/nginx/conf.d/webp.conf` | Mapa `$webp_suffix` para seleção de arquivos `.webp`. |
| `etc/systemd/system/nginx.service` | Unidade systemd para o binário customizado em `/usr/sbin/nginx`. |
| `etc/logrotate.d/nginx` | Rotação dos logs do NGINX. |

O `nginx.conf` contém um fallback HTTP na porta 80 que rejeita hosts não configurados com `444`, limites agressivos e timeouts curtos. Também contém fallback TLS/QUIC na porta 443 com `ssl_reject_handshake on`. Virtual hosts nomeados em `conf.d` têm precedência sobre o fallback.

O arquivo base inclui suporte a:

- HTTP/1.1, HTTP/2 e HTTP/3/QUIC por virtual host.
- TLS 1.2 e TLS 1.3.
- gzip, Brotli e zstd.
- WebSocket por meio do mapa `$connection_upgrade`.
- Proxy reverso com buffers e timeouts comuns.
- Cabeçalhos `nosniff`, `SAMEORIGIN`, `Referrer-Policy` e `Permissions-Policy`.

Certificados, HSTS, CSP e políticas específicas de aplicação devem ser definidos nos virtual hosts correspondentes, não globalmente sem avaliar o impacto.

### Exemplo de proxy WordPress

Um exemplo opt-in pode ser mantido como `etc/nginx/conf.d/wordpress.test.conf.example`. Enquanto estiver com a extensão `.example`, o instalador não o copia. Após provisionar certificado e chave para `wordpress.test`, renomeie para `.conf` e valide.

O exemplo redireciona HTTP para HTTPS e faz proxy para:

```text
127.0.0.1:8881
```

Certificados esperados pelo exemplo:

```text
/etc/nginx/ssl/wordpress.test.crt
/etc/nginx/ssl/wordpress.test.key
```

Para desenvolvimento local, adicione o domínio ao `/etc/hosts`:

```text
127.0.0.1 wordpress.test
```

## systemd

Por padrão (`INSTALL_CONFIG=1`), o `build-nginx.sh` instala a unidade systemd em `/etc/systemd/system/nginx.service` e executa `systemctl daemon-reload`. A unidade versionada usa:

```text
Binary: /usr/sbin/nginx
Config: /etc/nginx/nginx.conf
PID: /var/run/nginx.pid
```

Para implantar ou atualizar a unidade manualmente após validar a configuração:

```bash
sudo /usr/sbin/nginx -t -q -c /etc/nginx/nginx.conf
sudo install -o root -g root -m 0644 \
    etc/systemd/system/nginx.service \
    /etc/systemd/system/nginx.service
sudo systemctl daemon-reload
sudo systemctl enable --now nginx
```

Não inicie ou recarregue o serviço apenas para validar uma alteração de texto. Execute `nginx -t` antes.

## logrotate

Por padrão (`INSTALL_CONFIG=1`), o `build-nginx.sh` instala a rotação de log em `/etc/logrotate.d/nginx`. Para instalá-lo ou atualizá-lo manualmente:

```bash
sudo install -o root -g root -m 0644 \
    etc/logrotate.d/nginx \
    /etc/logrotate.d/nginx
```

Confirme que os caminhos de log usados no `nginx.conf` correspondem ao bloco do logrotate antes de executar uma rotação real.

## Validação

Não há suíte automatizada, gerenciador de dependências de aplicação ou pipeline de CI no projeto. Validações estáticas mínimas:

```bash
bash -n build-nginx.sh
./build-nginx.sh --help
```

Se disponível:

```bash
shellcheck build-nginx.sh
```

Depois de uma instalação real:

```bash
/usr/sbin/nginx -V
sudo /usr/sbin/nginx -t -c /etc/nginx/nginx.conf
```

Para a unidade:

```bash
systemd-analyze verify etc/systemd/system/nginx.service
```

O build completo não deve ser executado como teste rotineiro: ele instala pacotes, compila fontes, usa rede e pode modificar o sistema.

## Reprodutibilidade

Para um build tão reproduzível quanto possível, fixe:

- `APP_VERSION` e `NGINX_REF`.
- `OPENSSL_VERSION` e `OPENSSL_REF` no modo bundled.
- `PCRE_REF`, `ZLIB_REF` e `ZSTD_REF`.
- `BROTLI_REF`, `HEADERS_MORE_REF` e `CACHE_PURGE_REF`.
- Imagem/repositório Debian ou Ubuntu.
- Toolchain, `CPU_OPT` e modo OpenSSL.

`CPU_OPT=native` e OpenSSL system reduzem a portabilidade/reprodutibilidade. No modo system, fixe a imagem e os pacotes da distribuição, porque `OPENSSL_VERSION` não controla a biblioteca usada.

## Segurança operacional

- Não coloque tokens, senhas, chaves privadas ou credenciais no `.env`, README, logs ou mensagens de commit.
- Revise certificados e permissões de chaves privadas antes de ativar virtual hosts TLS.
- Não use `SKIP_DEPS=1` sem confirmar todas as dependências.
- Não force UPX com CET/IBT.
- Preserve logs e diretórios de build durante diagnóstico.
- Não remova flags de hardening, patches ou módulos sem verificar compatibilidade e impacto.
- Não distribua binários compilados com `CPU_OPT=native` para hosts desconhecidos.

## Troubleshooting

### `OPENSSL_VERSION is not set`

O modo bundled exige uma versão explícita:

```dotenv
OPENSSL_MODE=bundled
OPENSSL_VERSION=3.5.7
```

Ou altere para OpenSSL system:

```bash
./build-nginx.sh --system-openssl
```

### `nginx -t` mostra o binário ou configuração errados

Confirme os caminhos efetivos:

```bash
/usr/sbin/nginx -V
systemctl show nginx -p FragmentPath -p ExecStart -p ExecStartPre
```

Se `systemctl` mostrar `/usr/lib/systemd/system/nginx.service` e `/usr/sbin/nginx`, instale a unidade versionada e execute `systemctl daemon-reload`.

### Falha no HTTP/3 com OpenSSL system

A biblioteca da distribuição pode não fornecer a API QUIC necessária. Verifique:

```bash
openssl version -a
/usr/sbin/nginx -V
```

Use uma distribuição/libssl compatível ou volte ao modo bundled.

### UPX é ignorado

Em x86_64, o script pula UPX automaticamente quando CET/IBT está ativo. Isso é esperado e protege a compatibilidade do binário. Use `--no-upx` para deixar a intenção explícita.

## Licença e fontes

O projeto orquestra fontes do NGINX, OpenSSL, PCRE2, zlib-ng, Brotli, zstd e módulos de terceiros. Consulte as licenças e condições de distribuição de cada componente antes de redistribuir o binário ou as imagens geradas.
