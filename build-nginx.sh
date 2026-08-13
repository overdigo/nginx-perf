#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$SCRIPT_DIR
ENV_FILE=${ENV_FILE:-$REPO_DIR/.env}

log() {
    printf '[build-nginx] %s\n' "$*"
}

warn() {
    printf '[build-nginx] warning: %s\n' "$*" >&2
}

die() {
    printf '[build-nginx] error: %s\n' "$*" >&2
    exit 1
}

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    COLOR_BLUE=$'\033[1;34m'
    COLOR_GREEN=$'\033[1;32m'
    COLOR_RED=$'\033[1;31m'
    COLOR_RESET=$'\033[0m'
else
    COLOR_BLUE=''
    COLOR_GREEN=''
    COLOR_RED=''
    COLOR_RESET=''
fi

PHASE_INDEX=0
PHASE_TOTAL=10

phase() {
    local message

    PHASE_INDEX=$((PHASE_INDEX + 1))
    message=$(printf '[%02d/%02d] %s' "$PHASE_INDEX" "$PHASE_TOTAL" "$*")
    printf '\n%s%s%s\n' \
        "$COLOR_BLUE" "$message" "$COLOR_RESET"
    printf '%s\n' "$message" >>"$BUILD_LOG"
}

phase_ok() {
    printf '%s[ok]%s phase %02d/%02d completed\n' \
        "$COLOR_GREEN" "$COLOR_RESET" "$PHASE_INDEX" "$PHASE_TOTAL"
    printf '[ok] phase %02d/%02d completed\n' "$PHASE_INDEX" "$PHASE_TOTAL" >>"$BUILD_LOG"
}

phase_fail() {
    printf '%s[fail]%s phase %02d/%02d failed; see %s\n' \
        "$COLOR_RED" "$COLOR_RESET" "$PHASE_INDEX" "$PHASE_TOTAL" "$BUILD_LOG" >&2
    printf '[fail] phase %02d/%02d failed\n' "$PHASE_INDEX" "$PHASE_TOTAL" >>"$BUILD_LOG"
}

run_phase() {
    local description=$1
    local status
    shift

    phase "$description"
    set +e
    (
        set -Eeuo pipefail
        "$@"
    ) >>"$BUILD_LOG" 2>&1
    status=$?
    set -e

    if (( status == 0 )); then
        phase_ok
    else
        phase_fail
        return "$status"
    fi
}

init_build_log() {
    local log_dir

    log_dir=$(dirname -- "$BUILD_LOG")
    mkdir --parents -- "$log_dir"
    : >"$BUILD_LOG" || die "cannot write build log: $BUILD_LOG"
    printf 'build-nginx started at %s\n' "$(date --iso-8601=seconds)" >>"$BUILD_LOG"
    printf 'command: %q' "$0" >>"$BUILD_LOG"
    printf ' %q' "$@" >>"$BUILD_LOG"
    printf '\n' >>"$BUILD_LOG"
}

write_build_state() {
    {
        printf 'APP_VERSION=%q\n' "${APP_VERSION:-}"
        printf 'JOBS=%q\n' "${JOBS:-}"
        printf 'CPU_OPT=%q\n' "${CPU_OPT:-}"
        printf 'AUTO_VAR_INIT=%q\n' "${AUTO_VAR_INIT:-}"
        printf 'ARCH_CFLAGS=%q\n' "${ARCH_CFLAGS:-}"
        printf 'CET_CFLAGS=%q\n' "${CET_CFLAGS:-}"
        printf 'CET_LDFLAGS=%q\n' "${CET_LDFLAGS:-}"
        printf 'HARDENING_CFLAGS=%q\n' "${HARDENING_CFLAGS:-}"
        printf 'WARNING_CFLAGS=%q\n' "${WARNING_CFLAGS:-}"
        printf 'DEPENDENCY_CFLAGS=%q\n' "${DEPENDENCY_CFLAGS:-}"
        printf 'TEMP_BUILD=%q\n' "${TEMP_BUILD:-0}"
        printf 'BUILD_ROOT=%q\n' "${BUILD_ROOT:-}"
        printf 'OPENSSL_MODE=%q\n' "${OPENSSL_MODE:-}"
        printf 'NGINX_DIR=%q\n' "${NGINX_DIR:-}"
        printf 'OPENSSL_DIR=%q\n' "${OPENSSL_DIR:-}"
        printf 'PCRE_DIR=%q\n' "${PCRE_DIR:-}"
        printf 'ZLIB_DIR=%q\n' "${ZLIB_DIR:-}"
        printf 'BROTLI_DIR=%q\n' "${BROTLI_DIR:-}"
        printf 'ZSTD_DIR=%q\n' "${ZSTD_DIR:-}"
        printf 'HEADERS_MORE_DIR=%q\n' "${HEADERS_MORE_DIR:-}"
        printf 'CACHE_PURGE_DIR=%q\n' "${CACHE_PURGE_DIR:-}"
        printf 'HTTP_LOG_PATH=%q\n' "${HTTP_LOG_PATH:-}"
        printf 'ERROR_LOG_PATH=%q\n' "${ERROR_LOG_PATH:-}"
        printf 'CLIENT_TEMP_PATH=%q\n' "${CLIENT_TEMP_PATH:-}"
        printf 'PROXY_TEMP_PATH=%q\n' "${PROXY_TEMP_PATH:-}"
        printf 'FASTCGI_TEMP_PATH=%q\n' "${FASTCGI_TEMP_PATH:-}"
        printf 'MODULES_PATH=%q\n' "${MODULES_PATH:-}"
        printf 'LOG_DIR=%q\n' "${LOG_DIR:-}"
        printf 'CACHE_DIR=%q\n' "${CACHE_DIR:-}"
        printf 'PREFIX=%q\n' "${PREFIX:-}"
        printf 'SBIN_PATH=%q\n' "${SBIN_PATH:-}"
        printf 'CONF_PATH=%q\n' "${CONF_PATH:-}"
        printf 'PID_PATH=%q\n' "${PID_PATH:-}"
        printf 'LOCK_PATH=%q\n' "${LOCK_PATH:-}"
        printf 'RUNTIME_USER=%q\n' "${RUNTIME_USER:-}"
        printf 'RUNTIME_GROUP=%q\n' "${RUNTIME_GROUP:-}"
        printf 'nginx_ref=%q\n' "${nginx_ref:-}"
        printf 'openssl_ref=%q\n' "${openssl_ref:-}"
        printf 'pcre_ref=%q\n' "${pcre_ref:-}"
        printf 'zlib_ref=%q\n' "${zlib_ref:-}"
        printf 'zstd_ref=%q\n' "${zstd_ref:-}"
        printf 'brotli_ref=%q\n' "${brotli_ref:-}"
        printf 'headers_more_ref=%q\n' "${headers_more_ref:-}"
        printf 'cache_purge_ref=%q\n' "${cache_purge_ref:-}"
    } >"$BUILD_STATE_FILE"
}

load_build_state() {
    if [[ -f "$BUILD_STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$BUILD_STATE_FILE"
        rm -f -- "$BUILD_STATE_FILE"
    fi
}

trim_whitespace() {
    local value=$1

    value=${value#"${value%%[![:space:]]*}"}
    value=${value%"${value##*[![:space:]]}"}
    printf '%s' "$value"
}

load_env_file() {
    local line key value

    if [[ ! -f "$ENV_FILE" ]]; then
        warn "environment file not found: $ENV_FILE"
        return 0
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%$'\r'}
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        [[ "$line" == *=* ]] || continue

        key=${line%%=*}
        value=${line#*=}
        key=${key//[[:space:]]/}

        case "$key" in
            APP_VERSION|CPU_OPT|AUTO_VAR_INIT|OPENSSL_MODE|OPENSSL_VERSION|PCRE_VERSION|PCRE_REF|ZLIB_VERSION|ZLIB_REF|ZSTD_VERSION|ZSTD_REF|NGINX_REF|OPENSSL_REF|BROTLI_REF|HEADERS_MORE_REF|CACHE_PURGE_REF|NGINX_CHANNEL|INTERACTIVE|BUILD_LOG|PREFIX|SBIN_PATH|CONF_PATH|PID_PATH|LOCK_PATH|HTTP_LOG_PATH|ERROR_LOG_PATH|CLIENT_TEMP_PATH|PROXY_TEMP_PATH|FASTCGI_TEMP_PATH|LOG_DIR|CACHE_DIR|MODULES_PATH|RUNTIME_USER|RUNTIME_GROUP|CC|CXX|LD|AR|NM|RANLIB|STRIP|JOBS|BUILD_DIR|KEEP_BUILD|SKIP_DEPS|INSTALL_CONFIG|ENABLE_UPX|NGINX_DEBUG)
                if [[ ! -v "$key" ]]; then
                    value=$(trim_whitespace "$value")
                    if [[ "$value" == \"*\"* ]]; then
                        value=${value#\"}
                        value=${value%%\"*}
                    elif [[ "$value" == \'*\'* ]]; then
                        value=${value#\'}
                        value=${value%%\'*}
                    else
                        value=${value%%[[:space:]]#*}
                        value=$(trim_whitespace "$value")
                    fi
                    printf -v "$key" '%s' "$value"
                fi
                ;;
        esac
    done < "$ENV_FILE"
}

usage() {
    cat <<'EOF'
Usage: ./build-nginx.sh [options]

Build and install NGINX natively on Debian or Ubuntu.

Options:
  --prefix PATH          NGINX installation prefix (default: /usr/share)
  --sbin-path PATH       NGINX binary path (default: /usr/sbin/nginx)
  --conf-path PATH       NGINX configuration path (default: /etc/nginx/nginx.conf)
  --stable               Build the latest stable NGINX release
  --latest, --mainline   Build the latest NGINX mainline release
  --interactive          Choose the release channel from a menu
  --version VERSION      Build an explicit NGINX version
  --system-openssl       Use the distribution OpenSSL and libssl-dev
  --bundled-openssl      Download and build OpenSSL (default)
  --native-arch           Use -march=native -mtune=native on x86_64 (default)
  --generic-arch          Use portable architecture tuning
  --auto-var-init MODE    Set automatic variable initialization: zero, pattern or uninitialized
  --log-path PATH        Detailed log file (default: /tmp/nginx-build.log)
  --jobs N               Number of parallel build jobs
  --build-dir PATH       Keep sources and build files in PATH
  --keep-build           Keep the temporary build directory
  --skip-deps            Do not install packages with apt
  --no-config            Do not install the repository NGINX configuration
  --no-upx               Do not compress the installed binary with UPX
  --debug                Include NGINX debug support
  -h, --help             Show this help

The default channel is pinned: APP_VERSION from .env or the environment is
used. Set NGINX_CHANNEL=stable or NGINX_CHANNEL=mainline to resolve the latest
release from nginx.org. OpenSSL uses the bundled source by default; set
OPENSSL_MODE=system to use the distribution development package instead. Set
CPU_OPT=native or use --native-arch to optimize for the build host CPU. Set
PCRE_REF, ZLIB_REF and ZSTD_REF for reproducible dependency revisions.
EOF
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --prefix)
                (($# >= 2)) || die "--prefix requires a path"
                PREFIX=$2
                shift 2
                ;;
            --sbin-path)
                (($# >= 2)) || die "--sbin-path requires a path"
                SBIN_PATH=$2
                shift 2
                ;;
            --conf-path)
                (($# >= 2)) || die "--conf-path requires a path"
                CONF_PATH=$2
                shift 2
                ;;
            --stable)
                NGINX_CHANNEL=stable
                shift
                ;;
            --latest|--mainline)
                NGINX_CHANNEL=mainline
                shift
                ;;
            --interactive)
                INTERACTIVE=1
                shift
                ;;
            --version)
                (($# >= 2)) || die "--version requires a version"
                APP_VERSION=$2
                NGINX_CHANNEL=pinned
                shift 2
                ;;
            --system-openssl)
                OPENSSL_MODE=system
                shift
                ;;
            --bundled-openssl)
                OPENSSL_MODE=bundled
                shift
                ;;
            --native-arch)
                CPU_OPT=native
                shift
                ;;
            --generic-arch)
                CPU_OPT=generic
                shift
                ;;
            --auto-var-init)
                (($# >= 2)) || die "--auto-var-init requires zero, pattern or uninitialized"
                AUTO_VAR_INIT=$2
                shift 2
                ;;
            --log-path)
                (($# >= 2)) || die "--log-path requires a path"
                BUILD_LOG=$2
                shift 2
                ;;
            --jobs)
                (($# >= 2)) || die "--jobs requires a number"
                JOBS=$2
                shift 2
                ;;
            --build-dir)
                (($# >= 2)) || die "--build-dir requires a path"
                BUILD_DIR=$2
                shift 2
                ;;
            --keep-build)
                KEEP_BUILD=1
                shift
                ;;
            --skip-deps)
                SKIP_DEPS=1
                shift
                ;;
            --no-config)
                INSTALL_CONFIG=0
                shift
                ;;
            --no-upx)
                ENABLE_UPX=0
                shift
                ;;
            --debug)
                NGINX_DEBUG=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

latest_release_tag() {
    local repository=$1

    curl --fail --silent --show-error --compressed --location --retry 3 \
        --connect-timeout 10 --max-time 120 \
        --header 'Accept: application/vnd.github+json' \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        "https://api.github.com/repos/$repository/releases/latest" \
        | jq --raw-output --exit-status '.tag_name'
}

latest_nginx_version() {
    local channel=$1
    local version

    if ! version=$(
        curl --fail --silent --show-error --compressed --location --retry 3 \
            --connect-timeout 10 --max-time 120 \
            'https://nginx.org/en/download.html' \
            | grep --extended-regexp --only-matching 'nginx-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' \
            | sed -E 's/^nginx-//; s/\.tar\.gz$//' \
            | sort --version-sort --unique \
            | awk -F. -v channel="$channel" '
                ($2 % 2 == 0 && channel == "stable") ||
                ($2 % 2 == 1 && channel == "mainline") { version = $0 }
                END {
                    if (version != "") {
                        print version
                    } else {
                        exit 1
                    }
                }
            '
    ); then
        die "could not resolve the latest $channel NGINX release from nginx.org"
    fi

    printf '%s\n' "$version"
}

select_channel() {
    local selection

    case "$NGINX_CHANNEL" in
        latest)
            NGINX_CHANNEL=mainline
            ;;
        pinned|stable|mainline)
            ;;
        *)
            die "NGINX_CHANNEL must be pinned, stable or mainline"
            ;;
    esac

    if [[ "$INTERACTIVE" == 1 ]]; then
        [[ -t 0 ]] || die "--interactive requires a terminal"
        printf '\nSelect the NGINX release channel:\n'
        printf '  1) stable\n'
        printf '  2) latest/mainline\n'
        printf '  3) pinned version from .env\n'
        printf 'Choice [1-3]: '
        read -r selection || die "could not read the release channel"
        case "$selection" in
            1)
                NGINX_CHANNEL=stable
                ;;
            2)
                NGINX_CHANNEL=mainline
                ;;
            3)
                NGINX_CHANNEL=pinned
                ;;
            *)
                die "invalid release channel choice: $selection"
                ;;
        esac
    fi
}

clone_repository() {
    local repository=$1
    local destination=$2
    local revision=${3:-}

    if [[ -n "$revision" ]]; then
        git -c advice.detachedHead=false -c http.lowSpeedLimit=1000 \
            -c http.lowSpeedTime=60 clone --quiet --depth 1 \
            --single-branch --branch "$revision" --recurse-submodules \
            --shallow-submodules "https://github.com/$repository" "$destination"
    else
        git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 clone --quiet \
            --depth 1 --recurse-submodules --shallow-submodules \
            "https://github.com/$repository" "$destination"
    fi
}

patch_source() {
    local file=$1
    local expression=$2
    local replacement=$3
    local description=$4

    [[ -f "$file" ]] || die "cannot patch missing source file for $description: $file"

    if grep --fixed-strings --quiet -- "$expression" "$file"; then
        sed --in-place "s@${expression}@${replacement}@g" "$file"
        log "patched $description"
    else
        die "required hardening pattern not found for $description in $file"
    fi
}

install_dependencies() {
    local -a packages=(
        build-essential
        clang
        lld
        llvm
        make
        git
        ca-certificates
        curl
        jq
        perl
        cmake
        pkg-config
        zlib1g-dev
        libzstd-dev
    )

    if [[ "$OPENSSL_MODE" == system ]]; then
        packages+=(openssl libssl-dev)
    fi

    if [[ "$SKIP_DEPS" == 1 ]]; then
        log "skipping apt dependency installation"
        return 0
    fi

    [[ -x "$(command -v apt-get || true)" ]] || die "apt-get is required on Debian/Ubuntu"

    log "updating apt package indexes"
    run_root apt-get update

    if [[ "$ENABLE_UPX" != 0 ]]; then
        case "$(uname -m)" in
            x86_64|amd64)
                ;;
            *)
                if apt-cache show upx-ucl >/dev/null 2>&1; then
                    packages+=(upx-ucl)
                fi
                ;;
        esac
    fi

    log "installing build dependencies"
    run_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends "${packages[@]}"
}

ensure_runtime_user() {
    if ! getent group "$RUNTIME_GROUP" >/dev/null 2>&1; then
        log "creating system group: $RUNTIME_GROUP"
        run_root groupadd --system "$RUNTIME_GROUP"
    fi

    if ! getent passwd "$RUNTIME_USER" >/dev/null 2>&1; then
        log "creating system user: $RUNTIME_USER"
        run_root useradd --system --no-create-home --shell /usr/sbin/nologin \
            --gid "$RUNTIME_GROUP" "$RUNTIME_USER"
    fi
}

prepare_build_directory() {
    if [[ -n "$BUILD_DIR" ]]; then
        BUILD_ROOT=$BUILD_DIR
        TEMP_BUILD=0
        mkdir -p -- "$BUILD_ROOT"
    else
        BUILD_ROOT=$(mktemp --directory --tmpdir nginx-build.XXXXXX)
        TEMP_BUILD=1
    fi

    NGINX_DIR=$BUILD_ROOT/nginx
    OPENSSL_DIR=$BUILD_ROOT/openssl
    PCRE_DIR=$BUILD_ROOT/pcre2
    ZLIB_DIR=$BUILD_ROOT/zlib-ng
    BROTLI_DIR=$BUILD_ROOT/ngx_brotli
    ZSTD_DIR=$BUILD_ROOT/zstd-nginx-module
    HEADERS_MORE_DIR=$BUILD_ROOT/headers-more-nginx-module
    CACHE_PURGE_DIR=$BUILD_ROOT/ngx_cache_purge
}

cleanup() {
    if [[ "${TEMP_BUILD:-0}" == 1 && "${KEEP_BUILD:-0}" != 1 && -n "${BUILD_ROOT:-}" && -d "$BUILD_ROOT" ]]; then
        rm -rf -- "$BUILD_ROOT"
    fi
    if [[ -n "${BUILD_STATE_FILE:-}" && -f "$BUILD_STATE_FILE" ]]; then
        rm -f -- "$BUILD_STATE_FILE"
    fi
}

prepare_zlib() {
    log "preparing zlib-ng in compatibility mode"
    (
        cd -- "$ZLIB_DIR"
        grep --fixed-strings --quiet -- 'compat=0' configure \
            || die "zlib-ng compatibility marker not found in $ZLIB_DIR/configure"
        sed --in-place 's/compat=0/compat=1/g' configure
        CC="$CC" CFLAGS="$DEPENDENCY_CFLAGS" ./configure --zlib-compat
        make --jobs "$JOBS"
        make clean
    )
}

build_brotli() {
    local brotli_build_dir=$BROTLI_DIR/deps/brotli/out

    log "building Brotli"
    cmake -S "$BROTLI_DIR/deps/brotli" -B "$brotli_build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DBUILD_SHARED_LIBS=OFF \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCMAKE_C_COMPILER="$CC" \
        -DCMAKE_CXX_COMPILER="$CXX" \
        -DCMAKE_C_FLAGS="$DEPENDENCY_CFLAGS" \
        -DCMAKE_CXX_FLAGS="$DEPENDENCY_CFLAGS"
    cmake --build "$brotli_build_dir" --config Release \
        --target brotlienc --parallel "$JOBS"
}

configure_nginx() {
    local nginx_cflags
    local nginx_ldflags
    local -a configure_args

    nginx_cflags="$HARDENING_CFLAGS $WARNING_CFLAGS"
    nginx_ldflags="-fuse-ld=lld -pie -Wl,-z,relro,-z,now -Wl,-z,noexecstack -Wl,-z,separate-code -Wl,--as-needed"

    if [[ -n "$CET_LDFLAGS" ]]; then
        nginx_ldflags="$nginx_ldflags $CET_LDFLAGS"
    fi

    log "configuring NGINX $APP_VERSION"
    configure_args=(
        ./auto/configure
        --prefix="$PREFIX"
        --sbin-path="$SBIN_PATH"
        --user="$RUNTIME_USER"
        --group="$RUNTIME_GROUP"
        --http-log-path="$HTTP_LOG_PATH"
        --error-log-path="$ERROR_LOG_PATH"
        --conf-path="$CONF_PATH"
        --pid-path="$PID_PATH"
        --lock-path="$LOCK_PATH"
        --http-client-body-temp-path="$CLIENT_TEMP_PATH"
        --http-proxy-temp-path="$PROXY_TEMP_PATH"
        --http-fastcgi-temp-path="$FASTCGI_TEMP_PATH"
        --modules-path="$MODULES_PATH"
        --with-pcre="$PCRE_DIR"
        --with-zlib="$ZLIB_DIR"
        --with-cc-opt="$nginx_cflags"
        --with-ld-opt="$nginx_ldflags"
        --with-compat
        --with-pcre-jit
        --with-threads
        --with-http_realip_module
        --with-http_stub_status_module
        --with-http_ssl_module
        --with-http_v2_module
        --with-http_v3_module
        --with-http_gzip_static_module
        --with-stream
        --with-stream_realip_module
        --with-stream_ssl_module
        --with-stream_ssl_preread_module
        --without-stream_split_clients_module
        --without-stream_set_module
        --without-http_scgi_module
        --without-http_uwsgi_module
        --without-http_autoindex_module
        --without-http_split_clients_module
        --without-http_memcached_module
        --without-http_ssi_module
        --without-http_empty_gif_module
        --without-http_browser_module
        --without-http_userid_module
        --without-http_mirror_module
        --without-http_referer_module
        --without-mail_pop3_module
        --without-mail_imap_module
        --without-mail_smtp_module
        --add-module="$BROTLI_DIR"
        --add-module="$ZSTD_DIR"
        --add-module="$HEADERS_MORE_DIR"
        --add-module="$CACHE_PURGE_DIR"
    )

    if [[ "$OPENSSL_MODE" == bundled ]]; then
        configure_args+=(
            --with-openssl="$OPENSSL_DIR"
            '--with-openssl-opt=enable-ec_nistp_64_gcc_128 no-tls1 no-tls1_1 no-shared no-weak-ssl-ciphers enable-quic enable-ktls zlib'
        )
    else
        log "using system OpenSSL; QUIC and KTLS depend on the distribution build"
    fi

    if [[ "$NGINX_DEBUG" == 1 ]]; then
        configure_args+=(--with-debug)
    fi

    (
        cd -- "$NGINX_DIR"
        CC="$CC" CXX="$CXX" LD="$LD" AR="$AR" NM="$NM" RANLIB="$RANLIB" STRIP="$STRIP" \
            "${configure_args[@]}"
    )
}

build_nginx() {
    log "compiling NGINX"
    (
        cd -- "$NGINX_DIR"
        make --jobs "$JOBS"
    )
}

install_nginx() {
    local conf_dir mime_types config_file config_name
    local escaped_value
    local -a temp_dirs

    log "installing NGINX into $PREFIX"
    (
        cd -- "$NGINX_DIR"
        run_root make install
    )

    run_root "$STRIP" --strip-unneeded "$SBIN_PATH"

    conf_dir=$(dirname -- "$CONF_PATH")
    run_root install --directory --mode 0755 \
        "$conf_dir" "$conf_dir/conf.d" "$conf_dir/stream.d"

    mime_types=$NGINX_DIR/conf/mime.types
    if [[ -f "$mime_types" ]]; then
        run_root install --mode 0644 "$mime_types" "$conf_dir/mime.types"
        if [[ "$PREFIX/mime.types" != "$conf_dir/mime.types" ]]; then
            run_root install --directory --mode 0755 "$PREFIX"
            run_root install --mode 0644 "$mime_types" "$PREFIX/mime.types"
        fi
    fi

    if [[ "$INSTALL_CONFIG" == 1 ]]; then
        log "installing repository configuration"
        run_root install --mode 0644 \
            "$REPO_DIR/etc/nginx/nginx.conf" "$CONF_PATH"
        for config_file in "$REPO_DIR/etc/nginx/conf.d/"*.conf; do
            [[ -f "$config_file" ]] || continue
            config_name=${config_file##*/}
            run_root install --mode 0644 "$config_file" "$conf_dir/conf.d/$config_name"
        done

        # Keep the repository placeholders while using native host paths.
        escaped_value=${conf_dir//\\/\\\\}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        run_root sed --in-place "s|^    include /etc/nginx/mime.types;|    include $escaped_value/mime.types;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    include ${conf_dir}/mime.types;" "$CONF_PATH" \
            || die "failed to configure the native MIME types path in $CONF_PATH"
        run_root sed --in-place "s|^    include /etc/nginx/conf.d/\\*\\.conf;|    include $escaped_value/conf.d/*.conf;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    include ${conf_dir}/conf.d/*.conf;" "$CONF_PATH" \
            || die "failed to configure the native include path in $CONF_PATH"
        run_root sed --in-place "s|^    include /etc/nginx/stream.d/\\*\\.conf;|    include $escaped_value/stream.d/*.conf;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    include ${conf_dir}/stream.d/*.conf;" "$CONF_PATH" \
            || die "failed to configure the native stream include path in $CONF_PATH"

        escaped_value=${PID_PATH//\\/\\\\}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        run_root sed --in-place "s|^pid /tmp/nginx.pid;|pid $escaped_value;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "pid ${PID_PATH};" "$CONF_PATH" \
            || die "failed to configure the native PID path in $CONF_PATH"

        escaped_value=${HTTP_LOG_PATH//\\/\\\\}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        run_root sed --in-place "s|^    access_log /dev/stdout main;|    access_log $escaped_value main;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    access_log ${HTTP_LOG_PATH} main;" "$CONF_PATH" \
            || die "failed to configure the native access log in $CONF_PATH"

        escaped_value=${ERROR_LOG_PATH//\\/\\\\}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        run_root sed --in-place "s|^    error_log stderr warn;|    error_log $escaped_value warn;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    error_log ${ERROR_LOG_PATH} warn;" "$CONF_PATH" \
            || die "failed to configure the native error log in $CONF_PATH"

        escaped_value=${CLIENT_TEMP_PATH//\\/\\\\}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        run_root sed --in-place "s|^    client_body_temp_path /tmp/client_temp;|    client_body_temp_path $escaped_value;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    client_body_temp_path ${CLIENT_TEMP_PATH};" "$CONF_PATH" \
            || die "failed to configure the native client temp path in $CONF_PATH"

        escaped_value=${PROXY_TEMP_PATH//\\/\\\\}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        run_root sed --in-place "s|^    proxy_temp_path /tmp/proxy_temp;|    proxy_temp_path $escaped_value;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    proxy_temp_path ${PROXY_TEMP_PATH};" "$CONF_PATH" \
            || die "failed to configure the native proxy temp path in $CONF_PATH"

        escaped_value=${FASTCGI_TEMP_PATH//\\/\\\\}
        escaped_value=${escaped_value//&/\\&}
        escaped_value=${escaped_value//|/\\|}
        run_root sed --in-place "s|^    fastcgi_temp_path /tmp/fastcgi_temp;|    fastcgi_temp_path $escaped_value;|" "$CONF_PATH"
        run_root grep --fixed-strings --quiet -- "    fastcgi_temp_path ${FASTCGI_TEMP_PATH};" "$CONF_PATH" \
            || die "failed to configure the native FastCGI temp path in $CONF_PATH"

        if [[ -f "$REPO_DIR/etc/logrotate.d/nginx" ]]; then
            log "installing logrotate configuration into /etc/logrotate.d/nginx"
            run_root install --directory --mode 0755 /etc/logrotate.d
            run_root install --owner root --group root --mode 0644 \
                "$REPO_DIR/etc/logrotate.d/nginx" /etc/logrotate.d/nginx
        fi

        if [[ -f "$REPO_DIR/etc/systemd/system/nginx.service" ]]; then
            log "installing systemd service unit into /etc/systemd/system/nginx.service"
            run_root install --directory --mode 0755 /etc/systemd/system
            run_root install --owner root --group root --mode 0644 \
                "$REPO_DIR/etc/systemd/system/nginx.service" /etc/systemd/system/nginx.service
            if command -v systemctl >/dev/null 2>&1; then
                run_root systemctl daemon-reload || true
            fi
        fi
    fi

    temp_dirs=(
        "$CLIENT_TEMP_PATH"
        "$PROXY_TEMP_PATH"
        "$FASTCGI_TEMP_PATH"
        /tmp/client_temp
        /tmp/proxy_temp
        /tmp/fastcgi_temp
    )
    run_root install --directory --owner "$RUNTIME_USER" --group "$RUNTIME_GROUP" \
        --mode 0750 "${temp_dirs[@]}"
    run_root mkdir --parents -- "$(dirname -- "$PID_PATH")" "$(dirname -- "$LOCK_PATH")"
    run_root install --directory --owner "$RUNTIME_USER" --group "$RUNTIME_GROUP" \
        --mode 0750 "$LOG_DIR" "$CACHE_DIR"
}

compress_binary() {
    case "$ENABLE_UPX" in
        0|false|no)
            log "UPX compression disabled"
            ;;
        1|true|yes)
            [[ -z "$CET_LDFLAGS" ]] || die "UPX is incompatible with CET/IBT; use --no-upx"
            require_command upx
            log "compressing NGINX with UPX"
            run_root upx --best --lzma "$SBIN_PATH"
            ;;
        auto)
            if [[ -n "$CET_LDFLAGS" ]]; then
                warn "skipping UPX because the binary uses CET/IBT hardening"
            elif command -v upx >/dev/null 2>&1; then
                log "compressing NGINX with UPX"
                run_root upx --best --lzma "$SBIN_PATH"
            else
                warn "UPX is not installed; leaving the binary uncompressed"
            fi
            ;;
        *)
            die "ENABLE_UPX must be auto, 0 or 1"
            ;;
    esac
}

verify_installation() {
    log "checking installed binary"
    "$SBIN_PATH" -V 2>&1 | sed -n '1,3p'
    file "$SBIN_PATH" || true

    if [[ "$INSTALL_CONFIG" == 1 ]]; then
        log "testing NGINX configuration"
        run_root "$SBIN_PATH" -t -c "$CONF_PATH"
    fi

    log "NGINX installation completed"
    log "binary: $SBIN_PATH"
    log "config: $CONF_PATH"
}

phase_install_dependencies() {
    install_dependencies
    require_command apt-cache
    require_command git
    require_command curl
    require_command jq
    require_command cmake
    require_command make
    require_command nproc
    require_command "$CC"
    require_command "$CXX"
    require_command "$LD"
    require_command "$AR"
    require_command "$NM"
    require_command "$RANLIB"
    require_command "$STRIP"
    require_command getent
    require_command install
    require_command dirname
    require_command awk
    require_command grep
    require_command sed
    require_command sort
    if [[ "$OPENSSL_MODE" == system ]]; then
        require_command openssl
    fi
}

phase_prepare_environment() {
    local arch

    if [[ -z "$JOBS" ]]; then
        JOBS=$(nproc)
    fi
    [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || die "JOBS must be a positive integer"

    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            if [[ "$CPU_OPT" == native ]]; then
                ARCH_CFLAGS='-march=native -mtune=native'
            else
                ARCH_CFLAGS='-march=x86-64 -mtune=generic'
            fi
            CET_CFLAGS='-fcf-protection=full'
            CET_LDFLAGS='-Wl,-z,shstk'
            ;;
        aarch64|arm64)
            [[ "$CPU_OPT" == generic ]] || die "CPU_OPT=native is currently supported only on x86_64/amd64"
            ARCH_CFLAGS='-march=armv8-a'
            CET_CFLAGS=''
            CET_LDFLAGS=''
            ;;
        *)
            [[ "$CPU_OPT" == generic ]] || die "CPU_OPT=native is not supported on $arch"
            ARCH_CFLAGS=''
            CET_CFLAGS=''
            CET_LDFLAGS=''
            warn "no architecture-specific tuning selected for $arch"
            ;;
    esac

    log "CPU tuning: $CPU_OPT ($ARCH_CFLAGS)"

    if [[ -n "$CET_LDFLAGS" && "$ENABLE_UPX" =~ ^(1|true|yes)$ ]]; then
        die "UPX is incompatible with CET/IBT; use --no-upx"
    fi

    AUTO_VAR_INIT_CFLAG="-ftrivial-auto-var-init=$AUTO_VAR_INIT"
    log "automatic variable initialization: $AUTO_VAR_INIT_CFLAG"
    HARDENING_CFLAGS="-O2 -pipe $ARCH_CFLAGS -flto -fPIE -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=3 -D_GLIBCXX_ASSERTIONS -fstrict-flex-arrays=3 -fstack-clash-protection -fstack-protector-strong $CET_CFLAGS $AUTO_VAR_INIT_CFLAG -fno-delete-null-pointer-checks -fno-strict-overflow -fasynchronous-unwind-tables -fomit-frame-pointer"
    WARNING_CFLAGS='-Wall -Wextra -Wformat=2 -Wimplicit-fallthrough -Wno-error=implicit-fallthrough -Wno-error=unused-parameter -Werror=format-security -Werror=return-type -Wno-deprecated-declarations'
    DEPENDENCY_CFLAGS="-O2 -pipe $ARCH_CFLAGS -flto -fPIC -fstack-protector-strong $CET_CFLAGS"

    ensure_runtime_user
    prepare_build_directory
    write_build_state
}

phase_resolve_revisions() {
    if [[ "$NGINX_CHANNEL" != pinned ]]; then
        APP_VERSION=$(latest_nginx_version "$NGINX_CHANNEL")
        log "selected $NGINX_CHANNEL NGINX release: $APP_VERSION"
    fi
    [[ -n "$APP_VERSION" ]] || die "APP_VERSION is not set; use .env, --version or a release channel"

    nginx_ref=${NGINX_REF:-release-$APP_VERSION}
    if [[ "$OPENSSL_MODE" == bundled ]]; then
        openssl_ref=${OPENSSL_REF:-openssl-$OPENSSL_VERSION}
    else
        openssl_ref=''
    fi
    pcre_ref=${PCRE_REF:-${PCRE_VERSION:-}}
    zlib_ref=${ZLIB_REF:-${ZLIB_VERSION:-}}
    zstd_ref=${ZSTD_REF:-${ZSTD_VERSION:-}}
    brotli_ref=${BROTLI_REF:-}
    headers_more_ref=${HEADERS_MORE_REF:-}
    cache_purge_ref=${CACHE_PURGE_REF:-}

    if [[ -z "$pcre_ref" ]]; then
        log "resolving latest PCRE2 release"
        pcre_ref=$(latest_release_tag PCRE2Project/pcre2)
    elif [[ "$pcre_ref" != pcre2-* ]]; then
        pcre_ref=pcre2-$pcre_ref
    fi
    if [[ -z "$zlib_ref" ]]; then
        log "resolving latest zlib-ng release"
        zlib_ref=$(latest_release_tag zlib-ng/zlib-ng)
    fi
    if [[ -z "$zstd_ref" ]]; then
        log "resolving latest zstd-nginx-module release"
        zstd_ref=$(latest_release_tag tokers/zstd-nginx-module)
    fi

    log "NGINX ref: $nginx_ref"
    if [[ "$OPENSSL_MODE" == bundled ]]; then
        log "OpenSSL ref: $openssl_ref"
    else
        log "OpenSSL source: system ($(openssl version -v))"
    fi
    log "PCRE2 ref: $pcre_ref"
    log "zlib-ng ref: $zlib_ref"
    log "zstd module ref: $zstd_ref"
    log "third-party modules: zstd, headers-more, cache-purge"
    write_build_state
}

phase_download_sources() {
    clone_repository nginx/nginx "$NGINX_DIR" "$nginx_ref"
    rm -rf -- "$NGINX_DIR/docs/html"/*
    if [[ "$OPENSSL_MODE" == bundled ]]; then
        clone_repository openssl/openssl "$OPENSSL_DIR" "$openssl_ref"
    fi
    clone_repository PCRE2Project/pcre2 "$PCRE_DIR" "$pcre_ref"
    clone_repository zlib-ng/zlib-ng "$ZLIB_DIR" "$zlib_ref"
    clone_repository google/ngx_brotli "$BROTLI_DIR" "$brotli_ref"
    clone_repository tokers/zstd-nginx-module "$ZSTD_DIR" "$zstd_ref"
    clone_repository openresty/headers-more-nginx-module "$HEADERS_MORE_DIR" "$headers_more_ref"
    clone_repository nginx-modules/ngx_cache_purge "$CACHE_PURGE_DIR" "$cache_purge_ref"
}

phase_patch_sources() {
    patch_source "$NGINX_DIR/src/http/ngx_http_header_filter_module.c" \
        'r->headers_out.server == NULL' '0' 'Server header removal'
    patch_source "$NGINX_DIR/src/http/v2/ngx_http_v2_filter_module.c" \
        'r->headers_out.server == NULL' '0' 'HTTP/2 Server header removal'
    patch_source "$NGINX_DIR/src/http/v3/ngx_http_v3_filter_module.c" \
        'r->headers_out.server == NULL' '0' 'HTTP/3 Server header removal'
    patch_source "$NGINX_DIR/src/http/ngx_http_special_response.c" \
        '<hr><center>nginx</center>' '' 'default error page footer removal'
}

phase_prepare_zlib() {
    prepare_zlib
}

phase_build_brotli() {
    build_brotli
}

phase_configure_nginx() {
    configure_nginx
}

phase_build_nginx() {
    build_nginx
}

phase_install_nginx() {
    install_nginx
    compress_binary
    verify_installation
}

main() {
    local arch
    local nginx_ref openssl_ref pcre_ref zlib_ref zstd_ref brotli_ref
    local headers_more_ref cache_purge_ref

    load_env_file

    APP_VERSION=${APP_VERSION:-}
    CPU_OPT=${CPU_OPT:-native}
    AUTO_VAR_INIT=${AUTO_VAR_INIT:-pattern}
    OPENSSL_MODE=${OPENSSL_MODE:-bundled}
    OPENSSL_VERSION=${OPENSSL_VERSION:-}
    PCRE_VERSION=${PCRE_VERSION:-}
    PCRE_REF=${PCRE_REF:-}
    ZLIB_VERSION=${ZLIB_VERSION:-}
    ZLIB_REF=${ZLIB_REF:-}
    ZSTD_VERSION=${ZSTD_VERSION:-}
    ZSTD_REF=${ZSTD_REF:-}
    NGINX_REF=${NGINX_REF:-}
    OPENSSL_REF=${OPENSSL_REF:-}
    BROTLI_REF=${BROTLI_REF:-}
    HEADERS_MORE_REF=${HEADERS_MORE_REF:-}
    CACHE_PURGE_REF=${CACHE_PURGE_REF:-}
    NGINX_CHANNEL=${NGINX_CHANNEL:-pinned}
    INTERACTIVE=${INTERACTIVE:-0}

    PREFIX=${PREFIX:-/usr/share}
    SBIN_PATH=${SBIN_PATH:-/usr/sbin/nginx}
    CONF_PATH=${CONF_PATH:-/etc/nginx/nginx.conf}
    PID_PATH=${PID_PATH:-/run/nginx.pid}
    LOCK_PATH=${LOCK_PATH:-/var/lock/nginx.lock}
    HTTP_LOG_PATH=${HTTP_LOG_PATH:-/var/log/nginx/access.log}
    ERROR_LOG_PATH=${ERROR_LOG_PATH:-/var/log/nginx/error.log}
    CLIENT_TEMP_PATH=${CLIENT_TEMP_PATH:-/var/lib/nginx/body}
    PROXY_TEMP_PATH=${PROXY_TEMP_PATH:-/var/lib/nginx/proxy}
    FASTCGI_TEMP_PATH=${FASTCGI_TEMP_PATH:-/var/lib/nginx/fastcgi}
    LOG_DIR=${LOG_DIR:-/var/log/nginx}
    CACHE_DIR=${CACHE_DIR:-/var/cache/nginx}
    MODULES_PATH=${MODULES_PATH:-/usr/share/nginx/modules}
    RUNTIME_USER=${RUNTIME_USER:-www-data}
    RUNTIME_GROUP=${RUNTIME_GROUP:-www-data}
    CC=${CC:-clang}
    CXX=${CXX:-clang++}
    LD=${LD:-lld}
    AR=${AR:-llvm-ar}
    NM=${NM:-llvm-nm}
    RANLIB=${RANLIB:-llvm-ranlib}
    STRIP=${STRIP:-llvm-strip}
    JOBS=${JOBS:-}
    BUILD_DIR=${BUILD_DIR:-}
    KEEP_BUILD=${KEEP_BUILD:-0}
    SKIP_DEPS=${SKIP_DEPS:-0}
    INSTALL_CONFIG=${INSTALL_CONFIG:-1}
    ENABLE_UPX=${ENABLE_UPX:-auto}
    NGINX_DEBUG=${NGINX_DEBUG:-0}
    BUILD_LOG=${BUILD_LOG:-/tmp/nginx-build.log}

    parse_args "$@"
    BUILD_STATE_FILE="${BUILD_LOG}.state.$$"
    init_build_log "$@"
    select_channel

    case "$OPENSSL_MODE" in
        bundled|system)
            ;;
        *)
            die "OPENSSL_MODE must be bundled or system"
            ;;
    esac
    case "$CPU_OPT" in
        generic|native)
            ;;
        *)
            die "CPU_OPT must be generic or native"
            ;;
    esac
    case "$AUTO_VAR_INIT" in
        zero|pattern|uninitialized)
            ;;
        *)
            die "AUTO_VAR_INIT must be zero, pattern or uninitialized"
            ;;
    esac
    if [[ "$OPENSSL_MODE" == bundled ]]; then
        [[ -n "$OPENSSL_VERSION" ]] || die "OPENSSL_VERSION is not set; define it in .env or the environment, or use --system-openssl"
    fi
    case "$ENABLE_UPX" in
        0|1|auto|false|no|true|yes)
            ;;
        *)
            die "ENABLE_UPX must be auto, 0 or 1"
            ;;
    esac
    [[ "$NGINX_DEBUG" == 0 || "$NGINX_DEBUG" == 1 ]] || die "NGINX_DEBUG must be 0 or 1"

    [[ -r /etc/os-release ]] || die "/etc/os-release is required"
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}" in
        debian|ubuntu)
            ;;
        *)
            die "unsupported distribution: ${PRETTY_NAME:-unknown}; use Debian or Ubuntu"
            ;;
    esac

    if (( EUID == 0 )); then
        SUDO=()
    else
        require_command sudo
        sudo -v || die "sudo authorization is required to install NGINX"
        SUDO=(sudo -n)
    fi

    run_root() {
        "${SUDO[@]}" "$@"
    }

    run_phase "Validating host and installing build dependencies" phase_install_dependencies
    run_phase "Preparing runtime user, compiler flags and build directory" phase_prepare_environment
    load_build_state
    trap cleanup EXIT
    run_phase "Resolving NGINX channel and dependency revisions" phase_resolve_revisions
    load_build_state
    run_phase "Downloading source trees" phase_download_sources
    run_phase "Applying NGINX hardening patches" phase_patch_sources
    run_phase "Preparing zlib-ng compatibility build" phase_prepare_zlib
    run_phase "Building Brotli compression library" phase_build_brotli
    run_phase "Configuring NGINX" phase_configure_nginx
    run_phase "Compiling NGINX" phase_build_nginx
    run_phase "Installing, compressing and validating NGINX" phase_install_nginx
}

main "$@"
