## configure.ac -- Process this file with autoconf to produce configure

AC_INIT([tci-relay],
    [m4_esyscmd_s([./version.sh])],
    [https://github.com/glevand/thunderx-ci])

AC_CONFIG_MACRO_DIR([m4])

AC_PREFIX_DEFAULT([/usr/local])

AS_IF([test "x$CFLAGS" = "x"], [AC_SUBST([CFLAGS], [""])])

AC_PROG_CC

AM_INIT_AUTOMAKE
AC_GNU_SOURCE

AM_SILENT_RULES([yes])

default_cflags="--std=gnu99 -g \
	-Wall -W -Wunused -Wstrict-prototypes -Wmissing-prototypes \
	-Wmissing-declarations -Wredundant-decls -Werror"

default_cppflags=""

AC_ARG_ENABLE(
	[debug],
	[AS_HELP_STRING([--enable-debug],
		[build programs with extra debug info [default=no]]
	)],
	[],
	[enable_debug=check]
)

AS_IF(
	[test "x$enable_debug" = "xyes"],
	[
		default_cflags="$default_cflags -O0"
		default_cppflags="$default_cppflags -DDEBUG"
	],
	[
		default_cflags="$default_cflags -O2"
		default_cppflags="$default_cppflags -DNDEBUG"
	]
)

AC_ARG_ENABLE(
	[debug-mem],
	[AS_HELP_STRING([--enable-debug-mem],
		[build programs with memory debugging enabled (caution) [default=no]]
	)],
	[],
	[enable_debug_mem=check]
)

AS_IF(
	[test "x$enable_debug_mem" = "xyes"],
	[default_cppflags="$default_cppflags -DDEBUG_MEM"]
)

AC_ARG_VAR([SITE_CONFIG_FILE],
	[Site configuration file [default="/etc/tci-relay.conf"]]
)
	
AS_IF([test "x$site_config_file" = x],
	[site_config_file="/etc/tci-relay.conf"]
)

AC_DEFINE_UNQUOTED([SITE_CONFIG_FILE], ["$site_config_file"], [Site configuration file.])

AC_SUBST([DEFAULT_CFLAGS], ["$default_cflags"])
AC_SUBST([DEFAULT_CPPFLAGS], ["$default_cppflags"])

AC_SUBST([LIBTOOL_DEPS])
AC_SUBST([DESTDIR])

AC_CONFIG_HEADERS([config.h])
AC_CONFIG_FILES([Makefile])

AC_OUTPUT
