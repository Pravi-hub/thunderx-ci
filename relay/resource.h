/*
 *  TCI relay.
 */

#include "list.h"
#include "msg.h"

struct resource {
	struct list_entry list_entry;
	char name[msg_data_len];
	unsigned int max_seconds;
};

void resource_add(const char* name, unsigned int max_seconds);
void resource_remove(const char* name);

struct resource *resource_find_by_name(const char *name);
