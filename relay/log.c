/*
 *  TCI relay.
 */

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>

#include <netinet/tcp.h>

#include "log.h"
#include "util.h"

#if defined(DEBUG)
static bool debug_on = true;
#else
static bool debug_on = false;
#endif

static FILE *log;

void set_debug_on(bool b)
{
	debug_on = b;
}

bool get_debug_on(void)
{
	return debug_on;
}

static void __attribute__((unused)) _vlog(const char *func, int line,
	const char *fmt, va_list ap)
{
	if (!log)
		log = stderr;

	if (func)
		fprintf(log, "%s:%d: ", func, line);

	vfprintf(log, fmt, ap);
	fflush(log);
}

void  __attribute__((unused)) _log(const char *func, int line,
	const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	_vlog(func, line, fmt, ap);
	va_end(ap);
}

void  __attribute__((unused)) log_raw(const char *fmt, ...)
{
	va_list ap;

	va_start(ap, fmt);
	_vlog(NULL, 0, fmt, ap);
	va_end(ap);
}

void  __attribute__((unused)) _debug(const char *func, int line,
	const char *fmt, ...)
{
	va_list ap;

	if (!debug_on)
		return;

	va_start(ap, fmt);
	_vlog(func, line, fmt, ap);
	va_end(ap);
}

void  __attribute__((unused)) debug_raw(const char *fmt, ...)
{
	va_list ap;

	if (!debug_on)
		return;

	va_start(ap, fmt);
	_vlog(NULL, 0, fmt, ap);
	va_end(ap);
}

const char *__attribute__((unused)) tcp_state(unsigned int state)
{
	switch (state) {
	case TCP_ESTABLISHED: return "TCP_ESTABLISHED";
	case TCP_SYN_SENT: return "TCP_SYN_SENT";
	case TCP_SYN_RECV: return "TCP_SYN_RECV";
	case TCP_FIN_WAIT1: return "TCP_FIN_WAIT1";
	case TCP_FIN_WAIT2: return "TCP_FIN_WAIT2";
	case TCP_TIME_WAIT: return "TCP_TIME_WAIT";
	case TCP_CLOSE: return "TCP_CLOSE";
	case TCP_CLOSE_WAIT: return "TCP_CLOSE_WAIT";
	case TCP_LAST_ACK: return "TCP_LAST_ACK";
	case TCP_LISTEN: return "TCP_LISTEN";
	case TCP_CLOSING: return "TCP_CLOSING";
	}
	return "unknown tcp state";
}

