#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

if [ -z "$AUTOBUILD" ] ; then 
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(pwd)"
stage="$(pwd)/stage"

mkdir -p $stage

# Load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

EPOXY_VERSION="1.5.4"
EPOXY_SOURCE_DIR="$top/libepoxy"

VERSION_HEADER_FILE="$EPOXY_SOURCE_DIR/_build_release/src/config.h"

build=${AUTOBUILD_BUILD_ID:=0}

# Create the staging folders
mkdir -p "$stage/lib"/{debug,release,relwithdebinfo}
mkdir -p "$stage/include/epoxy"
mkdir -p "$stage/LICENSES"

pushd "$EPOXY_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        # ------------------------ windows, windows64 ------------------------
        windows*)
            load_vsvars

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                archflags=""
            else
                archflags="/arch:AVX"
            fi

            meson "_build_debug" --prefix="$(cygpath -w ${stage})" --libdir="$(cygpath -w ${stage})/lib/debug" --bindir="$(cygpath -w ${stage})/lib/debug" \
                --buildtype debug --debug

            pushd "_build_debug"
                ninja
                ninja install
            popd

            meson "_build_release" --prefix="$(cygpath -w ${stage})" --libdir="$(cygpath -w ${stage})/lib/release" --bindir="$(cygpath -w ${stage})/lib/release" \
                --buildtype debugoptimized

            pushd "_build_release"
                ninja
                ninja install
            popd
        ;;

        "darwin")
        ;;
        linux*)
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp COPYING "$stage/LICENSES/libepoxy.txt"
popd

# version will be (e.g.) "1.4.0"
version=`sed -n -E 's/#define PACKAGE_VERSION "([0-9])[.]([0-9])[.]([0-9]).*/\1.\2.\3/p' "${VERSION_HEADER_FILE}"`
# shortver will be (e.g.) "230": eliminate all '.' chars
#since the libs do not use micro in their filenames, chop off shortver at minor
short="$(echo $version | cut -d"." -f1-2)"
shortver="${short//.}"

echo "${version}.${build}" > "${stage}/VERSION.txt"
