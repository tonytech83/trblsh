#!/bin/bash
set -euo pipefail

ENV_FILE=""
SUDO_CMD=""
PACKAGER=""

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO_CMD=""
    elif command_exists sudo; then
        SUDO_CMD="sudo"
    elif command_exists doas && [ -f /etc/doas.conf ]; then
        SUDO_CMD="doas"
    else
        echo "No sudo/doas found and not running as root"
        exit 1
    fi
}

detect_packager() {
    for pgm in apt-get dnf yum zypper; do
        if command_exists "$pgm"; then
            PACKAGER="$pgm"
            break
        fi
    done
    if [ -z "$PACKAGER" ]; then
        echo "No supported package manager found (apt-get, dnf, yum, zypper)" >&2
        exit 1
    fi
    echo "Using ${PACKAGER} for package manager."
}

install_dependencies() {
    case "$PACKAGER" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            ${SUDO_CMD} apt-get update
            ${SUDO_CMD} apt-get install -y gpg curl tar jq
            ;;
        dnf | yum)
            ${SUDO_CMD} "${PACKAGER}" install -y curl tar jq
            ;;
        zypper)
            ${SUDO_CMD} zypper --non-interactive install curl tar jq
            ;;
    esac
    echo "* Dependencies installed."
}

install_alloy() {
    echo "* Installing Alloy ..."

    case "$PACKAGER" in
        apt-get)
            export DEBIAN_FRONTEND=noninteractive
            ${SUDO_CMD} apt-get update
            ${SUDO_CMD} apt-get install -y gpg curl
            ${SUDO_CMD} mkdir -p /etc/apt/keyrings
            curl -fsSL https://apt.grafana.com/gpg-full.key \
                | ${SUDO_CMD} tee /etc/apt/keyrings/grafana.asc >/dev/null
            ${SUDO_CMD} chmod 644 /etc/apt/keyrings/grafana.asc
            echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" \
                | ${SUDO_CMD} tee /etc/apt/sources.list.d/grafana.list >/dev/null
            ${SUDO_CMD} apt-get update
            ${SUDO_CMD} apt-get install -y alloy
            ENV_FILE=/etc/default/alloy
            ;;
        dnf | yum)
            ${SUDO_CMD} "${PACKAGER}" install -y curl
            ${SUDO_CMD} rpm --import https://rpm.grafana.com/gpg.key
            printf '%s\n' \
                '[grafana]' \
                'name=grafana' \
                'baseurl=https://rpm.grafana.com' \
                'repo_gpgcheck=1' \
                'enabled=1' \
                'gpgcheck=1' \
                'gpgkey=https://rpm.grafana.com/gpg.key' \
                'sslverify=1' \
                'sslcacert=/etc/pki/tls/certs/ca-bundle.crt' \
                | ${SUDO_CMD} tee /etc/yum.repos.d/grafana.repo >/dev/null
            ${SUDO_CMD} "${PACKAGER}" makecache
            ${SUDO_CMD} "${PACKAGER}" install -y alloy
            ENV_FILE=/etc/sysconfig/alloy
            ;;
        zypper)
            ${SUDO_CMD} zypper --non-interactive install curl
            ${SUDO_CMD} rpm --import https://rpm.grafana.com/gpg.key
            ${SUDO_CMD} zypper --non-interactive addrepo -f https://rpm.grafana.com grafana
            ${SUDO_CMD} zypper --non-interactive --gpg-auto-import-keys refresh
            ${SUDO_CMD} zypper --non-interactive install -r grafana alloy
            ENV_FILE=/etc/sysconfig/alloy
            ;;
    esac
    echo "* Alloy installed."
}

install_alloy_configs() {
    echo "* Installing config and defaults ..."

    local base="https://raw.githubusercontent.com/tonytech83/trblsh/master/alloy"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' RETURN

    curl -fsSL "${base}/alloy"        -o "${tmp}/alloy"
    curl -fsSL "${base}/config.alloy" -o "${tmp}/config.alloy"

    ${SUDO_CMD} install -D -m 0644 -o root -g root "${tmp}/alloy"        "${ENV_FILE}"
    ${SUDO_CMD} install -D -m 0644 -o root -g root "${tmp}/config.alloy" /etc/alloy/config.alloy
}

install_node_exporter() {
    echo "* Installing Node exporter ..."

    local base="https://raw.githubusercontent.com/tonytech83/trblsh/master/node_exporter"
    local tmp ne_version ne_dir
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' RETURN

    # system user
    if ! id node_exporter >/dev/null 2>&1; then
        ${SUDO_CMD} useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter
    fi

    # latest version
    ne_version=$(curl -fsSL https://api.github.com/repos/prometheus/node_exporter/releases/latest \
        | jq -r '.tag_name | ltrimstr("v")')
    if [ -z "$ne_version" ] || [ "$ne_version" = "null" ]; then
        echo "! Could not determine node_exporter version" >&2
        return 1
    fi

    # binary
    ne_dir="node_exporter-${ne_version}.linux-amd64"
    curl -fsSL "https://github.com/prometheus/node_exporter/releases/download/v${ne_version}/${ne_dir}.tar.gz" \
        -o "${tmp}/${ne_dir}.tar.gz"
    tar -xzf "${tmp}/${ne_dir}.tar.gz" -C "${tmp}"
    ${SUDO_CMD} install -m 0755 "${tmp}/${ne_dir}/node_exporter" /usr/local/bin/node_exporter

    # systemd unit
    curl -fsSL "${base}/node_exporter.service" -o "${tmp}/node_exporter.service"
    ${SUDO_CMD} install -D -m 0644 -o root -g root "${tmp}/node_exporter.service" /etc/systemd/system/node_exporter.service

    ${SUDO_CMD} systemctl daemon-reload
    ${SUDO_CMD} systemctl enable --now node_exporter
    echo "* node_exporter ${ne_version} installed, listening on :9100."
}

detect_sudo
detect_packager
install_dependencies
install_alloy
install_alloy_configs
install_node_exporter

echo "* Validating config ..."
${SUDO_CMD} alloy validate /etc/alloy/config.alloy

echo "* Enabling and starting Alloy"
${SUDO_CMD} systemctl enable --now alloy
${SUDO_CMD} systemctl status alloy --no-pager || true
${SUDO_CMD} systemctl status node_exporter --no-pager || true
