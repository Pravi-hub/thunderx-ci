/*
 *  TCI relay.
 */

#include <stdlib.h>

#include "list.h"
#include "log.h"

void list_init(struct list *list)
{
	list->head.next = &list->head;
	list->head.prev = &list->head;
}

void list_insert_before(struct list_entry *next, struct list_entry *entry)
{
	debug("%p\n", entry);
	entry->next = next;
	entry->prev = next->prev;
	next->prev->next = entry;
	next->prev = entry;
}

void list_insert_after(struct list_entry *prev, struct list_entry *entry)
{
	debug("%p\n", entry);
	entry->next = prev->next;
	entry->prev = prev;
	prev->next->prev = entry;
	prev->next = entry;
}

void list_remove(struct list_entry *entry)
{
	debug("%p\n", entry);
	entry->next->prev = entry->prev;
	entry->prev->next = entry->next;
}
