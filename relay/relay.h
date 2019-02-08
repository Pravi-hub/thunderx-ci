/*
 *  TCI relay.
 */

#include <stdbool.h>
#include <time.h>

#include "list.h"
#include "msg.h"

void relay_init(unsigned int get_max_count, unsigned int put_max_count);

struct get_msg {
	struct list_entry list_entry;
	char token[msg_data_len];
	int client_fd;
};

void _get_print(const char *func, int line, const struct get_msg *msg);
#define get_print(_msg) do {_get_print(__func__, __LINE__, _msg);} while(0)
size_t __attribute__((unused)) get_dump_list(const char *text, char *str,
	size_t str_len);
int get_add(int client_fd, const char *token);
void get_remove(struct get_msg *msg);
struct get_msg *get_find_by_resource(const char *resource);
struct get_msg *get_find_by_token(const char *token);
void get_clean_waiters(void);

struct put_msg {
	struct list_entry list_entry;
	char token[msg_data_len];
	char server[msg_data_len];
	int client_fd;
};

enum put_result {
	put_result_invalid = 0,
	put_result_updated,
	put_result_queued,
};

void _put_print(const char *func, int line, const struct put_msg *msg);
#define put_print(_msg) do {_put_print(__func__, __LINE__, _msg);} while(0)
size_t __attribute__((unused)) put_dump_list(const char *text, char *str,
	size_t str_len);
enum put_result put_add(int client_fd, const char *token, const char *server);
void put_remove(struct put_msg *msg);
struct put_msg *put_find_by_token(const char *token);
