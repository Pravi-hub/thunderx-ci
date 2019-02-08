/*
 *  TCI relay.
 */

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

//#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>

#include "checkout.h"
#include "log.h"
#include "timer.h"
#include "util.h"

struct co_manager {
	unsigned int counter;
	unsigned int max_count;
	struct list list;
};

static struct co_manager co_manager;

void checkout_init(unsigned int co_max_count)
{
	co_manager.max_count = co_max_count;
	list_init(&co_manager.list);
}

static bool co_full(void)
{
	if (co_manager.counter >= co_manager.max_count) {
		debug("full\n");
		return true;
	}
	return false;
}

void _co_print(const char *func, int line, const struct co_msg *msg)
{
	debug_raw("%s:%d: co msg:\n", func, line);
	debug_raw("  resource:      '%s'\n", msg->resource);
	debug_raw("  token:         '%s'\n", msg->token);
	debug_raw("  client_fd: %d\n", msg->client_fd);
	debug_raw("  timer_seconds: %u\n", msg->timer_seconds);
}

size_t __attribute__((unused)) co_dump_list(const char *text, char *str,
	size_t str_len)
{
	int i;
	size_t count = 0;
	struct co_msg *entry;

	debug_raw("%s (count=%u) %s\n", __func__, co_manager.counter, text);
	if (str && count < str_len) {
		count += snprintf(str + count, str_len - count,
			"%s (count=%u) %s\n", __func__, co_manager.counter,
			text);
	}

	i = 0;
	list_for_each(&co_manager.list, entry, list_entry) {
		debug_raw("  [%d] %p resource='%s', token='%s', sec=%u\n",
			i, entry, entry->resource, entry->token,
			entry->timer_seconds);
		if (str && count < str_len) {
			count += snprintf(str + count, str_len - count,
				"  [%d] %p resource='%s', token='%s', sec=%u\n",
			i, entry, entry->resource, entry->token,
			entry->timer_seconds);
		}
		i++;
	}
	return count;
}

static int co_add_waiting(int client_fd, const char *resource,
	unsigned int request_seconds)
{
	struct co_msg *msg;

	debug("'%s'\n", resource);

	msg = mem_alloc_zero(sizeof(*msg));

	build_assert(sizeof(msg->resource) >= sizeof(resource));

	strncpy(msg->resource, resource, sizeof(msg->resource));
	msg->timer_seconds = request_seconds;
	msg->client_fd = client_fd;

	list_add_tail(&co_manager.list, &msg->list_entry);
	co_manager.counter++;

	return 0;
}

static void co_timer_callback(void *data)
{
	struct co_msg *next;
	struct co_msg saved;

	assert(data);

	saved = *(struct co_msg *)data;

	debug("%p '%s'\n", data, saved.resource);
	log("Warning: Resource reservation expired: '%s', %us, %s.\n",
		saved.resource, saved.timer_seconds, saved.token);

	co_remove(data);
	next = co_find_by_resource(saved.resource);
	
	if(!next) {
		debug("resource now free: '%s'\n", saved.resource);
		return;
	}

	assert(next->timer_seconds);

	generate_token(next->token);

	next->timer = timer_add(next->timer_seconds, co_timer_callback,
		next);

	client_reply_and_close(next->client_fd, "OK-:%s", next->token);
	next->client_fd = 0;
}

static void co_add_reserved(int client_fd, const char *resource,
	unsigned int request_seconds)
{
	struct co_msg *msg;

	debug("'%s'\n", resource);

	msg = mem_alloc_zero(sizeof(*msg));

	build_assert(sizeof(msg->resource) >= sizeof(resource));

	strncpy(msg->resource, resource, sizeof(msg->resource));
	msg->client_fd = 0;
	msg->timer_seconds = request_seconds;

	list_add_tail(&co_manager.list, &msg->list_entry);
	co_manager.counter++;

	generate_token(msg->token);

	msg->timer = timer_add(request_seconds, co_timer_callback, msg);

	client_reply_and_close(client_fd, "OK-:%s", msg->token);
}

int co_add(int client_fd, const char *resource, unsigned int request_seconds)
{
	struct co_msg *existing;

	debug("[%d] '%s'\n", co_manager.counter, resource);

	if (co_full()) {
		co_clean_waiters();
		if (co_full()) {
			log("buffer full: '%s'\n", resource);
		}
	}

	existing = co_find_by_resource(resource);

	if (existing) {
		co_add_waiting(client_fd, resource, request_seconds);
	} else {
		co_add_reserved(client_fd, resource, request_seconds);
	}
	return 0;
}

void co_remove(struct co_msg *msg)
{
	assert(msg);

	debug("%p resource='%s', token='%s', sec=%u\n",
		msg, msg->resource, msg->token, msg->timer_seconds);

	list_remove(&msg->list_entry);
	co_manager.counter--;
	if (msg->timer) {
		timer_remove(msg->timer);
	}
	mem_free(msg);
}

struct co_msg *co_find_by_resource(const char *resource)
{
	struct co_msg *entry;

	list_for_each(&co_manager.list, entry, list_entry) {
		//debug("test '%s'\n", entry->resource);
		if (!strcmp(entry->resource, resource)) {
			debug("found %p '%s'\n", entry, entry->resource);
			return entry;
		}
	}
	debug("not found: '%s'\n", resource);
	return NULL;
}

struct co_msg *co_find_by_token(const char *token)
{
	struct co_msg *entry;

	list_for_each(&co_manager.list, entry, list_entry) {
		//debug("test '%s'\n", entry->token);
		if (!strcmp(entry->token, token)) {
			debug("found %p '%s'\n", entry, entry->token);
			return entry;
		}
	}
	debug("not found: '%s'\n", token);
	return NULL;
}

void co_clean_waiters(void)
{
	struct co_msg *entry;
	struct co_msg *tmp;

	list_for_each_safe(&co_manager.list, entry, tmp, list_entry) {
		int result;
		socklen_t len;
		struct tcp_info info;

		debug("fd=%d, token='%s'\n", entry->client_fd, entry->token);

		if (!entry->client_fd) {
			assert(entry->token[0]);
			continue;
		}

		assert(!entry->token[0]);

		len = sizeof(info);;
		result = getsockopt(entry->client_fd, SOL_TCP, TCP_INFO, &info, &len);

		if (result) {
			log("getsockopt failed: %s\n", strerror(errno));
		}

		debug("fd=%d, state=(%u)%s\n", entry->client_fd,
			(unsigned int)info.tcpi_state,
			tcp_state(info.tcpi_state));

		if (result || info.tcpi_state != TCP_ESTABLISHED) {
			close(entry->client_fd);
			entry->client_fd = -1;
			co_remove(entry);
		}
	}
}
