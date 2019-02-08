/*
 * TCI relay.
 */

#include <stdbool.h>

void __attribute__((unused)) __attribute__ ((format (printf, 3, 4))) _log(const char *func, int line,
	const char *fmt, ...);
void __attribute__((unused)) __attribute__ ((format (printf, 1, 2))) log_raw(const char *fmt, ...);
#define log(_args...) do {_log(__func__, __LINE__, _args);} while(0)

void __attribute__((unused)) __attribute__ ((format (printf, 3, 4))) _debug(const char *func, int line,
	const char *fmt, ...);
void __attribute__((unused)) __attribute__ ((format (printf, 1, 2))) debug_raw(const char *fmt, ...);
#define debug(_args...) do {_debug(__func__, __LINE__, _args);} while(0)
void set_debug_on(bool b);
bool get_debug_on(void);
