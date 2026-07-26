#!/bin/sh
set -eu

: "${RAD_HOME:=/var/lib/radicle}"
: "${RADICLE_ALIAS:=radicle-seed}"
config_map=/etc/radicle/config.json
profile_config="${RAD_HOME}/config.json"
cmd="${1:-radicle-node}"
shift 2>/dev/null || true

link_config() {
    if [ -f "${config_map}" ]; then
        target="$(readlink "${profile_config}" 2>/dev/null || true)"
        if [ "${target}" != "${config_map}" ]; then
            rm -f "${profile_config}"
            ln -s "${config_map}" "${profile_config}"
        fi
    fi
}

case "${cmd}" in
    radicle-node|node)
        if [ ! -f "${RAD_HOME}/keys/radicle" ]; then
            if [ "${RADICLE_BOOTSTRAP:-}" != "yes" ] || [ -z "${RAD_PASSPHRASE:-}" ]; then
                echo "error: a Radicle identity is missing; set RADICLE_BOOTSTRAP=yes and RAD_PASSPHRASE on an empty volume" >&2
                exit 1
            fi
            umask 077
            rm -f "${profile_config}"
            rad auth --alias "${RADICLE_ALIAS}"
        fi
        link_config
        exec radicle-node --force "$@"
        ;;
    radicle-httpd|httpd)
        link_config
        exec radicle-httpd --listen 0.0.0.0:8080 "$@"
        ;;
    radicle-search|search)
        exec radicle-search "$@"
        ;;
    *)
        exec "${cmd}" "$@"
        ;;
esac
