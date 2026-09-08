#!/bin/bash

set -euo pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

[ -f ./alloy/config.alloy ] || { echo "missing ./alloy/config.alloy"; exit 1; }
[ -f ./alloy/alloy ]        || { echo "missing ./alloy/alloy"; exit 1; }

detect_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        SUDO_CMD=""
    elif command_exists sudo; then
        SUDO_CMD="sudo"
    elif command_exists doas && [ -f /etc/doas.conf ]; then
        SUDO_CMD="doas"
    else
        printf "No sudo/doas found and not running as root"
        exit 1
    fi
}

detect_packager() {
    PACKAGER=""
    for pgm in apt-get dnf yum zypper; do
        if command_exists "$pgm"; then
            PACKAGER="$pgm"
            break
        fi
    done
    if [ -z "$PACKAGER" ]; then
        printf "No supported package manager found (apt-get, dnf, yum, zypper)" >&2
        exit 1
    fi
    printf "Using ${PACKAGER} for package manager."
}

install_alloy() {
    case "$PACKAGER" in
        apt-get)
            ${SUDO_CMD} "${PACKAGER}" install -y gpg wget
            ${SUDO_CMD} mkdir -p /etc/apt/keyrings
            ${SUDO_CMD} wget -qO /etc/apt/keyrings/grafana.asc https://apt.grafana.com/gpg-full.key
            ${SUDO_CMD} chmod 644 /etc/apt/keyrings/grafana.asc
            echo "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main" \
                | ${SUDO_CMD} tee /etc/apt/sources.list.d/grafana.list >/dev/null
            ${SUDO_CMD} "${PACKAGER}" update
            ${SUDO_CMD} "${PACKAGER}" install -y alloy
            ENV_FILE=/etc/default/alloy
            ;;
        dnf | yum)
            wget -qO- https://rpm.grafana.com/gpg.key | ${SUDO_CMD} rpm --import -
            echo -e '[grafana]\nname=grafana\nbaseurl=https://rpm.grafana.com\nrepo_gpgcheck=1\nenabled=1\ngpgcheck=1\ngpgkey=https://rpm.grafana.com/gpg.key\nsslverify=1\nsslcacert=/etc/pki/tls/certs/ca-bundle.crt' \
                | ${SUDO_CMD} tee /etc/yum.repos.d/grafana.repo >/dev/null
            ${SUDO_CMD} "${PACKAGER}" makecache
            ${SUDO_CMD} "${PACKAGER}" install -y alloy
            ENV_FILE=/etc/sysconfig/alloy
            ;;
        zypper)
            wget -qO- https://rpm.grafana.com/gpg.key | ${SUDO_CMD} rpm --import -
            ${SUDO_CMD} "${PACKAGER}" --non-interactive addrepo -f https://rpm.grafana.com grafana
            ${SUDO_CMD} "${PACKAGER}" --non-interactive --gpg-auto-import-keys refresh
            ${SUDO_CMD} "${PACKAGER}" --non-interactive -r grafana install alloy
            ENV_FILE=/etc/sysconfig/alloy
            ;;
    esac
    echo "* Alloy installed."
}

detect_sudo
detect_packager
install_alloy

echo "* Installing config and defaults ..."
${SUDO_CMD} install -m 0644 -o root -g root ./alloy/config.alloy /etc/alloy/config.alloy
${SUDO_CMD} install -m 0644 -o root -g root ./alloy/alloy "${ENV_FILE}"

msg_ok "Enabling and starting Alloy"
${SUDO_CMD} systemctl enable --now alloy
${SUDO_CMD} systemctl restart alloy
${SUDO_CMD} systemctl status alloy --no-pager