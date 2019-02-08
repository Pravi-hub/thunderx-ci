/*
 *  TCI relay.
 */

#include <assert.h>
#include <stdio.h>
#include <unistd.h>

#include "timer.h"
#include "log.h"
#include "util.h"

STATIC_LIST(timer_list);

size_t __attribute__((unused)) timer_dump_list(const char *text, char *str,
	size_t str_len)
{
	int i;
	size_t count = 0;
	struct timer *entry;

	debug_raw("%s %s\n", __func__, text);
	if (str && count < str_len) {
		count += snprintf(str + count, str_len - count,
			"%s %s\n", __func__, text);
	}

	i = 0;
	list_for_each(&timer_list, entry, list_entry) {
		debug_raw("  [%d] entry=%p, callback_data=%p\n",
			i, entry, entry->callback_data);
		if (str && count < str_len) {
			count += snprintf(str + count, str_len - count,
				"  [%d] entry=%p, callback_data=%p\n",
				i, entry, entry->callback_data);
		}
		i++;
	}
	return count;
}

static void timer_run_callbacks(time_t now)
{
	struct timer *tmp;
	struct timer *entry;

	//debug("[%ld] >\n", (long)now);

restart:
	list_for_each_safe(&timer_list, entry, tmp, list_entry) {
		debug("[%ld] check: timeout=%ld(%lds)\n", (long)now, (long)entry->timeout, (long)(entry->timeout - now));

		if (entry->timeout <= now) {
			struct timer saved;

			debug("[%ld] run: callback_data=%p\n", (long)now, entry->callback_data);

			assert(entry->callback);
			assert(entry->callback_data);

			saved = *entry;
			timer_remove(entry);

			saved.callback(saved.callback_data);
			goto restart;
		}
		return;
	}

	debug("[%ld] timer list empty\n", (long)now);
}

void timer_remove(struct timer *timer)
{
	struct timer *entry;

	debug("%p\n", timer);
	timer_dump_list(__func__, NULL, 0);

	list_for_each(&timer_list, entry, list_entry) {
		if (entry == timer) {
			list_remove(&timer->list_entry);
			mem_free(timer);
			return;
		}
	}

	debug("not found %p\n", timer);
}

void timer_start(void)
{
	struct timer *tmp;
	struct timer *entry;
	time_t now;

	now = time(NULL);

	timer_run_callbacks(now);

	// Set alarm to first non-expired timeout.
	list_for_each_safe(&timer_list, entry, tmp, list_entry) {
		debug("[%ld] start timeout=%ld(%lds)\n", (long)now, (long)entry->timeout, (long)(entry->timeout - now));
		alarm(entry->timeout - now);
		return;
	}
	debug("[%ld] timer list empty\n", (long)now);
}

struct timer *timer_add(unsigned int seconds, timer_callback cb, void *cb_data)
{
	time_t now;
	struct timer *new;
	struct timer *tmp;
	struct timer *entry;

	assert(seconds);
	assert(cb);
	assert(cb_data);

	alarm(0);
	now = time(NULL);

	timer_run_callbacks(now);

	new = mem_alloc_zero(sizeof(*new));
	new->callback = cb;
	new->callback_data = cb_data;
	new->timeout = now + seconds;

	//debug("[%ld] new timeout=%ld(%lds), callback_data=%p\n", (long)now,
	//      (long)new->timeout, (long)(new->timeout - now), new->callback_data);

	list_for_each_safe(&timer_list, entry, tmp, list_entry) {
		debug("[%ld] check timeout=%ld(%lds)\n", (long)now, (long)entry->timeout, (long)(entry->timeout - now));
		
		// Keep list sorted, shortest in front.
		if (new->timeout < entry->timeout) {
			debug("[%ld] add timeout=%ld(%lds), callback_data=%p\n", (long)now,
				(long)new->timeout, (long)(new->timeout - now), new->callback_data);
			list_insert_before(&entry->list_entry, &new->list_entry);
			timer_start();
			return new;
		}
	}

	debug("[%ld] add tail timeout=%ld(%lds), callback_data=%p\n", (long)now,
		(long)new->timeout, (long)(new->timeout - now), new->callback_data);
	list_add_tail(&timer_list, &new->list_entry);
	timer_start();
	return new;
}

time_t time_left(struct timer *entry)
{
	return entry->timeout - time(NULL);
}
