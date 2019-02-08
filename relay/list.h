/*
 *  TCI relay.
 */

#ifndef _LIST_H
#define _LIST_H

#include <stdbool.h>

#if !defined(offsetof)
#define offsetof(_type, _member) ((size_t) &((_type *)0)->_member)
#endif

#if !defined(container_of)
#define container_of(_ptr, _type, _member) ({ \
	const typeof( ((_type *)0)->_member ) *__mptr = (_ptr); \
	(_type *)( (char *)__mptr - offsetof(_type,_member) );})
#endif

struct list_entry {
	struct list_entry *prev, *next;
};

struct list {
	struct list_entry head;
};

#define list_entry(_ptr, _type, _member, _list) \
	(&container_of(_ptr, _type, _member)->_member == &((_list)->head) \
	? NULL \
	: container_of(_ptr, _type, _member))

#define list_prev_entry(_list, _entry, _member) \
	list_entry(_entry->_member.prev, typeof(*_entry), _member, _list)

#define list_next_entry(_list, _entry, _member) \
	list_entry(_entry->_member.next, typeof(*_entry), _member, _list)

#define list_for_each(_list, _entry, _member) \
	for (_entry = list_entry((_list)->head.next, typeof(*_entry), _member, _list); \
		_entry; _entry = list_next_entry(_list, _entry, _member))

#define list_for_each_continue(_list, _entry, _member) \
	for (; _entry; _entry = list_next_entry(_list, _entry, _member))

#define list_for_each_safe(_list, _entry, _tmp, _member) \
	for (_entry = container_of((_list)->head.next, typeof(*_entry), _member), \
		_tmp = container_of(_entry->_member.next, typeof(*_entry), \
				_member); \
	     &_entry->_member != &(_list)->head; \
	     _entry = _tmp, \
	     _tmp = container_of(_tmp->_member.next, typeof(*_entry), _member))

#define DEFINE_LIST(_list) struct list _list = { \
	.head = { \
		.next = &_list.head, \
		.prev = &_list.head \
	} \
}

#define STATIC_LIST(_list) static DEFINE_LIST(_list)

void list_init(struct list *list);
void list_insert_before(struct list_entry *next, struct list_entry *entry);
void list_insert_after(struct list_entry *prev, struct list_entry *entry);
void list_remove(struct list_entry *entry);

static inline void list_add_head(struct list *list, struct list_entry *entry)
{
	list_insert_after(&list->head, entry);
}
static inline void list_add_tail(struct list *list, struct list_entry *entry)
{
	list_insert_before(&list->head, entry);
}

#endif /* _LIST_H */
