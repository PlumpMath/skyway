AC_PREREQ(2.59)
AC_INIT(Skyway Wayland Compositor, 0.0.1, bjames@openmailbox.org)
AM_INIT_AUTOMAKE([color-tests -Wall -Wno-portability foreign])
AM_SILENT_RULES([yes])

AC_CONFIG_FILES([Makefile config.scm])
AC_CONFIG_FILES([pre-inst-env], [chmod +x pre-inst-env])

GUILE_PROGS([2.0.9])

PKG_CHECK_MODULES([WLC], [wlc])
LIBWLC="libwlc"

AC_SUBST([LIBWLC])
AC_OUTPUT
