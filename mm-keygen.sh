#!/usr/bin/env bash
#
# Generate public/private key pair.
#
# see https://cryptsus.com/blog/how-to-secure-your-ssh-server-with-public-key-elliptic-curve-ed25519-crypto.html

# MM_STDLIB="$HOME/Code/prj/scripts/lib/mm-stdlib.sh"

#
# Bash settings
#

set -o errexit   # abort on nonzero exit status
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# outputs each line of script as it executes it
if [[ "${TRACE-0}" == "1" ]]; then set -o xtrace; fi

#
# Const
#
readonly CMDNAME="${0##*/}"
#
# mm_keygen_script_dir=$(dirname "$(readlink -e "${BASH_SOURCE[0]}")" )
# readonly mm_keygen_script_dir

#
# Import
#

# shellcheck source=/dev/null
# source "${MM_STDLIB}"

#
# Functions
#


# Print message to stdout
#
# Usage:
#    log STRING [STRING...]
# Arguments:
#    STRING : message to print
#
log() {
	printf '%s\n' "$@"
}


# Print message to stderr and exit 1
#
# Usage:
#    die STRING [STRING...]
# Arguments:
#    STRING : message to print
#
die() {
	printf '%s: %s\n' "${CMDNAME}" "$@" >&2
	exit 1
}


# confirm [ <message> ]
#
#   Show a prompt message and ask for confirmation.
#   returns a boolean.
# See
#   https://stackoverflow.com/questions/3231804/in-bash-how-to-add-are-you-sure-y-n-to-any-command-or-alias
#
# Arguments:
#   $1 : optional prompt message (default "Are you sure?")
# Parameters:
#   assume_yes
#   assume_no
# Returns:
#   boolean
# Example
#   confirm "" && hg push ssh://..
#   confirm "Would you really like to do a push?" && hg push ssh://..
#
confirm() {
    ${assume_yes:-false} && { true ; return ; };
    ${assume_no:-false} && { false ; return ; };

    local prompt="${1:-"Are you sure? [y/n]: "}"

    read -r -p "${prompt}"
    case "${REPLY,,}" in
        y|yes) true ;;
        *)     false ;;
    esac
}


# Print usage informations.
mm_keygen_usage() {
    cat <<EOS
USAGE: ${CMDNAME} OPTIONS... [ <user> ] [ <host> ]

    Generate public/private key pair.

OPTIONS:
    -m, --mode <key_format>    
                    specify a key format for private key generation 
                      - ssh : OpenSSH format (default)
                      - pem : PEM format
                      - ppk : PuTTY format
    -n, --dry-run   perform a trial run with no request/updates made
    -y, --yes       assume yes to confirm question
    -h, --help      show usage information
EOS
}



# Generate a private/public key pair with ssh-keygen
#
# Arguments:
#   $1 : basename
#   $2 : comment
#   $3 : mode (if pem then PEM format, else OpenSSH format)
mm_keygen_create_key_ssh() {
    local basename="$1"
    local comment="$2"
    local mode="$3"
    
    local cmd="ssh-keygen -o -q -a 256 -t ed25519"
    
    if [ "${mode}" == "pem" ] ; then
        $cmd -m pem -f "${basename}.pem" -C "${comment}"
    else
        $cmd -f "${basename}" -C "${comment}"
    fi
}


# Generate a private/public key pair with puttygen
#
# Arguments:
#   $1 : filename
#   $2 : comment
mm_keygen_create_key_ppk() {
    local filename="$1"
    local comment="$2"

    puttygen -t ed25519 -C "${comment}" -o "${filename}" \
    && puttygen "${filename}" -O public-openssh -o "${filename}.pub"
}


# Generate a private/public key pair
#
# Arguments:
#   $1 : user  : string
#   $2 : host  : string
#   $3 : mode  : string (ssh | pem | ppk)
# Parameters:
#   dry_run    : boolean 
#   assume_yes : boolean
mm_keygen_create_key() {
    local user="$1"
    local host="$2"
    local mode="${3,,}" # to lowercase

    # check mode
    case "${mode}" in
        ssh|pem|ppk)
            ;;
        *)
            err "${CMDNAME}: invalid key mode: ${mode}"
            return 1
            ;;
    esac

    local timestamp 
    timestamp=$(date +%Y-%m-%d)

    local basename="id_ed25519-${user}-${host}-${timestamp//-/}" # remove "-" from timestamp"
    local comment="${user}@${host} (${timestamp})"

    # extension of the private key file 
    local ext=""
    [[ ! "${mode}" = "ssh" ]] && ext=".${mode}"

    # print the description of the operation
    if ${dry_run} ; then
        local dry_run_suffix=" (DRY RUN)"
    fi
    log "Generating public/private ed25519 key pair${dry_run_suffix:=}" \
        "    private key: ${basename}${ext}" \
        "    public  key: ${basename}${ext}.pub"

    # return if dry-run or not confirmed
    ${dry_run} || ! confirm "" && return

    if [[ "${mode}" == "ppk" ]] ; then
        mm_keygen_create_key_ppk "${basename}.ppk" "${comment}"
    else
        mm_keygen_create_key_ssh "${basename}" "${comment}" "${mode}"
    fi
}

# Handle command option and argument.
# See usage for details.
mm_keygen_main() {
    # getopt params
    local shortoptions="hnysm:"
    local longoptions="help,dry-run,yes,assume-yes,mode:"

    local valid_args
    if ! valid_args=$(getopt -o ${shortoptions} --long ${longoptions} -- "$@") ; then
        exit 1;
    fi

    local dry_run=false
    local assume_yes=false
    local mode="SSH"

    eval set -- "${valid_args}"
    while true ; do
        case "$1" in
            -h | --help)
                mm_keygen_usage
                exit 0
                ;;
            -n|--dry-run)
                dry_run=true
                shift
                ;;
            -y|--yes|--assume-yes)
                # 'assume_yes' variable is only referenced indirectly
                # shellcheck disable=SC2034  
                assume_yes=true
                shift
                ;;
            -m|--mode)
                mode="$2"
                shift 2
                ;;
            --) shift; 
                break 
                ;;
        esac
    done

    # handle non-option arguments
    if [[ $# -gt 2 ]]; then
        err "${CMDNAME}: invalid number of arguments: $*"
        exit 1
    fi

    local user="${1:-${USER}}"
    local host="${2:-${HOSTNAME}}"

    mm_keygen_create_key "${user}" "${host}" "${mode}"

}

#
# main
#
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    mm_keygen_main "${@}"
fi
