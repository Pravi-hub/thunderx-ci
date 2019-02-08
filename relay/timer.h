/*
 *  TCI relay.
 */

#ifndef _TIMER_H
#define _TIMER_H

//#include <stdbool.h>
#include <time.h>
#include "list.h"

typedef void (*timer_callback)(void *data);

struct timer {
	struct list_entry list_entry;
	time_t timeout;
	timer_callback callback;
	void *callback_data;
};

struct timer *timer_add(unsigned int seconds, timer_callback cb, void *cb_data);
void timer_start(void);
void timer_remove(struct timer *entry);
size_t __attribute__((unused)) timer_dump_list(const char *text, char *str,
	size_t str_len);
time_t time_left(struct timer *entry);

#endif /* _TIMER_H */
