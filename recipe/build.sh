#! /bin/bash

set -e
IFS=$' \t\n' # workaround for conda 4.2.13+toolchain bug

# Adopt a Unix-friendly path if we're on Windows (see bld.bat).
[ -n "$PATH_OVERRIDE" ] && export PATH="$PATH_OVERRIDE"

# On Windows we want $LIBRARY_PREFIX in both "mixed" (C:/Conda/...) and Unix
# (/c/Conda) forms, but Unix form is often "/" which can cause problems.
if [ -n "$LIBRARY_PREFIX_M" ] ; then
    mprefix="$LIBRARY_PREFIX_M"
    if [ "$LIBRARY_PREFIX_U" = / ] ; then
        uprefix=""
    else
        uprefix="$LIBRARY_PREFIX_U"
    fi
else
    mprefix="$PREFIX"
    uprefix="$PREFIX"
fi

# On Windows we need to regenerate the configure scripts.
if [ -n "$VS_MAJOR" ] ; then
    am_version=1.15 # keep sync'ed with meta.yaml
    export ACLOCAL=aclocal-$am_version
    export AUTOMAKE=automake-$am_version
    autoreconf_args=(
        --force
        --install
        -I "$mprefix/share/aclocal"
        -I "$mprefix/mingw-w64/share/aclocal" # note: this is correct for win32 also!
    )
    autoreconf "${autoreconf_args[@]}"
fi

export PKG_CONFIG_LIBDIR=$uprefix/lib/pkgconfig:$uprefix/share/pkgconfig
configure_args=(
    --prefix=$mprefix
    --disable-dependency-tracking
    --disable-selective-werror
    --disable-silent-rules
)

./configure "${configure_args[@]}"
make -j$CPU_COUNT
make install
make check

rm -rf $uprefix/share/man $uprefix/share/doc/${PKG_NAME#xorg-}

xcb_libs="
xcb
xcb-composite
xcb-damage
xcb-dpms
xcb-dri2
xcb-dri3
xcb-glx
xcb-present
xcb-randr
xcb-record
xcb-res
xcb-screensaver
xcb-shape
xcb-shm
xcb-sync
xcb-xf86dri
xcb-xfixes
xcb-xinerama
xcb-xkb
xcb-xtest
xcb-xv
xcb-xvmc
"

# Non-Windows: prefer dynamic libraries to static, and dump libtool helper files
if [ -z "VS_MAJOR" ] ; then
    for lib_ident in $xcb_libs ; do
        rm -f $uprefix/lib/lib${lib_ident}.la $uprefix/lib/lib${lib_ident}.a
    done
fi

if [ "$(uname)" == "Linux" ]; then
    # Build a dummy libxcb-xlib. This library used to exist, but was
    # deprecated.
    # The problem is that on older systems where it still exists
    # (e.g SUSE 11), we may end up mixing the system's libxcb-xlib with the
    # libX11 and libxcb provided by conda.
    # This can cause missing symbols when trying to run a binary which links
    # to libxcb:
    #
    #    /usr/lib64/libxcb-xlib.so.0: undefined symbol: _xcb_unlock_io
    #
    # In this case _xcb_unlock_io is present on /usr/lib64/libxcb.so.1, but
    # there is no such function anymore on the version we built here.
    # Packaging a dummy library solves libxcb-xlib this problem as the only
    # libxcb-xlib user is libX11:
    #
    # https://lists.freedesktop.org/archives/xcb/2009-April/004489.html
    # https://lists.freedesktop.org/archives/xcb/2009-April/004492.html
    #
    # PLEASE NOTE that if you are facing this problem you also need to install
    # conda-forge's libx11, otherwise you will get something like:
    #
    #   /usr/lib64/libX11.so.6: undefined symbol: xcb_xlib_lock
    cd "$PREFIX/lib"
    echo ' ' | $CC --shared -Wl,-soname,libxcb-xlib.so.0 -o libxcb-xlib.so.0.0.0 
    ln -s libxcb-xlib.so.0.0.0 libxcb-xlib.so.0
fi
