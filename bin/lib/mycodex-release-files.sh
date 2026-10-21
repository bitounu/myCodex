#!/usr/bin/env bash
# Shared by the updater and embedded verbatim in the bundle bootstrap.
# No removal, cross-filesystem copy fallback, or destination-directory semantics.
MC_RELEASE_FS_MV=""

mc_release_fs_error() { printf 'myCodex: unsafe release filesystem state: %s\n' "$*" >&2; return 1; }

mc_release_fs_directory() {
  local path="$1" create="${2:-0}"
  [[ "${path}" == /* && "${path}" != *$'\n'* && "$(realpath -m -- "${path}")" == "${path}" ]] || {
    mc_release_fs_error "directory contains a symlink or noncanonical component: ${path}"; return 1;
  }
  if [[ "${create}" == 1 ]]; then mkdir -p -- "${path}" || return; fi
  [[ -d "${path}" && ! -L "${path}" && -O "${path}" \
    && "$(realpath -- "${path}")" == "${path}" ]] || {
    mc_release_fs_error "not an owned ordinary directory: ${path}"; return 1;
  }
}

mc_release_fs_file() {
  local path="$1" allow_absent="${2:-0}"
  mc_release_fs_directory "$(dirname -- "${path}")" || return
  [[ ! -L "${path}" && ( ( -f "${path}" && -O "${path}" ) \
    || ( "${allow_absent}" == 1 && ! -e "${path}" ) ) ]] || {
    mc_release_fs_error "not an owned ordinary file: ${path}"; return 1;
  }
}

mc_release_fs_move() {
  local source="$1" target="$2" mode="${3:-replace}"
  if [[ -d "${source}" ]]; then
    mc_release_fs_directory "${source}" || return
  else
    mc_release_fs_file "${source}" || return
  fi
  mc_release_fs_directory "$(dirname -- "${target}")" || return
  if [[ "${mode}" == new ]]; then
    [[ ! -e "${target}" && ! -L "${target}" ]] || {
      mc_release_fs_error "destination is occupied: ${target}"; return 1;
    }
  else
    mc_release_fs_file "${target}" 1 || return
  fi
  if [[ -z "${MC_RELEASE_FS_MV}" ]]; then
    if mv --no-copy --version >/dev/null 2>&1; then MC_RELEASE_FS_MV="mv"
    elif command -v gmv >/dev/null 2>&1 && gmv --no-copy --version >/dev/null 2>&1; then MC_RELEASE_FS_MV="gmv"
    else
      mc_release_fs_error 'GNU mv (or gmv) with --no-copy support is required'; return 1
    fi
  fi
  (
    # Holding the destination directory as cwd prevents a concurrent parent
    # rename/symlink swap from redirecting the replacement into another folder.
    local parent
    parent="$(dirname -- "${target}")"
    cd -P -- "${parent}" || exit
    [[ "$(pwd -P)" == "${parent}" ]] || { mc_release_fs_error 'destination directory changed'; exit 1; }
    if [[ "$(dirname -- "${source}")" == "${parent}" ]]; then source="./${source##*/}"; fi
    target="./${target##*/}"
    if [[ "${mode}" == new ]]; then
      "${MC_RELEASE_FS_MV}" --no-copy -nT -- "${source}" "${target}" || exit
      # GNU mv -n reports success when it skips an occupied destination.
      [[ ! -e "${source}" && ! -L "${source}" ]] || {
        mc_release_fs_error "destination became occupied: ${target}"; exit 1;
      }
    else
      "${MC_RELEASE_FS_MV}" --no-copy -fT -- "${source}" "${target}"
    fi
  )
}
