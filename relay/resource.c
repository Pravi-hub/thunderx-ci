/*
 *  TCI relay.
 */

#include <assert.h>
//#include <errno.h>
//#include <stdio.h>
#include <string.h>
//#include <unistd.h>

#include "log.h"
#include "resource.h"
#include "util.h"

STATIC_LIST(resource_list);

struct resource *resource_find_by_name(const char *name)
{
	struct resource *entry;

	list_for_each(&resource_list, entry, list_entry) {
		//debug("test '%s'\n", entry->name);
		if (!strcmp(entry->name, name)) {
			debug("found '%s'\n", entry->name);
			return entry;
		}
	}
	debug("not found: '%s'\n", name);
	return NULL;
}

void resource_add(const char* name, unsigned int max_seconds)
{
	struct resource *new;

	debug("'%s', %u sec (%u min)\n", name, max_seconds, max_seconds / 60);

	new = mem_alloc_zero(sizeof(*new));
	
	assert(strlen(name) < sizeof(new->name));
	strncpy(new->name, name, sizeof(new->name));
	new->max_seconds = max_seconds;
	
	list_add_tail(&resource_list, &new->list_entry);
}

void resource_remove(const char* name)
{
	struct resource *resource;

	resource = resource_find_by_name(name);

	if (resource) {
		debug("found: '%s'\n", name);
		list_remove(&resource->list_entry);
		mem_free(resource);
		return;
	}
	debug("not found: '%s'\n", name);
}
