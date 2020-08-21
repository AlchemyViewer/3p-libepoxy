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
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Default target per autobuild build --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
			DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC -DPIC"
			RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -DPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
			DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
			RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
			RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
			RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="$opts"
            RELEASE_LDFLAGS="$opts"

            # Handle any deliberate platform targeting
            if [ -z "${TARGET_CPPFLAGS:-}" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            CFLAGS="$DEBUG_CFLAGS" \
                CXXFLAGS="$DEBUG_CXXFLAGS" \
                CPPFLAGS="${CPPFLAGS:-} ${DEBUG_CPPFLAGS}" \
                LDFLAGS="$DEBUG_LDFLAGS" \
                meson "_build_debug" --prefix="${stage}" --libdir="${stage}/lib/debug" --bindir="${stage}/lib/debug" \
                --optimization g --debug

            pushd "_build_debug"
                ninja
                ninja install
            popd


            CFLAGS="$RELEASE_CFLAGS" \
                CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="${CPPFLAGS:-} ${RELEASE_CPPFLAGS}" \
                LDFLAGS="$RELEASE_LDFLAGS" \
                meson "_build_release" --prefix="${stage}" --libdir="${stage}/lib/release" --bindir="${stage}/lib/release" \
                --optimization 3 --debug -Db_lto=true

            pushd "_build_release"
                ninja
                ninja install
            popd
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
