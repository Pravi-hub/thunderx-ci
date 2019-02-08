/*
 *  TCI relay.
 */

#if defined(HAVE_CONFIG_H)
#include "config.h"
#endif

#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "log.h"
#include "msg.h"
#include "util.h"

void generate_token(char *token)
{
	char *p;
	FILE *fp;
	static const unsigned int len =
		sizeof("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx");

	fp = fopen("/proc/sys/kernel/random/uuid", "r");

	if (!fp) {
		log("fopen failed: %s\n", strerror(errno));
		assert(0);
		exit(EXIT_FAILURE);
	}

	p = fgets(token, len, fp);

	if (p != token) {
		log("fgets failed: %s\n", strerror(errno));
		assert(0);
		exit(EXIT_FAILURE);
	}

	for (p = token; p < token + len; p++) {
		*p = tolower(*p);
	}

	debug("'%s'\n", token);
}

unsigned int to_unsigned(const char *str)
{
	const char *p;
	unsigned long u;

	for (p = str; *p; p++) {
		if (!isdigit(*p)) {
			log("isdigit failed: '%s'\n", str);
			return 0L;
		}
	}

	u = strtoul(str, NULL, 10);

	if (u == ULONG_MAX) {
		log("strtoul '%s' failed: %s\n", str, strerror(errno));
		return 0L;
	}
	
	if (u > UINT_MAX) {
		log("too big: %lu\n", u);
		return UINT_MAX;
	}

	return (unsigned int)u;
}

static const unsigned int mem_magic = 0xa600d1U;

struct mem_header {
	unsigned int magic;
	size_t size;
	bool free_called;
};

void *mem_alloc(size_t size)
{
	void *p;
	struct mem_header *h;

	if (size == 0) {
		log("ERROR: Zero size alloc.\n");
		exit(EXIT_FAILURE);
	}

	h = malloc(sizeof(struct mem_header) + size);

	if (!h) {
		log("ERROR: calloc %lu failed: %s.\n", (unsigned long)size,
			strerror(errno));
		exit(EXIT_FAILURE);
	}

	h->magic = mem_magic;
	h->size = size;
	h->free_called = false;

	p = (void *)h + sizeof(struct mem_header);

	debug("h=%p, p=%p\n", h, p);

	return p;
}

void *mem_alloc_zero(size_t size)
{
	void *p = mem_alloc(size);

	memset(p, 0, size);
	return p;
}

void _mem_free(void *p)
{
	if (!p) {
		log("ERROR: null free.\n");
		assert(0);
		exit(EXIT_FAILURE);
	}

	struct mem_header *h = p - sizeof(struct mem_header);

	debug("h=%p, p=%p\n", h, p);

	if (h->magic != mem_magic) {
		log("ERROR: bad object.\n");
		assert(0);
		exit(EXIT_FAILURE);
	}

	if (h->free_called) {
		log("ERROR: double free.\n");
		assert(0);
		exit(EXIT_FAILURE);
	}

	h->free_called = true;
#if defined (DEBUG_MEM)
	memset(p, 0xcd, h->size);
#else
	free(h);
#endif
}

void __attribute__((unused)) _mem_free_debug(const char *func, int line,
	void *p)
{
	debug("=>%s:%d: %p\n", func, line, p);
	_mem_free(p);
}

int __attribute__ ((format (printf, 2, 3))) client_reply_and_close(
	int client_fd, const char *fmt, ...)
{
	va_list ap;
	int written;
	int expected;
	char reply[msg_buffer_len];

	va_start(ap, fmt);
	expected = vsnprintf(reply, sizeof(reply), fmt, ap);
	va_end(ap);

	reply[msg_buffer_len] = 0;

	if (expected <= 0) {
		log("ERROR: vsnprintf failed: %d, '%s'\n", expected, fmt);
		assert(0);
		strncpy(reply, "ERR:internal", sizeof(reply));
	}

	if (expected >= msg_buffer_len) {
		log("ERROR: Reply too large:\n\n%s\n\n", reply);
		assert(0);
		strncpy(reply, "ERR:internal", sizeof(reply));
	}

	debug("'%s'\n", reply);

	written = write(client_fd, reply, expected);
	close(client_fd);

	if (written != expected) {
		log("ERROR: Write failed: %s\n", strerror(errno));
		return -1;
	}

	return 0;
}
