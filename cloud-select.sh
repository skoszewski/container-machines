# cloud-select.sh - Combined azurecli-select and gcloud-select for Bash and Zsh

gcloud-select() {
    local root="${GCLOUD_PROFILE_ROOT:-${CLOUD_CLI_PROFILE_DIR:-$HOME/.config}/gcloud.d}"
    local cmd="${1-}"

    _cloud_select_colors

    # Each stream is tested on its own, so nothing escapes into a redirect.
    local reset= bold= dim= cyan= green= ered= ereset=
    if [[ -z "${NO_COLOR-}" ]]; then
        if [[ -t 1 ]]; then
            reset="$_CLOUD_SELECT_RESET" bold="$_CLOUD_SELECT_BOLD"
            dim="$_CLOUD_SELECT_DIM" cyan="$_CLOUD_SELECT_CYAN"
            green="$_CLOUD_SELECT_GREEN"
        fi
        if [[ -t 2 ]]; then
            ereset="$_CLOUD_SELECT_RESET" ered="$_CLOUD_SELECT_RED"
        fi
    fi

    case "$cmd" in
        ''|-h|--help|help)
            printf 'usage: %sgcloud-select%s <command> [<args>]\n\n' "$bold" "$reset"
            printf '  %sselect%s [<profile>]  switch to <profile>; with no argument, reset to\n' "$cyan" "$reset"
            printf '                      the gcloud default (.config/gcloud in %s%s%s or its parent)\n' "$dim" "$root" "$reset"
            printf '  %sshow%s                print the active configuration of the current profile\n' "$cyan" "$reset"
            printf '  %shelp%s                print this message\n\n' "$cyan" "$reset"
            printf 'profiles are subdirectories of %s%s%s\n' "$dim" "$root" "$reset"
            return 0
            ;;
    esac

    shift

    case "$cmd" in
        select)
            if [[ -n "${1-}" ]]; then
                if [[ ! -d "$root/$1" ]]; then
                    mkdir -p "$root/$1" || return 1
                    printf 'Created a new profile directory: %s%s%s\n' "$dim" "$root/$1" "$reset"
                fi

                export CLOUDSDK_CONFIG="$root/$1"
                printf 'Selected gcloud CLI profile: %s%s%s\n' "$green$bold" "$1" "$reset"
            else
                local default= candidate=
                for candidate in "$HOME/.config/gcloud" "$root/gcloud" "$root/../gcloud"; do
                    [[ -d "$candidate" ]] || continue
                    default="$(cd "$candidate" && pwd -P)"
                    break
                done

                if [[ -n "$default" ]]; then
                    export CLOUDSDK_CONFIG="$default"
                    printf 'Selected the default gcloud CLI profile: %s%s%s\n' "$green$bold" "$default" "$reset"
                else
                    unset CLOUDSDK_CONFIG
                fi
            fi
            ;;
        show)
            if [[ -n "${CLOUDSDK_CONFIG-}" ]]; then
                printf "Using profile directory: \"%s%s%s\"\n\n" "$bold" "${CLOUDSDK_CONFIG}" "$reset"
            else
                printf "Profile directory is not set.\n\n"
            fi
            gcloud config list
            ;;
        *)
            printf '%sgcloud-select: unknown command: %s%s\n' "$ered" "$cmd" "$ereset" >&2
            return 1
            ;;
    esac
}

azurecli-select() {
    local root="${AZURECLI_PROFILE_ROOT:-${CLOUD_CLI_PROFILE_DIR:-$HOME/.config}/azure.d}"
    local cmd="${1-}"

    _cloud_select_colors

    # Each stream is tested on its own, so nothing escapes into a redirect.
    local reset= bold= dim= cyan= green= ered= ereset=
    if [[ -z "${NO_COLOR-}" ]]; then
        if [[ -t 1 ]]; then
            reset="$_CLOUD_SELECT_RESET" bold="$_CLOUD_SELECT_BOLD"
            dim="$_CLOUD_SELECT_DIM" cyan="$_CLOUD_SELECT_CYAN"
            green="$_CLOUD_SELECT_GREEN"
        fi
        if [[ -t 2 ]]; then
            ereset="$_CLOUD_SELECT_RESET" ered="$_CLOUD_SELECT_RED"
        fi
    fi

    case "$cmd" in
        ''|-h|--help|help)
            printf 'usage: %sazurecli-select%s <command> [<args>]\n\n' "$bold" "$reset"
            printf '  %sselect%s [<profile>]  switch to <profile>; with no argument, reset to\n' "$cyan" "$reset"
            printf '                      the azure cli default (.azure in %s%s%s or its parent)\n' "$dim" "$root" "$reset"
            printf '  %sshow%s                print the signed-in context of the current profile\n' "$cyan" "$reset"
            printf '  %senv%s                 export AZURE_SUBSCRIPTION_ID and AZURE_TENANT_ID\n' "$cyan" "$reset"
            printf '  %shelp%s                print this message\n\n' "$cyan" "$reset"
            printf 'profiles are subdirectories of %s%s%s\n' "$dim" "$root" "$reset"
            return 0
            ;;
    esac

    shift

    case "$cmd" in
        select)
            if [[ -n "${1-}" ]]; then
                if [[ ! -d "$root/$1" ]]; then
                    mkdir -p "$root/$1" || return 1
                    printf 'Created a new profile directory: %s%s%s\n' "$dim" "$root/$1" "$reset"
                fi

                export AZURE_CONFIG_DIR="$root/$1"
                printf 'Selected Azure CLI profile: %s%s%s\n' "$green$bold" "$1" "$reset"
            else
                local default= candidate=
                for candidate in "$HOME/.azure" "$root/.azure" "$root/../.azure"; do
                    [[ -d "$candidate" ]] || continue
                    default="$(cd "$candidate" && pwd -P)"
                    break
                done

                if [[ -n "$default" ]]; then
                    export AZURE_CONFIG_DIR="$default"
                    printf 'Selected the default Azure CLI profile: %s%s%s\n' "$green$bold" "$default" "$reset"
                else
                    unset AZURE_CONFIG_DIR
                fi
            fi
            ;;
        show)
            if [[ -n "${AZURE_CONFIG_DIR-}" ]]; then
                printf "Using profile directory: \"%s%s%s\"\n\n" "$bold" "${AZURE_CONFIG_DIR}" "$reset"
            else
                printf "Profile directory is not set.\n\n"
            fi
            az account show |
                jq -r --arg c "$cyan" --arg b "$bold" --arg d "$dim" --arg r "$reset" \
                    '@text "\($c)Tenant Id:         \($r)\($b)\(.tenantId)\($r)\n\($c)Subscription Id:   \($r)\($b)\(.id)\($r)\n\($c)Subscription Name: \($r)\($b)\(.name)\($r)\n\n\($c)User Name: \($r)\($b)\(.user.name)\($r) \($d)[\(.user.type)]\($r)"'
            ;;
        env)
            eval "$(az account show | jq -r '@sh "export AZURE_SUBSCRIPTION_ID=\(.id) AZURE_TENANT_ID=\(.tenantId)"')"
            ;;
        *)
            printf '%sazurecli-select: unknown command: %s%s\n' "$ered" "$cmd" "$ereset" >&2
            return 1
            ;;
    esac
}

_cloud_select_colors() {
    [[ -n "${_CLOUD_SELECT_COLORS-}" ]] && return 0
    _CLOUD_SELECT_COLORS=1

    _CLOUD_SELECT_RESET= _CLOUD_SELECT_BOLD= _CLOUD_SELECT_DIM=
    _CLOUD_SELECT_RED= _CLOUD_SELECT_GREEN= _CLOUD_SELECT_CYAN=

    # A terminal without colour, TERM=dumb included, fails this probe.
    command -v tput >/dev/null 2>&1 || return 0
    tput setaf 1 >/dev/null 2>&1 || return 0

    _CLOUD_SELECT_RESET="$(tput sgr0)"
    _CLOUD_SELECT_BOLD="$(tput bold)"
    _CLOUD_SELECT_DIM="$(tput dim)"
    _CLOUD_SELECT_RED="$(tput setaf 1)"
    _CLOUD_SELECT_GREEN="$(tput setaf 2)"
    _CLOUD_SELECT_CYAN="$(tput setaf 6)"
}

_cloud_select_setup() {
    # If GCLOUD_PROFILE_ROOT was set to a default value, allow CLOUD_CLI_PROFILE_DIR to override it on re-source
    if [[ -z "${CLOUD_CLI_PROFILE_DIR-}" ]]; then
        if [[ "${GCLOUD_PROFILE_ROOT-}" == */gcloud.d && "${GCLOUD_PROFILE_ROOT-}" != "$HOME/.config/gcloud.d" ]]; then
            unset GCLOUD_PROFILE_ROOT
        fi
        if [[ "${AZURECLI_PROFILE_ROOT-}" == */azure.d && "${AZURECLI_PROFILE_ROOT-}" != "$HOME/.config/azure.d" ]]; then
            unset AZURECLI_PROFILE_ROOT
        fi
    else
        if [[ -z "${GCLOUD_PROFILE_ROOT-}" || "${GCLOUD_PROFILE_ROOT-}" == "$HOME/.config/gcloud.d" ]]; then
            unset GCLOUD_PROFILE_ROOT
        fi
        if [[ -z "${AZURECLI_PROFILE_ROOT-}" || "${AZURECLI_PROFILE_ROOT-}" == "$HOME/.config/azure.d" ]]; then
            unset AZURECLI_PROFILE_ROOT
        fi
    fi

    # Set default profile roots if not already set
    local profile_dir="${CLOUD_CLI_PROFILE_DIR:-$HOME/.config}"
    GCLOUD_PROFILE_ROOT="${GCLOUD_PROFILE_ROOT:-$profile_dir/gcloud.d}"
    AZURECLI_PROFILE_ROOT="${AZURECLI_PROFILE_ROOT:-$profile_dir/azure.d}"

    if [[ -n "${ZSH_VERSION-}" ]]; then
        # Zsh-specific completions
        eval '
        _gcloud_select() {
            local root="${GCLOUD_PROFILE_ROOT:-${CLOUD_CLI_PROFILE_DIR:-$HOME/.config}/gcloud.d}"
            local -a commands profiles

            commands=(
                '\''select:switch the active profile'\''
                '\''show:print the active configuration'\''
                '\''help:print usage'\''
            )

            if (( CURRENT == 2 )); then
                _describe -t commands '\''gcloud-select command'\'' commands
                return
            fi

            # Only "select" takes an argument, and only one.
            [[ "${words[2]}" == select ]] || return 0
            (( CURRENT == 3 )) || return 0

            profiles=( ${root}/*(/N:t) )

            _describe -t profiles '\''gcloud profile'\'' profiles
        }

        _azurecli_select() {
            local root="${AZURECLI_PROFILE_ROOT:-${CLOUD_CLI_PROFILE_DIR:-$HOME/.config}/azure.d}"
            local -a commands profiles

            commands=(
                '\''select:switch the active profile'\''
                '\''show:print the signed-in context'\''
                '\''env:export the subscription and tenant ids'\''
                '\''help:print usage'\''
            )

            if (( CURRENT == 2 )); then
                _describe -t commands '\''azurecli-select command'\'' commands
                return
            fi

            # Only "select" takes an argument, and only one.
            [[ "${words[2]}" == select ]] || return 0
            (( CURRENT == 3 )) || return 0

            profiles=( ${root}/*(/N:t) )

            _describe -t profiles '\''azure cli profile'\'' profiles
        }

        if (( $+functions[compdef] )); then
            compdef _gcloud_select gcloud-select
            compdef _azurecli_select azurecli-select
        else
            print -u2 '\''cloud-select: compdef not available, run compinit before sourcing this file to get tab completion'\''
        fi
        '
    elif [[ -n "${BASH_VERSION-}" ]]; then
        # Bash-specific completions
        _gcloud_select() {
            local cur="${2-}"
            local root="${GCLOUD_PROFILE_ROOT:-${CLOUD_CLI_PROFILE_DIR:-$HOME/.config}/gcloud.d}"
            local d n
            local -a names=()

            COMPREPLY=()

            if (( COMP_CWORD == 1 )); then
                for n in select show help; do
                    [[ "$n" == "$cur"* ]] && COMPREPLY+=( "$n" )
                done
                return 0
            fi

            # Only "select" takes an argument, and only one.
            [[ "${COMP_WORDS[1]}" == select ]] || return 0
            (( COMP_CWORD > 2 )) && return 0

            for d in "$root"/*/; do
                [[ -d "$d" ]] || continue
                d="${d%/}"
                names+=( "${d##*/}" )
            done

            for n in "${names[@]}"; do
                [[ "$n" == "$cur"* ]] && COMPREPLY+=( "$n" )
            done
        }

        _azurecli_select() {
            local cur="${2-}"
            local root="${AZURECLI_PROFILE_ROOT:-${CLOUD_CLI_PROFILE_DIR:-$HOME/.config}/azure.d}"
            local d n
            local -a names=()

            COMPREPLY=()

            if (( COMP_CWORD == 1 )); then
                for n in select show env help; do
                    [[ "$n" == "$cur"* ]] && COMPREPLY+=( "$n" )
                done
                return 0
            fi

            # Only "select" takes an argument, and only one.
            [[ "${COMP_WORDS[1]}" == select ]] || return 0
            (( COMP_CWORD > 2 )) && return 0

            for d in "$root"/*/; do
                [[ -d "$d" ]] || continue
                d="${d%/}"
                names+=( "${d##*/}" )
            done

            for n in "${names[@]}"; do
                [[ "$n" == "$cur"* ]] && COMPREPLY+=( "$n" )
            done
        }

        complete -F _gcloud_select gcloud-select
        complete -F _azurecli_select azurecli-select
    fi
}
_cloud_select_setup
unset -f _cloud_select_setup
