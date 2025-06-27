#!/bin/bash

# Script de Instalación de Lightning Terminal (litd)
# Adaptado para macOS Sonoma 15.5 (original probado en Ubuntu 24.04)

set -e  # Salir si ocurre un error

# Variables
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
LIT_CONF_DIR="$USER_HOME/.lit"
LIT_CONF_FILE="$LIT_CONF_DIR/lit.conf"
LND_DIR="$USER_HOME/.lnd"
WALLET_PASSWORD_FILE="$LND_DIR/wallet_password"
LITD_VERSION="v0.14.0-alpha"
KEY_ID="F4FC70F07310028424EFC20A8E4256593F177720"
KEY_SERVER="hkps://keyserver.ubuntu.com"
DOWNLOAD_DIR="/tmp/litd_release_verification"

# Preguntar arquitectura
while true; do
  read -p "¿Está utilizando Apple Silicon (arm) o Intel (x86)? (arm/x86): " ARCH
  if [[ "$ARCH" == "arm" ]]; then
    BIN_ARCH="darwin-arm64"
    break
  elif [[ "$ARCH" == "x86" ]]; then
    BIN_ARCH="darwin-amd64"
    break
  else
    echo "[-] Entrada inválida. Por favor, ingrese 'arm' o 'x86'."
  fi
done

# Construcción de URLs
BINARY_TARBALL="lightning-terminal-${BIN_ARCH}-${LITD_VERSION}.tar.gz"
BINARY_URL="https://github.com/lightninglabs/lightning-terminal/releases/download/$LITD_VERSION/$BINARY_TARBALL"
SIGNATURE_URL="https://github.com/lightninglabs/lightning-terminal/releases/download/$LITD_VERSION/manifest-guggero-$LITD_VERSION.sig"
MANIFEST_URL="https://github.com/lightninglabs/lightning-terminal/releases/download/$LITD_VERSION/manifest-$LITD_VERSION.txt"

# Verificar instalación previa
echo "[+] Verificando si Lightning Terminal ya está instalado..."
if [[ -f "/usr/local/bin/litd" ]]; then
  echo "[+] Lightning Terminal (litd) ya está instalado. Omitiendo la instalación."
  exit 0
fi

# Preparar entorno
echo "[+] Instalando dependencias necesarias con Homebrew..."
brew install gnupg

mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR"

# Importar la clave de Oli
echo "[+] Importando clave PGP del desarrollador..."
gpg --keyserver "$KEY_SERVER" --recv-keys "$KEY_ID" || { echo "[-] No se pudo importar la clave."; exit 1; }

# Descargar artefactos
curl -LO "$BINARY_URL"
curl -LO "$SIGNATURE_URL"
curl -LO "$MANIFEST_URL"

# Verificar firma
echo "[+] Verificando firma PGP..."
gpg --verify "$(basename $SIGNATURE_URL)" "$(basename $MANIFEST_URL)"

# Verificar hash SHA256
echo "[+] Verificando hash SHA256..."
DOWNLOADED_HASH=$(shasum -a 256 "$BINARY_TARBALL" | awk '{print $1}')
grep "$DOWNLOADED_HASH" "$(basename $MANIFEST_URL)" > /dev/null || {
  echo "[-] Verificación de hash SHA256 fallida."; exit 1;
}
echo "[+] Verificación de hash SHA256 exitosa."

# Extraer e instalar binario
echo "[+] Extrayendo binario..."
tar -xvzf "$BINARY_TARBALL" --strip-components=1

echo "[+] Instalando ejecutables en /usr/local/bin..."
sudo install -m 0755 -o root -g wheel ./litd ./loop ./pool ./frcli /usr/local/bin/

# Advertencia sobre systemd (omitido en macOS)
echo "[⚠️] macOS no usa systemd. Deberá iniciar litd manualmente o crear un plist para launchd."
echo "[✅] Lightning Terminal $LITD_VERSION instalado exitosamente."

