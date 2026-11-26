#!/bin/sh
# Instala (ou reinstala) o Bergastream no Linux, só para o seu usuário, sem
# sudo. Depois disso o próprio app se atualiza (Ajustes → Verificar
# atualizações, ou o aviso ao abrir).
#
#   curl -fsSL https://github.com/Agelinena/bergastream/releases/latest/download/bergastream-install-linux.sh | sh
#
#   sh bergastream-install-linux.sh                     baixa a versão mais nova
#   sh bergastream-install-linux.sh pacote.tar.gz       instala um pacote baixado
#   sh bergastream-install-linux.sh --desinstalar       remove o app (os dados ficam)
#
# Onde fica:
#   ~/.local/share/bergastream                  o app (BERGASTREAM_DIR troca)
#   ~/.local/share/applications/…desktop        atalho no menu
#   ~/.local/bin/bergastream                    para abrir pelo terminal
#   ~/.local/share/com.bergastream.app          banco e músicas baixadas (o app cria)
set -eu

DEST="${BERGASTREAM_DIR:-$HOME/.local/share/bergastream}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_ID=com.bergastream.app
DESKTOP="$DATA_HOME/applications/$APP_ID.desktop"
ICON="$DATA_HOME/icons/hicolor/512x512/apps/$APP_ID.png"
LINK="$HOME/.local/bin/bergastream"
URL=https://github.com/Agelinena/bergastream/releases/latest/download/bergastream-linux-x64.tar.gz

atualizar_menu() {
  update-desktop-database "$DATA_HOME/applications" 2>/dev/null || true
  gtk-update-icon-cache -q "$DATA_HOME/icons/hicolor" 2>/dev/null || true
}

if [ "${1:-}" = "--desinstalar" ]; then
  rm -rf "$DEST" "$DEST.old" "$DESKTOP" "$ICON"
  [ -L "$LINK" ] && rm -f "$LINK"
  atualizar_menu
  echo "Bergastream removido. Banco e músicas baixadas continuam em $DATA_HOME/$APP_ID"
  echo "(apague essa pasta se não for instalar de novo)."
  exit 0
fi

[ "$(uname -m)" = x86_64 ] || { echo "Só há versão para Linux x86_64." >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -n "${1:-}" ]; then
  cp "$1" "$tmp/pacote.tar.gz"
else
  echo "==> Baixando a versão mais nova"
  if command -v curl >/dev/null; then
    curl -fL --progress-bar -o "$tmp/pacote.tar.gz" "$URL"
  else
    wget -q --show-progress -O "$tmp/pacote.tar.gz" "$URL"
  fi
fi

tar -xzf "$tmp/pacote.tar.gz" -C "$tmp"
if [ ! -x "$tmp/bergastream/bergastream" ]; then
  echo "O pacote não tem o app (bergastream/bergastream)." >&2
  exit 1
fi

echo "==> Instalando em $DEST"
mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST.old"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$tmp/bergastream" "$DEST"
rm -rf "$DEST.old"

mkdir -p "$(dirname "$LINK")" "$(dirname "$DESKTOP")" "$(dirname "$ICON")"
ln -sfn "$DEST/bergastream" "$LINK"
[ -f "$DEST/bergastream.png" ] && cp "$DEST/bergastream.png" "$ICON"
cat > "$DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Bergastream
Comment=Sua música, do seu servidor
Exec="$DEST/bergastream"
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Audio;Player;
StartupWMClass=bergastream
EOF
atualizar_menu

# O áudio toca pelo libmpv do sistema.
if ! ldconfig -p 2>/dev/null | grep -q 'libmpv\.so\.[12] '; then
  echo
  echo "Falta o libmpv (sem ele o app não toca). No Debian/Ubuntu:"
  echo "  sudo apt install libmpv2"
fi

echo
echo "Pronto. Abra o Bergastream pelo menu de aplicativos."
