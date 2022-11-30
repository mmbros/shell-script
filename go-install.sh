#!/usr/bin/env bash
#
# install golang in a given folder

#
# Bash settings
#

set -o errexit   # abort on nonzero exitstatus
set -o nounset   # abort on unbound variable
set -o pipefail  # don't hide errors within pipes

# outputs each line of script as it executes it
if [[ "${TRACE-0}" == "1" ]]; then set -o xtrace; fi

#
# Const
#

readonly CMDNAME="${0##*/}"
readonly GO_DEV_HTML_URL="https://go.dev/dl/"
readonly GO_DEV_HTML_FILENAME="godev.html"

#
# Options
#

OPT__GO_VERSION="latest"

OPT__OS_ARCH_KIND="linux-amd64.tar.gz"

OPT__LIB_DIR="/usr/local/lib"

OPT__BIN_DIR="/usr/local/bin"

OPT__SKIP_SYMLINK=false

#
# Variables
#

GO_DEV_HTML_FILEPATH=

GO_FILENAME=
GO_FILEPATH=
GO_DIR=

TMP_DIR=


#
# Functions
#

# print usage informations.
usage() {
    cat <<EOS
USAGE: ${CMDNAME} [options]


OPTIONS:
    -v, --ver, --version <go-version>  
                    go version to install (default "${OPT__GO_VERSION}")     
    -l, --lib <dir>
                    parent folder of the goX.Y.Z folder (default "${OPT__LIB_DIR}")
    -b, --bin <dir>  
                    folder with the symlinks to go binaries (default "${OPT__BIN_DIR}")     
        --no-symlinks, --skip-symlinks
                    skip the creation of the symlinks to go binaries     
    -h, --help      show usage information
    -t, --type <os-arch-kind>
                    type of install (default "${OPT__OS_ARCH_KIND}")

EXAMPLE:
    # install the latest go version
    ${CMDNAME}

    # install the latest go version
    ${CMDNAME} -v latest

    # install the go1.19 version
    ${CMDNAME}  --ver 1.19

    # install the go1.18.7.1 version, skipping the creation of symlinka
    ${CMDNAME}  --version go1.18.7.1 --skip-symlinks
EOS

    # -n, --dry-run   perform a trial run with no request/updates made

}


# print message
log() {
    printf '%s\n' "$@"
}


# print message to stderr and exit 1
die() {
    printf '%s\n' "$@" >&2
    exit 1
}


# download url to destination
download() {
    local url="$1"
    local output="$2"

    log "downloading \"${url}\" to \"${output}\""
    
    [[ -f "${output}" ]] && {
        log "  skip: destination file already exists"
        return
    }

    wget -nc "${url}" "-O" "${output}"
}


move() {
    log "move \"$1\" to \"$2\""
    mv "$1" "$2"
}


create_tmp_dir() {
    TMP_DIR="$(mktemp -d --tmpdir "${CMDNAME}.XXX")"
    mkdir -p "${TMP_DIR}"

    GO_DEV_HTML_FILEPATH="${TMP_DIR}/${GO_DEV_HTML_FILENAME}"
    # log "created temp directory: ${TMP_DIR}"
}


download_godev_page() {
    # download the go.dev html page
    download "${GO_DEV_HTML_URL}" "${GO_DEV_HTML_FILEPATH}"
}


find_go_filename_by_version() {
    local re

    if [[ "${OPT__GO_VERSION}" == "latest" ]]; then
        # get the latest go version from the html page.
        # it is the first filename matching OS, Arch and Kind
        re="go[0-9.]+${OPT__OS_ARCH_KIND//./\\.}"
        GO_FILENAME=$(grep -E -o --max-count=1 "${re}" "${GO_DEV_HTML_FILEPATH}") \
            || die "golang latest version not found for \"${OPT__OS_ARCH_KIND}\""
    else
        re="${OPT__GO_VERSION}.${OPT__OS_ARCH_KIND}"
        GO_FILENAME=$(grep -o --max-count=1 ">${re//./\\.}</a>" "${GO_DEV_HTML_FILEPATH}") \
            || die "golang version not found: ${re}"
        GO_FILENAME="${GO_FILENAME#>}"
        GO_FILENAME="${GO_FILENAME%</a>}"
    fi

    # set the GO filepath
    GO_FILEPATH="${TMP_DIR}/${GO_FILENAME}"

    # set the GO version
    OPT__GO_VERSION="${GO_FILENAME/\.${OPT__OS_ARCH_KIND}/}"
    log "new go version: ${OPT__GO_VERSION}"

    # update GO_DIR
    GO_DIR="${OPT__LIB_DIR}/${OPT__GO_VERSION}"
 
}


download_go_filename() {
    # download golang tar archive
    download "${GO_DEV_HTML_URL}${GO_FILENAME}" "${GO_FILEPATH}"
}


check_sha256() {
    log "checking golang package sha256 signature"
    local sha256

    # get the sha256 checksum of the file
    sha256=$(awk "/${GO_FILENAME//./\\.}.*<\/td>/,/tt/" "${GO_DEV_HTML_FILEPATH}" \
          | tail -n 1 | sed "s/^.*<tt>\(.*\)<\/tt>.*$/\1/")

    echo "file  : ${GO_FILENAME}"
    echo "sha256: ${sha256}"

    if ! echo "${sha256} ${GO_FILEPATH}" | sha256sum -c ; then
        local got
        got=$(sha256sum "${GO_FILEPATH}")
        echo "want  ${sha256}  ${GO_FILENAME}"
        echo " got  ${got}"

        exit 1
    fi
}


extract_go() {
    local arc="$1"
    local dir="$2"
    log "extract golang package '${arc}' to '${dir}'"
    mkdir -p "${dir}"
    tar -C "${dir}" -xzf "${arc}" --strip-components=1 "go"
}


parse_cmdline() {

    # Process all the command line operation
    while :; do
        case ${1:-} in
            # Two hyphens ends the options parsing
            --)
                shift
                break
                ;;
            -h|--help|h|help)
                usage
                exit
                ;;
            # Parse an option value via this syntax: --foo bar
            -v|--ver|--version)
                if [[ -n "${2:-}" ]]; then
                    OPT__GO_VERSION="$2"
                    shift 2
                else
                    die "The command option $1 requires a value"
                fi
                ;;
            # Parse an option value via this syntax: --foo=bar
            --ver=?*|--version=?*)
                OPT__GO_VERSION=${1#*=}
                shift
                ;;                
            -l|--lib)
                if [[ -n "${2:-}" ]]; then
                    OPT__LIB_DIR="$2"
                    shift 2
                else
                    die "The command option $1 requires a value"
                fi
                ;;
            -b|--bin)
                if [[ -n "${2:-}" ]]; then
                    OPT__BIN_DIR="$2"
                    shift 2
                else
                    die "The command option $1 requires a value"
                fi
                ;;
            # Parse an option value via this syntax: --foo=bar
            --lib=?*)
                OPT__LIB_DIR=${1#*=}
                shift
                ;;
            # Parse an option value via this syntax: --foo=bar
            -bin=?*)
                OPT__BIN_DIR=${1#*=}
                shift
                ;;
            # -n|--dry-run)
            #     OPT__DRY_RUN=true
            #     shift
            #     ;;
            --skip-symlinks|--no-symlinks)
                OPT__SKIP_SYMLINK=true
                shift
                ;;
            -t|--type)
                if [[ -n "${2:-}" ]]; then
                    OPT__OS_ARCH_KIND="$2"
                    shift 2
                else
                    die "The command option $1 requires a value"
                fi
                ;;
            --type=?*)
                OPT__OS_ARCH_KIND=${1#*=}
                shift
                ;;
            # Parse an option value via this syntax: --foo= (i.e. blank)
            --type=|--lib=|--bin=|--ver=|--version=)
                die "The command option ${1%*=} requires a value"
                ;; 
            # Anything
            *)
                if (($# == 0)) ; then
                    break
                else
                    die "${CMDNAME}: unknown command '$1'"
                fi
                ;;
        esac
    done

    # prepend "go" if needed
    if [[ "${OPT__GO_VERSION}" != "latest" && "${OPT__GO_VERSION}" != go* ]]; then
        OPT__GO_VERSION="go${OPT__GO_VERSION}"
    fi

    GO_DIR="${OPT__LIB_DIR}/${OPT__GO_VERSION}"

    # log "OPT__GO_VERSION = ${OPT__GO_VERSION}"
    # log "OPT__LIB_DIR = ${OPT__LIB_DIR}"
    # log "OPT__DRY_RUN = ${OPT__DRY_RUN}"
    # log "OPT__OS_ARCH_KIND = ${OPT__OS_ARCH_KIND}"
    # log "OPT__SKIP_SYMLINK = ${OPT__SKIP_SYMLINK}"

}


create_bin_symlink() {
    ${OPT__SKIP_SYMLINK} && return

    local binfile linkpath gocurr


    log "create/update symlinks for golang binaries:"

    # save current go symlink
    gocurr=$(readlink "${OPT__BIN_DIR}"/go) || true

    # ensure bin  dir exists
    mkdir -p "${OPT__BIN_DIR}"

    # create new symlinks
    for binfile in "${GO_DIR}"/bin/*; do
        linkpath="${OPT__BIN_DIR}/${binfile##*/}"
        ln --force --symbolic "${binfile}" "${linkpath}";
        log "  ${linkpath} -> ${binfile}"
    done

    # delete the symlinks that have the same folder of the old go symlink
    if [[ -n "${gocurr}" ]]; then
        gocurr="${gocurr%/*}"
        for linkpath in "${OPT__BIN_DIR}"/*; do
            binfile=$(readlink "${linkpath}") && [[ "${binfile}" == "${gocurr}"/* ]] && rm "${linkpath}"
        done
    fi

}


main() {
    parse_cmdline "$@"

    if [[ ! -d "${GO_DIR}" ]]; then
        create_tmp_dir
        download_godev_page
        find_go_filename_by_version # can change GO_DIR 
    fi

    if [[ ! -d "${GO_DIR}" ]]; then
        download_go_filename
        check_sha256
        extract_go "${GO_FILEPATH}" "${GO_DIR}"
    fi

    create_bin_symlink
}

main "$@"
