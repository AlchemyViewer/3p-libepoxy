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
                --buildtype debug -Dtests=false

            pushd "_build_debug"
                ninja
                ninja install
            popd

            meson "_build_release" --prefix="$(cygpath -w ${stage})" --libdir="$(cygpath -w ${stage})/lib/release" --bindir="$(cygpath -w ${stage})/lib/release" \
                --buildtype debugoptimized -Dtests=false

            pushd "_build_release"
                ninja
                ninja install
            popd
        ;;

        darwin*)
            # Setup osx sdk platform
            SDKNAME="macosx10.15"
            export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)
            export MACOSX_DEPLOYMENT_TARGET=10.13

            # Setup build flags
            ARCH_FLAGS="-arch x86_64"
            SDK_FLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} --sysroot=${SDKROOT}"
            DEBUG_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -Og -g -msse4.2 -fPIC -DPIC"
            RELEASE_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -O3 -g -msse4.2 -fPIC -DPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC"
            DEBUG_LDFLAGS="$ARCH_FLAGS -headerpad_max_install_names"
            RELEASE_LDFLAGS="$ARCH_FLAGS -headerpad_max_install_names"

            CFLAGS="$DEBUG_CFLAGS" \
            CXXFLAGS="$DEBUG_CXXFLAGS" \
            CPPFLAGS="$DEBUG_CPPFLAGS" \
            LDFLAGS="$DEBUG_LDFLAGS" \
            meson "_build_debug" --prefix="${stage}" --libdir="${stage}/lib/debug" --bindir="${stage}/lib/debug" \
                -Doptimization=g -Ddebug=true -Dtests=false

            pushd "_build_debug"
                ninja
                ninja install
            popd

            CFLAGS="$RELEASE_CFLAGS" \
            CXXFLAGS="$RELEASE_CXXFLAGS" \
            CPPFLAGS="$RELEASE_CPPFLAGS" \
            LDFLAGS="$RELEASE_LDFLAGS" \
            meson "_build_release" --prefix="${stage}" --libdir="${stage}/lib/release" --bindir="${stage}/lib/release" \
                -Doptimization=3 -Ddebug=true -Db_ndebug=true -Dtests=false

            pushd "_build_release"
                ninja
                ninja install
            popd

            pushd "${stage}/lib/debug"
                fix_dylib_id "libepoxy.dylib"
                dsymutil libepoxy.0.dylib
                strip -x -S libepoxy.0.dylib
            popd

            pushd "${stage}/lib/release"
                fix_dylib_id "libepoxy.dylib"
                dsymutil libepoxy.0.dylib
                strip -x -S libepoxy.0.dylib
            popd

        ;;
        linux*)
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
                    -Doptimization=g -Ddebug=true -Dtests=false

            pushd "_build_debug"
                ninja
                ninja install
            popd


            CFLAGS="$RELEASE_CFLAGS" \
                CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="${CPPFLAGS:-} ${RELEASE_CPPFLAGS}" \
                LDFLAGS="$RELEASE_LDFLAGS" \
                meson "_build_release" --prefix="${stage}" --libdir="${stage}/lib/release" --bindir="${stage}/lib/release" \
                    -Doptimization=3 -Ddebug=true -Db_ndebug=true -Dtests=false

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

echo "${version}" > "${stage}/VERSION.txt"
