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

#include "relay.h"
#include "log.h"
#include "util.h"

struct get_manager {
	unsigned int counter;
	unsigned int max_count;
	struct list list;
};

struct put_manager {
	unsigned int counter;
	unsigned int max_count;
	struct list list;
};

static struct get_manager get_manager;
static struct put_manager put_manager;

void relay_init(unsigned int get_max_count, unsigned int put_max_count)
{
	list_init(&get_manager.list);
	get_manager.max_count = get_max_count;

	list_init(&put_manager.list);
	put_manager.max_count = put_max_count;
}

//==============================================================================

static bool get_full(void)
{
	if (get_manager.counter >= get_manager.max_count) {
		debug("full\n");
		return true;
	}
	return false;
}

void _get_print(const char *func, int line, const struct get_msg *msg)
{
	debug_raw("%s:%d: get msg:\n", func, line);
	debug_raw("  token:     '%s'\n", msg->token);
	debug_raw("  client_fd: %d\n", msg->client_fd);
}

size_t __attribute__((unused)) get_dump_list(const char *text, char *str,
	size_t str_len)
{
	int i;
	size_t count = 0;
	struct get_msg *msg;

	debug_raw("%s (count=%u) %s\n", __func__, get_manager.counter, text);
	if (str && count < str_len) {
		count += snprintf(str + count, str_len - count,
			"%s (count=%u) %s\n", __func__, get_manager.counter,
			text);
	}

	i = 0;
	list_for_each(&get_manager.list, msg, list_entry) {
		debug_raw("  [%d] token='%s', fd=%d\n",
			i, msg->token, msg->client_fd);
		if (str && count < str_len) {
			count += snprintf(str + count, str_len - count,
				"  [%d] token='%s', fd=%d\n",
				i, msg->token, msg->client_fd);
		}
		i++;
	}
	return count;
}

struct get_msg *get_find_by_token(const char *token)
{
	struct get_msg *entry;

	list_for_each(&get_manager.list, entry, list_entry) {
		//debug("test '%s'\n", entry->token);
		if (!strcmp(entry->token, token)) {
			debug("found: '%s'='%s'\n", entry->token, token);
			return entry;
		}
	}

	debug("not found: '%s'\n", token);
	return NULL;
}

int get_add(int client_fd, const char *token)
{
	struct get_msg *old;
	struct get_msg *new;

	debug("[%d] '%s'\n", get_manager.counter, token);

	old = get_find_by_token(token);

	if (old) {
		debug("remove old\n");
		list_remove(&old->list_entry);
		mem_free(old);
		get_manager.counter--;
	}

	if (get_full()) {
		get_clean_waiters();
		if (get_full()) {
			log("buffer full: '%s'\n", token);
			client_reply_and_close(client_fd, "ERR:full");
			return -1;
		}
	}

	new = mem_alloc_zero(sizeof(*new));

	build_assert(sizeof(new->token) >= sizeof(token));

	strncpy(new->token, token, sizeof(new->token));
	new->client_fd = client_fd;

	list_add_tail(&get_manager.list, &new->list_entry);
	get_manager.counter++;

	//get_print(msg);

	return 0;

}

void get_remove(struct get_msg *msg)
{
	assert(msg);
	
	list_remove(&msg->list_entry);
	get_manager.counter--;
	mem_free(msg);
}

void get_clean_waiters(void)
{
	struct get_msg *entry;
	struct get_msg *tmp;

	list_for_each_safe(&get_manager.list, entry, tmp, list_entry) {
		int result;
		socklen_t len;
		struct tcp_info info;

		debug("> %s\n", entry->token);

		len = sizeof(info);;
		result = getsockopt(entry->client_fd, SOL_TCP, TCP_INFO, &info, &len);

		if (result) {
			log("getsockopt failed: %s\n", strerror(errno));
		}

		debug("fd %d: %s (%u)\n", entry->client_fd,
			tcp_state(info.tcpi_state),
			(unsigned int)info.tcpi_state);

		if (result || info.tcpi_state != TCP_ESTABLISHED) {
			close(entry->client_fd);
			entry->client_fd = -1;
			get_remove(entry);
		}

		debug("<\n");
	}
}

//==============================================================================

static bool put_full(void)
{
	if (put_manager.counter >= put_manager.max_count) {
		debug("full\n");
		return true;
	}
	return false;
}

void _put_print(const char *func, int line, const struct put_msg *msg)
{
	debug_raw("%s:%d: put msg:\n", func, line);
	debug_raw("  token:  '%s'\n", msg->token);
	debug_raw("  server: '%s'\n", msg->server);
}

size_t __attribute__((unused)) put_dump_list(const char *text, char *str,
	size_t str_len)
{
	int i;
	size_t count = 0;
	struct put_msg *msg;

	debug_raw("%s (count=%u) %s\n", __func__, put_manager.counter, text);
	if (str && count < str_len) {
		count += snprintf(str + count, str_len - count,
			"%s (count=%u) %s\n", __func__, put_manager.counter,
			text);
	}

	i = 0;
	list_for_each(&put_manager.list, msg, list_entry) {
		debug_raw("  [%d] token='%s', server='%s', fd=%d\n",
			i, msg->token, msg->server, msg->client_fd);
		if (str && count < str_len) {
			count += snprintf(str + count, str_len - count,
				"  [%d] token='%s', server='%s', fd=%d\n",
				i, msg->token, msg->server, msg->client_fd);
		}
		i++;
	}
	return count;
}

struct put_msg *put_find_by_token(const char *token)
{
	struct put_msg *entry;

	list_for_each(&put_manager.list, entry, list_entry) {
		//debug("test '%s'\n", entry->token);
		if (!strcmp(entry->token, token)) {
			debug("found: '%s'='%s'\n", entry->token, token);
			return entry;
		}
	}

	debug("not found: '%s'\n", token);
	return NULL;
}

enum put_result put_add(int client_fd, const char *token, const char *server)
{
	int result;
	struct put_msg *old;
	struct put_msg *new;

	debug("[%d] '%s' '%s'\n", put_manager.counter, token, server);

	old = put_find_by_token(token);

	if (old) {
		result = put_result_updated;
		debug("remove old\n");
		list_remove(&old->list_entry);
		mem_free(old);
		put_manager.counter--;
	} else {
		result = put_result_queued;
	}
	
	if (put_full()) {
		struct put_msg *first;

		list_for_each(&put_manager.list, first, list_entry) {
			break;
		}
		debug("remove first: %p => %p:%s\n", &first->list_entry, first,
			first->token);
		list_remove(&first->list_entry);
		mem_free(first);
		put_manager.counter--;
	}

	new = mem_alloc_zero(sizeof(*new));

	build_assert(sizeof(new->token) >= sizeof(token));
	build_assert(sizeof(new->server) >= sizeof(server));

	strncpy(new->token, token, sizeof(new->token));
	strncpy(new->server, server, sizeof(new->server));
	new->client_fd = client_fd;

	list_add_tail(&put_manager.list, &new->list_entry);
	put_manager.counter++;
	//put_print(msg);

	return result;
}

void put_remove(struct put_msg *msg)
{
	debug("[%d] '%s' '%s'\n", put_manager.counter, msg->token, msg->server);
	list_remove(&msg->list_entry);
	mem_free(msg);
	put_manager.counter--;
}
