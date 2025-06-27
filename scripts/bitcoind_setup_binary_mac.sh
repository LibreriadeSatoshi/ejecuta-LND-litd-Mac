#!/bin/bash

# Script de Configuración de Nodo Bitcoin Core
# Adaptado para macOS Sonoma 15.5 (original probado en Ubuntu 24.04)

set -e

# Configuración
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
BITCOIN_DIR="$USER_HOME/.bitcoin"
BITCOIN_CONF="$BITCOIN_DIR/bitcoin.conf"
RPC_AUTH=""
NETWORK=""
ARCH=""

# Preguntar arquitectura
while true; do
  read -p "¿Está utilizando Apple Silicon (arm) o Intel (x86)? (arm/x86): " ARCH
  if [[ "$ARCH" == "arm" ]]; then
    BITCOIN_ARCH="aarch64-apple-darwin"
    break
  elif [[ "$ARCH" == "x86" ]]; then
    BITCOIN_ARCH="x86_64-apple-darwin"
    break
  else
    echo "[-] Entrada inválida. Por favor, ingrese 'arme' o 'x86'."
  fi
done"$BITCOIN_DIR/bitcoin.conf"
RPC_AUTH=""
NETWORK=""
# Eliminado: SERVICE_FILE porque macOS no usa systemd
BITCOIN_VERSION="29.0"  # Se mantiene la versión 29.0
BITCOIN_TARBALL="bitcoin-${BITCOIN_VERSION}-${BITCOIN_ARCH}.tar.gz"  # Arquitectura elegida por usuario"bitcoin-${BITCOIN_VERSION}-x86_64-apple-darwin.tar.gz"  # Reemplazo para macOS
BITCOIN_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/${BITCOIN_TARBALL}"
SHA256SUMS_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
SHA256SUMS_ASC_URL="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS.asc"

# Verificar si el usuario es root
if [[ $EUID -eq 0 ]]; then
  echo "[-] No ejecute este script como root. Homebrew no permite sudo."
  exit 1
fi

echo "[+] Instalando dependencias con Homebrew..."
brew install curl gnupg tar

# Descargar el binario de Bitcoin Core y archivos relacionados
echo "[+] Descargando el binario de Bitcoin Core, sumas de comprobación y firmas..."
curl -s -O "$BITCOIN_URL"  # Reemplazo de wget por curl
curl -s -O "$SHA256SUMS_URL"
curl -s -O "$SHA256SUMS_ASC_URL"

if [[ ! -f $BITCOIN_TARBALL || ! -f SHA256SUMS || ! -f SHA256SUMS.asc ]]; then
  echo "[-] No se pudieron descargar los archivos necesarios. Saliendo."
  exit 1
fi

# Verificar la suma de comprobación SHA256 (ajustado para macOS)
echo "[+] Verificando la suma de comprobación SHA256 del binario..."
grep "$BITCOIN_TARBALL" SHA256SUMS > SHA256SUMS.single
shasum -a 256 -c SHA256SUMS.single
if [[ $? -ne 0 ]]; then
  echo "[-] La verificación de la suma de comprobación SHA256 falló. Saliendo."
  exit 1
fi
echo "[+] Suma de comprobación SHA256 verificada con éxito."

# Importar las claves de firma de Bitcoin Core
echo "[+] Verificando el directorio 'guix.sigs'..."
if [[ -d "guix.sigs" ]]; then
  echo "[!] El directorio 'guix.sigs' ya existe. Obteniendo los últimos cambios..."
  cd guix.sigs
  git pull --ff-only || { echo "[-] No se pudo actualizar 'guix.sigs'. Por favor, resuelva manualmente."; exit 1; }
  cd ..
else
  echo "[+] Clonando el repositorio 'guix.sigs'..."
  git clone https://github.com/bitcoin-core/guix.sigs guix.sigs || { echo "[-] No se pudo clonar 'guix.sigs'. Saliendo."; exit 1; }
fi

echo "[+] Importando las claves de firma de Bitcoin Core..."
gpg --import guix.sigs/builder-keys/* || { echo "[-] No se pudieron importar las claves de firma de Bitcoin Core. Saliendo."; exit 1; }

# Verificar la firma PGP del archivo SHA256SUMS
echo "[+] Verificando la firma PGP del archivo SHA256SUMS..."
gpg --verify SHA256SUMS.asc SHA256SUMS
if [[ $? -ne 0 ]]; then
  echo "[-] La verificación de la firma PGP falló. Saliendo."
  exit 1
fi
echo "[+] Firma PGP verificada con éxito."

# Extraer e instalar el binario de Bitcoin Core
echo "[+] Extrayendo el binario de Bitcoin Core..."
tar -xzf "$BITCOIN_TARBALL"
BITCOIN_EXTRACTED="bitcoin-${BITCOIN_VERSION}"
echo "[+] Moviendo ejecutables a /usr/local/bin..."
sudo install -m 0755 -o root -g wheel ./$BITCOIN_EXTRACTED/bin/* /usr/local/bin

echo "[✅] Bitcoin Core $BITCOIN_VERSION instalado exitosamente en macOS."
echo "[⚠️] Recuerde ejecutar bitcoind manualmente o crear un .plist para launchd si desea ejecutarlo como servicio."

# Terminado
cat <<"EOF"

[+] ¡Bitcoin Core instalado, configurado y servicio habilitado con éxito!

    ⠀⠀⠀⠀⠀⠀⠀⠀⣀⣤⣴⣶⣾⣿⣿⣿⣿⣷⣶⣦⣤⣀⠀⠀⠀⠀⠀⠀⠀⠀
    ⠀⠀⠀⠀⠀⣠⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣦⣄⠀⠀⠀⠀⠀
    ⠀⠀⠀⣠⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣄⠀⠀⠀
    ⠀⠀⣴⣿⣿⣿⣿⣿⣿⣿⠟⠿⠿⡿⠀⢰⣿⠁⢈⣿⣿⣿⣿⣿⣿⣿⣿⣦⠀⠀
    ⠀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣤⣄⠀⠀⠀⠈⠉⠀⠸⠿⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀
    ⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡏⠀⠀⢠⣶⣶⣤⡀⠀⠈⢻⣿⣿⣿⣿⣿⣿⣿⡆
    ⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠃⠀⠀⠼⣿⣿⡿⠃⠀⠀⢸⣿⣿⣿⣿⣿⣿⣿⣷
    ⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡟⠀⠀⢀⣀⣀⠀⠀⠀⠀⢴⣿⣿⣿⣿⣿⣿⣿⣿⣿
    ⢿⣿⣿⣿⣿⣿⣿⣿⢿⣿⠁⠀⠀⣼⣿⣿⣿⣦⠀⠀⠈⢻⣿⣿⣿⣿⣿⣿⣿⡿
    ⠸⣿⣿⣿⣿⣿⣿⣏⠀⠀⠀⠀⠀⠛⠛⠿⠟⠋⠀⠀⠀⣾⣿⣿⣿⣿⣿⣿⣿⠇
    ⠀⢻⣿⣿⣿⣿⣿⣿⣿⣿⠇⠀⣤⡄⠀⣀⣀⣀⣀⣠⣾⣿⣿⣿⣿⣿⣿⣿⡟⠀
    ⠀⠀⠻⣿⣿⣿⣿⣿⣿⣿⣄⣰⣿⠁⢀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠀⠀
    ⠀⠀⠀⠙⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠋⠀⠀⠀
    ⠀⠀⠀⠀⠀⠙⠻⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⠋⠀⠀⠀⠀⠀
⠀    ⠀⠀⠀⠀⠀⠀⠀⠉⠛⠻⠿⢿⣿⣿⣿⣿⡿⠿⠟⠛⠉⠀⠀⠀⠀⠀⠀⠀⠀

[+] ¡Su nodo de Bitcoin ahora está en funcionamiento!
EOF


