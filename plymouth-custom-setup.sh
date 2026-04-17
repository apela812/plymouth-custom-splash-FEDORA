#!/usr/bin/env bash
set -Eeuo pipefail

# Interactive Plymouth setup helper for Fedora
# RU/EN bilingual prompts

DEFAULT_THEME_NAME="mytheme"
DEFAULT_KERNEL_ARGS=("plymouth.use-simpledrm")
THEME_NAME="$DEFAULT_THEME_NAME"
IMAGE_PATH=""
DISABLE_BGRT="yes"
AUTO_INSTALL_DEPS="yes"
ASK_REBOOT="yes"
THEME_DIR=""

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_BLUE='\033[34m'

say() {
  printf "%b%s%b\n" "$C_BLUE" "$1" "$C_RESET"
}

ok() {
  printf "%b[OK]%b %s\n" "$C_GREEN" "$C_RESET" "$1"
}

warn() {
  printf "%b[! ]%b %s\n" "$C_YELLOW" "$C_RESET" "$1"
}

err() {
  printf "%b[ERR]%b %s\n" "$C_RED" "$C_RESET" "$1" >&2
}

pause() {
  read -r -p "Нажми Enter / Press Enter... " _ || true
}

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

ask_yes_no() {
  local prompt="$1"
  local default="$2"
  local ans
  local suffix="[Y/n]"
  [[ "$default" == "no" ]] && suffix="[y/N]"
  while true; do
    read -r -p "$prompt $suffix: " ans || true
    ans="$(trim "$ans")"
    if [[ -z "$ans" ]]; then
      [[ "$default" == "yes" ]] && return 0 || return 1
    fi
    case "${ans,,}" in
      y|yes|д|да) return 0 ;;
      n|no|н|нет) return 1 ;;
      *) warn "Введите yes/y/да/д или no/n/нет/н / Enter yes/y or no/n" ;;
    esac
  done
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    err "Запусти через sudo / Please run with sudo"
    exit 1
  fi
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    err "Не найдена команда / Command not found: $cmd"
    exit 1
  }
}

pkg_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

install_deps() {
  local pkgs=(plymouth plymouth-system-theme plymouth-plugin-script dracut grub2-tools)
  local missing=()
  local p
  for p in "${pkgs[@]}"; do
    pkg_installed "$p" || missing+=("$p")
  done

  if (( ${#missing[@]} == 0 )); then
    ok "Зависимости уже установлены / Dependencies already installed"
    return 0
  fi

  warn "Не хватает пакетов / Missing packages: ${missing[*]}"
  if [[ "$AUTO_INSTALL_DEPS" == "yes" ]] || ask_yes_no "Установить их сейчас? / Install them now?" yes; then
    dnf install -y "${missing[@]}"
    ok "Пакеты установлены / Packages installed"
  else
    err "Без этих пакетов скрипт не сможет работать / The script cannot continue without these packages"
    exit 1
  fi
}

show_header() {
  clear || true
  printf "%bPlymouth Custom Setup / Настройка кастомной заставки%b\n" "$C_BOLD" "$C_RESET"
  printf "============================================================\n"
  printf "Тема / Theme        : %s\n" "$THEME_NAME"
  printf "Картинка / Image    : %s\n" "${IMAGE_PATH:-<не выбрана / not selected>}"
  printf "Папка темы / Dir    : %s\n" "${THEME_DIR:-<будет создана / will be created>}"
  printf "Скрыть BGRT / Hide vendor logo : %s\n" "$DISABLE_BGRT"
  printf "Авто-установка пакетов / Auto install deps : %s\n" "$AUTO_INSTALL_DEPS"
  printf "Перезапрос ребута / Ask for reboot : %s\n" "$ASK_REBOOT"
  printf "============================================================\n"
}

pick_image() {
  local input
  while true; do
    read -r -p "Введи путь к PNG-файлу / Enter path to PNG file: " input || true
    input="$(trim "$input")"
    [[ -z "$input" ]] && { warn "Путь пустой / Empty path"; continue; }

    # Expand ~ manually for sudo contexts
    if [[ "$input" == ~* ]]; then
      eval "input=$input"
    fi

    if [[ ! -f "$input" ]]; then
      warn "Файл не найден / File not found: $input"
      continue
    fi
    if [[ ! "$input" =~ \.png$|\.PNG$ ]]; then
      warn "Нужен PNG-файл / PNG file required"
      continue
    fi

    IMAGE_PATH="$(realpath "$input")"
    ok "Выбрана картинка / Image selected: $IMAGE_PATH"
    return 0
  done
}

configure_theme_name() {
  local input
  read -r -p "Имя темы / Theme name [$THEME_NAME]: " input || true
  input="$(trim "$input")"
  if [[ -n "$input" ]]; then
    input="${input// /_}"
    THEME_NAME="$input"
  fi
  THEME_DIR="/usr/share/plymouth/themes/${THEME_NAME}"
  ok "Имя темы / Theme name: $THEME_NAME"
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -a "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)"
}

ensure_kernel_arg() {
  local cfg="$1"
  local arg="$2"

  if grep -qE '^GRUB_CMDLINE_LINUX=' "$cfg"; then
    if ! grep -Eq "^GRUB_CMDLINE_LINUX=.*(^|[[:space:]])${arg}([[:space:]"]|$)" "$cfg"; then
      sed -i -E "s|^(GRUB_CMDLINE_LINUX=\")(.*)(\")$|\1\2 ${arg}\3|" "$cfg"
      ok "Добавлен параметр / Added kernel arg: $arg"
    else
      ok "Параметр уже есть / Kernel arg already present: $arg"
    fi
  else
    printf 'GRUB_CMDLINE_LINUX="%s"\n' "$arg" >> "$cfg"
    ok "Создан GRUB_CMDLINE_LINUX с параметром / Created GRUB_CMDLINE_LINUX with: $arg"
  fi
}

update_grub() {
  local grub_cfg="/boot/grub2/grub.cfg"
  if [[ ! -f /etc/default/grub ]]; then
    err "/etc/default/grub не найден / not found"
    return 1
  fi

  backup_file /etc/default/grub

  if [[ "$DISABLE_BGRT" == "yes" ]]; then
    local arg
    for arg in "${DEFAULT_KERNEL_ARGS[@]}"; do
      ensure_kernel_arg /etc/default/grub "$arg"
    done
  fi

  if [[ -f "$grub_cfg" ]]; then
    grub2-mkconfig -o "$grub_cfg"
    ok "GRUB обновлён / GRUB updated: $grub_cfg"
  else
    warn "Не найден $grub_cfg. Пропускаю / Not found, skipping: $grub_cfg"
  fi
}

create_theme_files() {
  THEME_DIR="/usr/share/plymouth/themes/${THEME_NAME}"
  mkdir -p "$THEME_DIR"

  install -m 0644 "$IMAGE_PATH" "$THEME_DIR/mylogo.png"

  cat > "$THEME_DIR/${THEME_NAME}.plymouth" <<EOF2
[Plymouth Theme]
Name=${THEME_NAME}
Description=Custom splash with centered image
ModuleName=script

[script]
ImageDir=${THEME_DIR}
ScriptFile=${THEME_DIR}/${THEME_NAME}.script
EOF2

  cat > "$THEME_DIR/${THEME_NAME}.script" <<'EOF2'
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

image = Image("mylogo.png");
image_width = image.GetWidth();
image_height = image.GetHeight();

x = (screen_width - image_width) / 2;
y = (screen_height - image_height) / 2;

sprite = Sprite(image);
sprite.SetPosition(x, y, 0);
EOF2

  chmod 0644 "$THEME_DIR/${THEME_NAME}.plymouth" "$THEME_DIR/${THEME_NAME}.script" "$THEME_DIR/mylogo.png"
  ok "Файлы темы созданы / Theme files created in: $THEME_DIR"
}

apply_theme() {
  plymouth-set-default-theme "$THEME_NAME"
  ok "Тема активирована / Theme activated: $THEME_NAME"
}

rebuild_initramfs() {
  dracut -f
  ok "initramfs пересобран / initramfs rebuilt"
}

offer_reboot() {
  if [[ "$ASK_REBOOT" != "yes" ]]; then
    warn "Перезагрузка отключена в настройках / Reboot prompt disabled"
    return 0
  fi

  if ask_yes_no "Перезагрузить сейчас? / Reboot now?" no; then
    if systemctl reboot 2>/dev/null; then
      exit 0
    else
      warn "Обычная перезагрузка заблокирована. Пробую с -i / Normal reboot blocked, trying with -i"
      systemctl reboot -i || warn "Не удалось перезагрузить автоматически / Could not reboot automatically"
    fi
  fi
}

show_manual_help() {
  printf "\n%bГотово / Done%b\n" "$C_BOLD" "$C_RESET"
  printf "Следующие полезные команды / Useful commands:\n"
  printf "  plymouth-set-default-theme -l\n"
  printf "  sudo plymouth-set-default-theme %s\n" "$THEME_NAME"
  printf "  sudo dracut -f\n"
  printf "  cat /proc/cmdline\n"
  printf "\nЧтобы заменить картинку позже / To replace image later:\n"
  printf "  1) Запусти этот скрипт снова / Run this script again\n"
  printf "  2) Выбери новый PNG / Select a new PNG\n"
  printf "\nКуда кладётся файл / Where the file is copied:\n"
  printf "  %s/mylogo.png\n" "$THEME_DIR"
}

quick_apply() {
  require_root
  require_cmd rpm
  require_cmd dnf
  require_cmd dracut
  require_cmd grub2-mkconfig
  require_cmd plymouth-set-default-theme

  install_deps
  create_theme_files
  apply_theme
  update_grub
  rebuild_initramfs
  show_manual_help
  offer_reboot
}

menu() {
  while true; do
    show_header
    cat <<'EOF2'
1) Выбрать картинку / Choose image
2) Изменить имя темы / Change theme name
3) Вкл/выкл скрытие логотипа производителя / Toggle hide vendor logo
4) Вкл/выкл авто-установку пакетов / Toggle auto install deps
5) Вкл/выкл вопрос о перезагрузке / Toggle reboot prompt
6) Запустить настройку / Run setup
7) Выход / Exit
EOF2
    printf "------------------------------------------------------------\n"
    read -r -p "Выбор / Choice: " choice || true
    case "$(trim "$choice")" in
      1) pick_image; pause ;;
      2) configure_theme_name; pause ;;
      3)
        [[ "$DISABLE_BGRT" == "yes" ]] && DISABLE_BGRT="no" || DISABLE_BGRT="yes"
        ok "Скрытие логотипа / Hide vendor logo: $DISABLE_BGRT"
        pause
        ;;
      4)
        [[ "$AUTO_INSTALL_DEPS" == "yes" ]] && AUTO_INSTALL_DEPS="no" || AUTO_INSTALL_DEPS="yes"
        ok "Авто-установка / Auto install deps: $AUTO_INSTALL_DEPS"
        pause
        ;;
      5)
        [[ "$ASK_REBOOT" == "yes" ]] && ASK_REBOOT="no" || ASK_REBOOT="yes"
        ok "Вопрос о перезагрузке / Reboot prompt: $ASK_REBOOT"
        pause
        ;;
      6)
        [[ -z "$IMAGE_PATH" ]] && pick_image
        configure_theme_name
        quick_apply
        exit 0
        ;;
      7) exit 0 ;;
      *) warn "Неверный пункт / Invalid option"; pause ;;
    esac
  done
}

main() {
  menu
}

main "$@"
