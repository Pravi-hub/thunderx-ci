/*
 *  TCI relay.
 */

#include <stdbool.h>
#include <time.h>

#include "list.h"
#include "msg.h"

void checkout_init(unsigned int co_max_count);

void checkout_add_resource(const char* name, unsigned int max_seconds);
void checkout_remove_resource(const char* name);

struct co_msg {
	struct list_entry list_entry;
	char resource[msg_data_len];
	int client_fd;
	unsigned int timer_seconds;
	char token[msg_data_len];
	struct timer *timer;
};

void _co_print(const char *func, int line, const struct co_msg *msg);
#define co_print(_msg) do {_co_print(__func__, __LINE__, _msg);} while(0)
size_t __attribute__((unused)) co_dump_list(const char *text, char *str,
	size_t str_len);
int co_add(int client_fd, const char *resource, unsigned int request_seconds);
void co_remove(struct co_msg *msg);
struct co_msg *co_find_by_resource(const char *resource);
struct co_msg *co_find_by_token(const char *token);
void co_clean_waiters(void);
int co_reply_client(int client_fd, const char *token);
