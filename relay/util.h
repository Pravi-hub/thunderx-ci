/*
 * TCI relay.
 */

#define build_assert(_x) do {(void)sizeof(char[(_x) ? 1 : -1]);} while (0)

const char *__attribute__((unused)) tcp_state(unsigned int state);

void generate_token(char *token);
unsigned int to_unsigned(const char *str);

void *mem_alloc(size_t size);
void *mem_alloc_zero(size_t size);
#if defined(DEBUG)
# define mem_free(_p) do {_mem_free_debug(__func__, __LINE__, _p);} while(0)
#else
# define mem_free(_p) do {_mem_free(_p);} while(0)
#endif
void __attribute__((unused)) _mem_free_debug(const char *func, int line,
	void *p);
void _mem_free(void *p);

int __attribute__ ((format (printf, 2, 3))) client_reply_and_close(
	int client_fd, const char *fmt, ...);

