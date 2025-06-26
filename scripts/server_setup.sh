bash#!/bin/bash
# Script de configuración de servidor para macOS
# Salir en caso de error
set -e

# Verificar privilegios de administrador
if [ "$EUID" -ne 0 ]; then
  echo "Por favor, ejecute como administrador (sudo)."
  exit 1
fi

# Variables
NEW_USER="serveruser"
USER_HOME="/Users/$NEW_USER"
SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
UNIQUE_ID=1001

echo "🚀 Iniciando configuración del servidor macOS..."

# 1. Crear un nuevo usuario con privilegios administrativos
if dscl . -read /Users/$NEW_USER > /dev/null 2>&1; then
  echo "✅ El usuario $NEW_USER ya existe."
else
  echo "👤 Creando usuario $NEW_USER..."
  
  # Crear el usuario
  dscl . -create /Users/$NEW_USER
  dscl . -create /Users/$NEW_USER UserShell /bin/bash
  dscl . -create /Users/$NEW_USER RealName "Server User"
  dscl . -create /Users/$NEW_USER UniqueID $UNIQUE_ID
  dscl . -create /Users/$NEW_USER PrimaryGroupID 20
  dscl . -create /Users/$NEW_USER NFSHomeDirectory $USER_HOME
  
  # Establecer contraseña
  echo "🔐 Estableciendo contraseña para $NEW_USER..."
  dscl . -passwd /Users/$NEW_USER
  
  # Agregar a grupo admin
  dscl . -append /Groups/admin GroupMembership $NEW_USER
  
  # Crear directorio home
  createhomedir -c -u $NEW_USER
  
  echo "✅ Usuario $NEW_USER creado con privilegios administrativos."
fi

# 2. Configurar SSH
echo "🔑 Configurando SSH para $NEW_USER..."

# Crear directorio .ssh si no existe
if [ ! -d "$SSH_DIR" ]; then
  echo "📁 Creando directorio .ssh para $NEW_USER..."
  mkdir -p "$SSH_DIR"
  chmod 700 "$SSH_DIR"
  chown $NEW_USER:staff "$SSH_DIR"
else
  echo "✅ El directorio .ssh para $NEW_USER ya existe."
fi

# Crear archivo authorized_keys si no existe
if [ ! -f "$AUTHORIZED_KEYS" ]; then
  echo "📝 Creando archivo authorized_keys para $NEW_USER..."
  touch "$AUTHORIZED_KEYS"
  chmod 600 "$AUTHORIZED_KEYS"
  chown $NEW_USER:staff "$AUTHORIZED_KEYS"
else
  echo "✅ El archivo authorized_keys para $NEW_USER ya existe."
fi

# Solicitar claves SSH del usuario
echo ""
echo "🔐 Por favor, pegue las claves públicas SSH que desea agregar."
echo "Cada clave debe estar en una nueva línea."
echo "Cuando termine, presione Enter y luego Ctrl+D para continuar."
echo "----------------------------------------"

USER_KEYS=$(cat)

# Agregar claves proporcionadas por el usuario
if [ -n "$USER_KEYS" ]; then
  while IFS= read -r KEY; do
    if [ -n "$KEY" ] && ! grep -qxF "$KEY" "$AUTHORIZED_KEYS"; then
      echo "$KEY" >> "$AUTHORIZED_KEYS"
      echo "✅ Clave agregada a authorized_keys."
    elif [ -n "$KEY" ]; then
      echo "⚠️  La clave ya existe en authorized_keys. Omitiendo."
    fi
  done <<< "$USER_KEYS"
else
  echo "⚠️  No se proporcionaron claves SSH."
fi

# 3. Habilitar acceso remoto SSH
echo "🌐 Habilitando acceso remoto SSH..."
systemsetup -setremotelogin on

# 4. Configurar seguridad SSH
SSHD_CONFIG="/etc/ssh/sshd_config"
echo "🔒 Configurando seguridad SSH..."

# Hacer backup del archivo de configuración
cp "$SSHD_CONFIG" "$SSHD_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"

# Deshabilitar login de root
if grep -q "^#PermitRootLogin" "$SSHD_CONFIG" || ! grep -q "^PermitRootLogin" "$SSHD_CONFIG"; then
  echo "🚫 Deshabilitando el inicio de sesión de root..."
  sed -i '' 's/^#PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
  if ! grep -q "^PermitRootLogin no" "$SSHD_CONFIG"; then
    echo "PermitRootLogin no" >> "$SSHD_CONFIG"
  fi
else
  echo "✅ El inicio de sesión de root ya está configurado."
fi

# Deshabilitar autenticación por contraseña
if grep -q "^#PasswordAuthentication" "$SSHD_CONFIG" || ! grep -q "^PasswordAuthentication no" "$SSHD_CONFIG"; then
  echo "🔐 Deshabilitando la autenticación por contraseña..."
  sed -i '' 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
  sed -i '' 's/^PasswordAuthentication yes/PasswordAuthentication no/' "$SSHD_CONFIG"
  if ! grep -q "^PasswordAuthentication no" "$SSHD_CONFIG"; then
    echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
  fi
else
  echo "✅ La autenticación por contraseña ya está deshabilitada."
fi

# Agregar restricción de usuario (opcional)
if ! grep -q "^AllowUsers" "$SSHD_CONFIG"; then
  echo "👥 Restringiendo acceso SSH solo al usuario $NEW_USER..."
  echo "AllowUsers $NEW_USER" >> "$SSHD_CONFIG"
fi

# 5. Reiniciar el servicio SSH
echo "🔄 Reiniciando el servicio SSH..."
launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
launchctl load /System/Library/LaunchDaemons/ssh.plist

echo ""
echo "🎉 ¡Configuración completada con éxito!"
echo ""
echo "📋 Resumen de la configuración:"
echo "  • Usuario creado: $NEW_USER"
echo "  • SSH habilitado y configurado"
echo "  • Login de root deshabilitado"
echo "  • Autenticación por contraseña deshabilitada"
echo "  • Claves SSH configuradas"
echo ""
echo "🔗 Para conectarte al servidor:"
echo "  ssh $NEW_USER@$(hostname -I | awk '{print $1}' || echo 'TU_IP_DEL_SERVIDOR')"
echo ""

cat <<"EOF"
             .------~---------~-----.
             | .------------------. |
             | |     🍎 macOS     | |
             | |   .'''.  .'''.   | |
             | |   :    ''    :   | |
             | |   :          :   | |
             | |    '.      .'    | |
             | |      '.  .'      | |
             | |        ''        | |  
             | `------------------' |  
             `.____________________.'  
               `-------.  .-------'    
        .--.      ____.'  `.____       
      .-~--~-----~--------------~----. 
      |     .---------.|.--------.|()| 
      |     `---------'|`-o-=----'|  | 
      |-*-*------------| *--  (==)|  | 
      |                |          |  | 
      `------------------------------' 
¡Tu servidor macOS está listo para el próximo paso!
EOF
