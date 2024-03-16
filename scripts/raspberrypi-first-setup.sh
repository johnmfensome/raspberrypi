#!/usr/bin/env bash
#
# Setup basic bash profile config files and install packages
# curl -sSfL https://raw.githubusercontent.com/johnmfensome/raspberrypi/main/scripts/raspberrypi-first-setup.sh | bash

######## VARIABLES #########
tempsetupVarsFile="/tmp/setupVars.conf"

######## PKG Vars ########
PKG_MANAGER="apt-get"
UPDATE_PKG_CACHE="${PKG_MANAGER} update -y"
PKG_INSTALL="${PKG_MANAGER} --yes --no-install-recommends install"
PKG_COUNT="${PKG_MANAGER} -s -o Debug::NoLocking=true upgrade | grep -c ^Inst || true"
CHECK_PKG_INSTALLED='dpkg-query -s'

# Dependencies that are required by the script,
PACKAGE_LIST=(bash-completion certbot curl dnsutils docker fontconfig git gpg grep grepcidr jq coreutils python3 iptables net-tools nfs-common openssl pv sed tar tcpdump telnet tree vim whiptail wireshark)

# Dependencies that where actually installed by the script. For example if the
# script requires grep and dnsutils but dnsutils is already installed, we save
# grep here. This way when uninstalling PiVPN we won't prompt to remove packages
# that may have been installed by the user for other reasons
INSTALLED_PACKAGE_LIST=()

######## SCRIPT ########

# Find the rows and columns. Will default to 80x24 if it can not be detected.
screen_size="$(stty size 2> /dev/null || echo 24 80)"
rows="$(echo "${screen_size}" | awk '{print $1}')"
columns="$(echo "${screen_size}" | awk '{print $2}')"

# Divide by two so the dialogs take up half of the screen, which looks nice.
r=$((rows / 2))
c=$((columns / 2))
# Unless the screen is tiny
r=$((r < 20 ? 20 : r))
c=$((c < 70 ? 70 : c))

# Override localization settings so the output is in English language.
export LC_ALL=C

_main() {
  # Pre install checks and configs
  _distro_check
  _root_check
  _update_cache
  _notify
  _install_packages PACKAGE_LIST[@]
}

####### FUNCTIONS ##########

_error() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

_root_check() {
  ######## FIRST CHECK ########
  # Must be root to install
  echo ":::"

  if [[ "${EUID}" -eq 0 ]]; then
    echo "::: You are root."
  else
    echo "::: sudo will be used for the install."

    # Check if it is actually installed
    # If it isn't, exit because the install cannot complete
    if eval "${CHECK_PKG_INSTALLED} sudo" &> /dev/null; then
      export SUDO="sudo"
      export SUDOE="sudo -E"
    else
      _error "::: Please install sudo or run this as root."
      exit 1
    fi
  fi
}

_install_packages() {
  # Install packages passed via argument array
  # No spinner - conflicts with set -e
  local FAILED=0
  local APTLOGFILE
  declare -a TO_INSTALL=()
  declare -a argArray1=("${!1}")

  for i in "${argArray1[@]}"; do
    echo -n ":::    Checking for ${i}..."

    if [[ "${PKG_MANAGER}" == 'apt-get' ]]; then
      if dpkg-query -W -f='${Status}' "${i}" 2> /dev/null \
        | grep -q "ok installed"; then
        echo " already installed!"
      else
        echo " not installed!"
        # Add this package to the list of packages in the argument array that
        # need to be installed
        TO_INSTALL+=("${i}")
      fi
    elif [[ "${PKG_MANAGER}" == 'apk' ]]; then
      if eval "${SUDO} ${CHECK_PKG_INSTALLED} ${i}" &> /dev/null; then
        echo " already installed!"
      else
        echo " not installed!"
        # Add this package to the list of packages in the argument array that
        # need to be installed
        TO_INSTALL+=("${i}")
      fi
    fi
  done

  APTLOGFILE="$(${SUDO} mktemp)"

  # shellcheck disable=SC2086
  ${SUDO} ${PKG_INSTALL} "${TO_INSTALL[@]}"

  for i in "${TO_INSTALL[@]}"; do
    if [[ "${PKG_MANAGER}" == 'apt-get' ]]; then
      if dpkg-query -W -f='${Status}' "${i}" 2> /dev/null \
        | grep -q "ok installed"; then
        echo ":::    Package ${i} successfully installed!"
        # Add this package to the total list of packages that were actually
        # installed by the script
        INSTALLED_PACKAGE_LIST+=("${i}")
      else
        echo ":::    Failed to install ${i}!"
        ((FAILED++))
      fi
    elif [[ "${PKG_MANAGER}" == 'apk' ]]; then
      if eval "${SUDO} ${CHECK_PKG_INSTALLED} ${i}" &> /dev/null; then
        echo ":::    Package ${i} successfully installed!"
        # Add this package to the total list of packages that were actually
        # installed by the script
        INSTALLED_PACKAGE_LIST+=("${i}")
      else
        echo ":::    Failed to install ${i}!"
        ((FAILED++))
      fi
    elif [[ "${PKG_MANAGER}" == 'apk' ]]; then
      if eval "${SUDO} ${CHECK_PKG_INSTALLED} ${i}" &> /dev/null; then
        echo ":::    Package ${i} successfully installed!"
        # Add this package to the total list of packages that were actually
        # installed by the script
        INSTALLED_PACKAGE_LIST+=("${i}")
      else
        echo ":::    Failed to install ${i}!"
        ((FAILED++))
      fi
    fi
  done

  if [[ "${FAILED}" -gt 0 ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]:" >&2
    ${SUDO} cat "${APTLOGFILE}" >&2
    exit 1
  fi
}

_distro_check() {
  # Check for supported distribution
  if command -v lsb_release > /dev/null; then
    PLAT="$(lsb_release -si)"
    OSCN="$(lsb_release -sc)"
  else # else get info from os-release
    . /etc/os-release
    PLAT="$(awk '{print $1}' <<< "${NAME}")"
    VER="${VERSION_ID}"
    declare -A VER_MAP=(["10"]="buster"
      ["11"]="bullseye"
      ["12"]="bookworm"
      ["18.04"]="bionic"
      ["20.04"]="focal"
      ["22.04"]="jammy"
      ["23.04"]="lunar")
    OSCN="${VER_MAP["${VER}"]}"

    # Alpine support
    if [[ -z "${OSCN}" ]]; then
      OSCN="${VER}"
    fi
  fi

  case "${PLAT}" in
    Debian | Raspbian | Ubuntu)
      case "${OSCN}" in
        stretch | buster | bullseye | bookworm | xenial | bionic | focal | jammy | lunar)
          :
          ;;
        *)
          maybeOSSupport
          ;;
      esac
      ;;
    Alpine)
      PKG_MANAGER='apk'
      UPDATE_PKG_CACHE="${PKG_MANAGER} update"
      PKG_INSTALL="${PKG_MANAGER} --no-cache add"
      PKG_COUNT="${PKG_MANAGER} list -u | wc -l || true"
      CHECK_PKG_INSTALLED="${PKG_MANAGER} --no-cache info -e"
      ;;
    *)
      noOSSupport
      ;;
  esac

  {
    echo "PLAT=${PLAT}"
    echo "OSCN=${OSCN}"
  } > "${tempsetupVarsFile}"
}

_update_cache() {
  # update package lists
  echo ":::"
  echo -e "::: Package Cache update is needed, running ${UPDATE_PKG_CACHE} ..."
  # shellcheck disable=SC2086
  ${SUDO} ${UPDATE_PKG_CACHE} &> /dev/null &
  _spinner "$!"
  echo " done!"
}

_notify() {
  # Let user know if they have outdated packages on their system and
  # advise them to run a package update at soonest possible.
  echo ":::"
  echo -n "::: Checking ${PKG_MANAGER} for upgraded packages...."
  updatesToInstall="$(eval "${PKG_COUNT}")"
  echo " done!"
  echo ":::"

  if [[ "${updatesToInstall}" -eq 0 ]]; then
    echo "::: Your system is up to date! Continuing with PiVPN installation..."
  else
    echo "::: There are ${updatesToInstall} updates available for your system!"
    echo "::: We recommend you update your OS after installing PiVPN! "
    echo ":::"
  fi
}

_spinner() {
  local pid="${1}"
  local delay=0.50
  local spinstr='/-\|'

  while ps a | awk '{print $1}' | grep -q "${pid}"; do
    local temp="${spinstr#?}"
    printf " [%c]  " "${spinstr}"
    local spinstr="${temp}${spinstr%"$temp"}"
    sleep "${delay}"
    printf "\\b\\b\\b\\b\\b\\b"
  done

  printf "    \\b\\b\\b\\b"
}

_main "$@"
