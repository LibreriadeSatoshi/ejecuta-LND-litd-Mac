#!/bin/bash

# Script de Configuración del Nodo Bitcoin Core
# Adaptado para macOS Sonoma 15.5 (original de Ubuntu 24.04)

set -e

# Configuración
USER_HOME=$(eval echo ~${SUDO_USER:-$USER})
BITCOIN_DIR="$USER_HOME/.bitcoin"
BITCOIN_CONF="$BITCOIN_DIR/bitcoin.conf"
RPC_AUTH=""
NETWORK=""
# Eliminado: SERVICE_FILE="/etc/systemd/system/bitcoind.service" ya que macOS no usa systemd

# Verificar si el usuario es root
echo "[+] Verificando privilegios de root..."
if [[ $EUID -ne 0 ]]; then
  echo "[-] Este script debe ser ejecutado como root. Use sudo."
  exit 1
fi

# Instalar dependencias. Reemplazado apt update/upgrade/install por brew install
echo "[+] Instalando dependencias con Homebrew..."
brew install git autoconf automake libtool pkg-config openssl libevent \
             boost zmq python@3

# Clonar el repositorio de Bitcoin Core
echo "[+] Verificando el repositorio de Bitcoin Core..."
if [[ ! -d "$USER_HOME/bitcoin" ]]; then
  echo "[+] Clonando el repositorio de Bitcoin Core usando v29.0 en $USER_HOME..."
  git clone -b v29.0 https://github.com/bitcoin/bitcoin.git "$USER_HOME/bitcoin"
  sudo chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} "$USER_HOME/bitcoin"
else
  echo "[!] El repositorio de Bitcoin ya existe. Omitiendo la clonación."
fi

# Navegar al repositorio
cd "$USER_HOME/bitcoin/"

# Compilar Bitcoin Core desde la fuente
if [[ ! -f "/usr/local/bin/bitcoind" ]]; then
  echo "[+] Compilando Bitcoin Core. Esto puede tardar un rato..."
  ./autogen.sh
  ./configure CXXFLAGS="--param ggc-min-expand=1 --param ggc-min-heapsize=32768" \
              --with-zmq --without-gui --disable-shared --with-pic --disable-tests \
              --disable-bench --enable-upnp-default --disable-wallet \
              CPPFLAGS="-I$(brew --prefix openssl)/include" \
              LDFLAGS="-L$(brew --prefix openssl)/lib"  # Añadido: compatibilidad con OpenSSL de brew
  echo "[+] Esta es la parte tediosa..."
  make -j "$(sysctl -n hw.ncpu)"  # Reemplazado nproc por sysctl -n hw.ncpu en macOS
  echo "[+] ¡Casi terminado!"
  sudo make install
else
  echo "[!] bitcoind ya está instalado. Omitiendo la compilación."
fi

# Volver al directorio de inicio del usuario
cd "$USER_HOME"

# Generar contraseña RPC. Descargar script rpcauth.py con curl que suele venir con macOS
echo "[+] Generando contraseña RPC para que otros servicios se conecten a bitcoind..."
curl -s -o rpcauth.py https://raw.githubusercontent.com/bitcoin/bitcoin/master/share/rpcauth/rpcauth.py
if [[ ! -f rpcauth.py ]]; then
  echo "[-] No se pudo descargar el generador de contraseñas RPC. Saliendo."
  exit 1
fi

# Ejecutar el script de autenticación RPC
RPC_OUTPUT=$(python3 ./rpcauth.py bitcoinrpc)
RPC_AUTH=$(echo "$RPC_OUTPUT" | grep -oE 'rpcauth=\S+')
RPC_PASSWORD=$(echo "$RPC_OUTPUT" | awk '/Your password:/ {getline; print $1}' | tr -d '[:space:]')

# Mostrar la contraseña al usuario
echo "[+] La siguiente contraseña ha sido generada para su conexión RPC:"
echo "    Contraseña: $RPC_PASSWORD"
echo "[!] Por favor, guarde esta contraseña de forma segura, ya que no se mostrará de nuevo."

# Confirmar que el usuario guardó la contraseña
read -p "¿Ha guardado la contraseña? (si/no): " CONFIRM
if [[ $CONFIRM != "si" ]]; then
  echo "[-]  Por favor, guarde la contraseña antes de continuar. Saliendo de la configuración."
  exit 1
fi

# Preguntar al usuario para elegir la red
echo "[+] Seleccione la red para ejecutar bitcoind..."
while true; do
  read -p "¿Desea ejecutar Bitcoin en mainnet o signet? (mainnet/signet): " NETWORK
  if [[ "$NETWORK" == "mainnet" || "$NETWORK" == "signet" ]]; then
    break
  else
    echo "[-] Entrada inválida. Por favor, ingrese 'mainnet' o 'signet'."
  fi
done

# Crear archivo de configuración bitcoin.conf
echo "[+] Creando archivo de configuración bitcoin.conf en $BITCOIN_DIR..."
if [[ -f "$BITCOIN_CONF" ]]; then
  read -p "[!] bitcoin.conf ya existe. ¿Sobrescribir? (si/no): " OVERWRITE
  if [[ "$OVERWRITE" != "si" ]]; then
    echo "[!] Omitiendo la creación de bitcoin.conf..."
  else
    echo "[+] Sobrescribiendo bitcoin.conf..."
  fi
fi

mkdir -p $BITCOIN_DIR
sudo chown -R ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $BITCOIN_DIR
cat <<EOF > $BITCOIN_CONF
# Establezca el mejor hash de bloque aquí­:
# Para v29.0 en Signet, un buen hash para probar es...
# 00000002d38fc984fa25a057930af276c00a001428bd68b8216f826d580a382f
#assumevalid=

# Ejecutar en modo demonio sin un shell interactivo
daemon=1

# Establecer el número de megabytes de RAM a usar, establecer como en el 50% de la memoria disponible
dbcache=3000

# Añadir visibilidad a la mempool y llamadas RPC para la depuración potencial de LND
debug=mempool
debug=rpc

# Desactivar la billetera, no se usará
disablewallet=1

# No se moleste en escuchar a los pares
listen=0

# Limitar la mempool al número de megabytes necesarios:
maxmempool=100

# Limitar la carga a los pares
maxuploadtarget=1000

# Desactivar el servicio de nodos SPV
nopeerbloomfilters=1
peerbloomfilters=0

# No aceptar el estilo multi-firma obsoleto
permitbaremultisig=0

# Establecer la autenticación RPC a lo que se estableció anteriormente
rpcauth=$RPC_AUTH

# Activar el servidor RPC
server=1

# Reducir el tamaño del archivo de registro en los reinicios
shrinkdebuglog=1

# Establecer signet si es necesario
$( [[ "$NETWORK" == "signet" ]] && echo "signet=1" || echo "#signet=1" )

# Podar la cadena de bloques. Ejemplo de poda a 50GB
prune=50000
# Activar el índice de búsqueda de transacciones, si el nodo podado está desactivado.
txindex=0

# Activar la publicación de ZMQ
zmqpubrawblock=tcp://127.0.0.1:28332
zmqpubrawtx=tcp://127.0.0.1:28333
EOF

# Establecer la propiedad del archivo de configuración al usuario
sudo chown ${SUDO_USER:-$USER}:${SUDO_USER:-$USER} $BITCOIN_CONF

# Informar al usuario dónde se encuentra el archivo de configuración
echo "[+] Su archivo bitcoin.conf ha sido creado en: $BITCOIN_CONF"

# En mac no podemos seguir para crear archivo de servicio systemd
#Linux: if [[ ! -f "$SERVICE_FILE" ]]; then
#Linux:  echo "[+] Creando archivo de servicio systemd para bitcoind..."
#Linux:  cat <<EOF > $SERVICE_FILE
#Linux: 
#Linux: [Unit]
#Linux: Description=Demonio de Bitcoin
#Linux: After=network.target
#Linux: 
#Linux: [Service]
#Linux: ExecStart=/usr/local/bin/bitcoind
#Linux: Type=forking
#Linux: Restart=on-failure
#Linux: 
#Linux: User=${SUDO_USER:-$USER}
#Linux: Group=sudo
#Linux: 
#Linux: [Install]
#Linux: WantedBy=multi-user.target
#Linux: EOF
#Linux: else
#Linux:   echo "[!] El archivo de servicio Systemd ya existe. Omitiendo la creacion."
#Linux: fi
#Linux: 
#Linux: # Habilitar, recargar e iniciar el servicio systemd
#Linux: systemctl enable bitcoind
#Linux: systemctl daemon-reload
#Linux: if ! systemctl is-active --quiet bitcoind; then
#Linux:   systemctl start bitcoind
#Linux:   echo "[+] El servicio bitcoind se inició."
#Linux: else
#Linux:   echo "[!] El servicio bitcoind ya se está ejecutando."
#Linux: fi

# Terminado
cat <<"EOF"

[+] ¡Bitcoin Core compilado, instalado, configurado y servicio habilitado con éxito!

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





