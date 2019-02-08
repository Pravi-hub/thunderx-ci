/*
 *  TCI relay.
 */

// (cd ${HOME}/projects/tci/relay && ./bootstrap) && ${HOME}/projects/tci/relay/configure --enable-debug --enable-debug-mem

#define _GNU_SOURCE

#if defined(HAVE_CONFIG_H)
#include "config.h"
#endif

#include <assert.h>
//#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
//#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <linux/limits.h>

#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>

#include "checkout.h"
#include "log.h"
#include "relay.h"
#include "resource.h"
#include "timer.h"
#include "util.h"

#if !defined(SITE_CONFIG_FILE)
# define SITE_CONFIG_FILE "/etc/tci-relay.conf"
#endif

static void print_version(void)
{
#if defined(PACKAGE_NAME) && defined(PACKAGE_VERSION)
	printf("tci-relay (" PACKAGE_NAME ") " PACKAGE_VERSION "\n");
#else
# error PACKAGE_VERSION not defined.
#endif
}

static void print_bugreport(void)
{
#if defined(PACKAGE_BUGREPORT)
	fprintf(stderr, "Send bug reports to " PACKAGE_BUGREPORT ".\n");
#else
# error PACKAGE_BUGREPORT not defined.
#endif
}

enum opt_value {opt_undef = 0, opt_yes, opt_no};

struct opts {
	char *config;
	enum opt_value help;
	unsigned int port;
	enum opt_value verbose;
	enum opt_value version;
};

static void print_usage(const struct opts *opts)
{
	print_version();

	fprintf(stderr,
		"tci-relay - ThunderX-CI relay server.\n"
		"Usage: tci-relay [flags]\n"
		"Option flags:\n"
		"  -c --config <config-file> - Site configuration file. Default: '%s'.\n"
		"  -h --help                 - Show this help and exit.\n"
		"  -p --port                 - Server IP port. Default: '%u'.\n"
		"  -v --verbose              - Verbose execution.\n"
		"  -V --version              - Display the program version number.\n",
		opts->config, opts->port);

	print_bugreport();
}

static int opts_parse(struct opts *opts, int argc, char *argv[])
{
	static const struct option long_options[] = {
		{"config",  required_argument, NULL, 'c'},
		{"help",    no_argument,       NULL, 'h'},
		{"port",    required_argument, NULL, 'p'},
		{"verbose", no_argument,       NULL, 'v'},
		{"version", no_argument,       NULL, 'V'},
		{ NULL,     0,                 NULL, 0},
	};
	static const char short_options[] = "chp:vV";

	*opts = (struct opts) {
		.config = NULL,
		.help = opt_no,
		.port = 9600U,
		.verbose = opt_no,
		.version = opt_no,
	};

	if (1) {
		int i;

		log("argc = %d\n", argc);
		for (i = 0; i < argc; i++) {
			log("  %d: %p = '%s'\n", i, &argv[i], argv[i]);
		}
	}
	
	while (1) {
		int c = getopt_long(argc, argv, short_options, long_options,
			NULL);

		if (c == EOF)
			break;

		switch (c) {
		case 'c': {
			size_t len;
			
			log("c:   %p = '%s'\n", optarg, optarg);
			if (!optarg) {
				fprintf(stderr,
					"tci-relay ERROR: Missing required argument <config-file>.'\n");
				opts->help = opt_yes;
				return -1;
			}
			len = strlen(optarg) + 1;
			opts->config = mem_alloc(len);
			strcpy(opts->config, optarg);
			break;
		}
		case 'h':
			opts->help = opt_yes;
			break;
		case 'p':
			opts->port = to_unsigned(optarg);
			break;
		case 'v':
			opts->verbose = opt_yes;
			break;
		case 'V':
			opts->version = opt_yes;
			break;
		default:
			opts->help = opt_yes;
			return -1;
		}
	}

	if (!opts->config) {
		opts->config = mem_alloc(sizeof(SITE_CONFIG_FILE));
		strcpy(opts->config, SITE_CONFIG_FILE);
	}

	return optind != argc;
}

static size_t dump_lists(const char *text, char *str, size_t str_len)
{
	size_t count = 0;

	if (str && count < str_len) {
		count += snprintf(str + count, str_len - count, "\n");
	}
	count += put_dump_list(text, str + count, str_len - count);
	count += get_dump_list(text, str + count, str_len - count);
	count += co_dump_list(text, str + count, str_len - count);
	count += timer_dump_list(text, str + count, str_len - count);
	if (str && count < str_len) {
		count += snprintf(str + count, str_len - count, "\n");
	}

	return count;
}

struct connection {
	int socket;
};

static int connection_setup(struct connection* con, unsigned int port,
	bool debug)
{
	struct sockaddr_in addr = {0};
	int result;

	con->socket = socket(AF_INET, SOCK_STREAM, 0);

	if (con->socket < 0) {
		log("socket failed: %s\n", strerror(errno));
		return -1;
	}

	addr.sin_family = AF_INET;
	addr.sin_port = htons(port);
	addr.sin_addr.s_addr = htons(INADDR_ANY);

	if (debug) {
		int optval = 1;
		setsockopt(con->socket, SOL_SOCKET, SO_REUSEPORT, &optval,
			sizeof(optval));
	}

	result = bind(con->socket, (struct sockaddr *)&addr, sizeof(addr));

	if (result) {
		log("bind failed: %s\n", strerror(errno));
		return -1;
	}

	result = listen(con->socket, 8);

	if (result) {
		log("listen failed: %s\n", strerror(errno));
		return -1;
	}

	debug("Success @%u\n", port);
	return 0;
}

static char *config_eat_ws(char *p)
{
	while (*p && (*p == ' ' || *p == '\t' || *p == '\r')) {
		p++;
	}
	return p;
}

static char *config_find_start(char *p)
{
	char *start;

	start = p = config_eat_ws(p);

	while (*p) {
		if (*p == '#' || *p == '\n'  || *p == '\r' ) {
			*p = 0;
			return start;
		}
		p++;
	}

	return start;
}

static void config_process_file(const char *config_file)
{
	FILE *fp;
	char buf[512];
	struct limits {
		unsigned int checkout;
		unsigned int get;
		unsigned int put;
	} limits = {
		.checkout = 3,
		.get = 3,
		.put = 3,
	};
	enum config_state {state_unknown, state_limits = 1, state_resources};
	enum config_state state = state_unknown;

	fp = fopen(config_file, "r");

	if (!fp) {
		log("open config '%s' failed: %s\n", config_file,
			strerror(errno));
		assert(0);
		exit(EXIT_FAILURE);
	}
	
	while (fgets(buf, sizeof(buf), fp)) {
		char *p;
		char *name;
		char *value;

		p = config_find_start(buf);

		if (!*p) {
			debug("null line\n");
			continue;
		}

		if (!strcmp(p, "[limits]")) {
			debug("state=limits:\n");
			state = state_limits;
			continue;
		}

		if (!strcmp(p, "[resources]")) {
			debug("state=resources\n");
			state = state_resources;
			continue;
		}

		name = strtok(p, "=");
		value = strtok(NULL, " \t");

		switch (state) {
		case state_limits:
			debug("limits: '%s', '%s'\n", name, value);
			if (!strcmp(name, "checkout")) {
				limits.checkout = to_unsigned(value);
			}
			if (!strcmp(name, "put")) {
				limits.put = to_unsigned(value);
			}
			if (!strcmp(name, "get")) {
				limits.get = to_unsigned(value);
			}
			break;
		case state_resources:
			debug("resources: '%s', '%s'\n", name, value);
			resource_add(name, to_unsigned(value));
			break;
		default:
			log("Bad config data '%s' (%s)\n", p, config_file);
			assert(0);
			exit(EXIT_FAILURE);
		}
	}

	relay_init(limits.put, limits.get);
	checkout_init(limits.checkout);
}

static int client_read(int client_fd, char *buf, unsigned int buf_len)
{
	int result;

	result = read(client_fd, buf, buf_len - 1);

	if (result < 0) {
		log("read failed: %s\n", strerror(errno));
		return -1;
	}

	buf[result] = 0;

	debug("%u bytes: '%s'\n", (unsigned int)result, buf);

	return 0;
}

struct parse_data {
	char data[msg_data_len];
};

static int parse_two(int client_fd, char *msg, char *name1,
	struct parse_data *d1, char *name2, struct parse_data *d2)
{
	const char *p;
	const char *extra;

	//debug("> '%s'\n", msg);

	d1->data[0] = 0;
	p = strtok(msg, ":");

	if (p) {
		strncpy(d1->data, p, sizeof(d1->data));
	}

	if (!p || !strlen(d1->data)) {
		log("bad %s: '%s'\n", name1, d1->data);
		client_reply_and_close(client_fd, "ERR:%s", name1);
		return -1;
	}

	if (d2) {
		d2->data[0] = 0;
		p = strtok(NULL, ":");

		if (p) {
			strncpy(d2->data, p, sizeof(d2->data));
		}

		if (!p || !strlen(d2->data)) {
			log("bad %s: '%s'\n", name2, d2->data);
			client_reply_and_close(client_fd, "ERR:%s", name2);
			return -1;
		}
	}

	extra = strtok(NULL, ":");

	if (extra) {
		log("bad extra: '%s'\n", extra);
		client_reply_and_close(client_fd, "ERR:extra");
		return -1;
	}

	debug("'%s', '%s'\n", d1->data, d2 ? d2->data : "(null)");
	return 0;
}

static int parse_one(int client_fd, char *msg, char *name1,
	struct parse_data *d1)
{
	return parse_two(client_fd, msg, name1, d1, NULL, NULL);
}

static int process_cki(int client_fd, char *msg)
{
	int result;
	struct parse_data token;
	struct co_msg *entry;

	debug("'%s'\n",msg);

	result = parse_one(client_fd, msg, "token", &token);

	if (result) {
		return result;
	}

	entry = co_find_by_token(token.data);
	
	if(!entry) {
		debug("not found: '%s'\n", token.data);
		return client_reply_and_close(client_fd, "ERR:unknown");
	}

	co_remove(entry);
	timer_start();

	return client_reply_and_close(client_fd, "OK-");
}

static int process_cko(int client_fd, char *msg)
{
	int result;
	struct parse_data resource;
	struct parse_data seconds;
	unsigned int request_seconds;
	struct resource *resource_entry;

	debug("'%s'\n", msg);

	result = parse_two(client_fd, msg, "resource", &resource, "seconds",
		&seconds);

	if (result) {
		return result;
	}

	request_seconds = to_unsigned(seconds.data);
	resource_entry = resource_find_by_name(resource.data);

	if (!resource_entry) {
		log("Unknown resource: '%s'\n", resource.data);
		client_reply_and_close(client_fd, "ERR:unknown");
		return -1;
	}

	if (!request_seconds) {
		client_reply_and_close(client_fd, "ERR:null:%u",
			resource_entry->max_seconds);
		return 0;
	}

	if (request_seconds > resource_entry->max_seconds) {
		log("Request too big: %u > %u (seconds)\n", request_seconds,
			resource_entry->max_seconds);
		client_reply_and_close(client_fd, "ERR:limit:%u",
			resource_entry->max_seconds);
		return -1;
	}

	co_add(client_fd, resource.data, request_seconds);
	return 0;
}

static int process_ckq(int client_fd, char *msg)
{
	int result;
	struct parse_data resource;
	struct resource *r_entry;
	struct co_msg *co_entry;

	debug("'%s'\n",msg);

	result = parse_one(client_fd, msg, "resource", &resource);

	if (result) {
		return result;
	}

	r_entry = resource_find_by_name(resource.data);

	if (!r_entry) {
		debug("not found: '%s'\n", resource.data);
		return client_reply_and_close(client_fd, "ERR:unknown");
	}

	co_entry = co_find_by_resource(resource.data);

	if (!co_entry) {
		return client_reply_and_close(client_fd, "OK-:%s:0",
			resource.data);
	}

	return client_reply_and_close(client_fd, "OK-:%s:%ld",
		co_entry->resource, (long)time_left(co_entry->timer));
}

static int process_dmp(int  __attribute__((unused)) client_fd,
	char __attribute__((unused)) *msg)
{
	const size_t str_len = 1024;
	char* str = mem_alloc(str_len);
	size_t count;
	size_t written;

	count = dump_lists("- dmp", str, str_len);
	str[str_len - 1] = 0;

	if (count >= str_len) {
		log("ERROR: String full:\n%s\n", str);
		assert(0);
	}

	written = write(client_fd, str, count);

	if (written != count) {
		log("ERROR: Write failed: %s\n", strerror(errno));
		assert(0);
		exit(EXIT_FAILURE);
	}

	client_reply_and_close(client_fd, "OK-");

	mem_free(str);
	return 0;
}

static int process_get(int client_fd, char *msg)
{
	int result;
	struct parse_data token;
	struct put_msg *p_msg;

	debug("> '%s'\n", msg);

	result = parse_one(client_fd, msg, "token", &token);

	if (result) {
		return result;
	}

	p_msg = put_find_by_token(token.data);

	if (p_msg) {
		result = client_reply_and_close(client_fd, "OK-:%s",
			p_msg->server);
		put_remove(p_msg);
		return result;
	}

	return get_add(client_fd, token.data);
}

static int process_put(int client_fd, char *msg)
{
	int result;
	struct parse_data token;
	struct parse_data server;
	struct get_msg *g_msg;

	//debug("> '%s'\n", msg);

	result = parse_two(client_fd, msg, "token", &token, "server", &server);

	if (result) {
		return result;
	}

	g_msg = get_find_by_token(token.data);

	if (g_msg) {
		result = client_reply_and_close(g_msg->client_fd, "OK-:%s",
			server.data);
		get_remove(g_msg);
		return client_reply_and_close(client_fd, "FWD");
	}

	result = put_add(client_fd, token.data, server.data);

	return client_reply_and_close(client_fd,
		(result == put_result_updated) ? "UPD" : "QED");
}

static struct connection connection;

struct sig_events {
	bool alarm;
	bool term;
};

static struct sig_events sig_events = {
	.alarm = false,
	.term = false,
};

static void procss_sock_events(unsigned int revents)
{
	int result;
	int client_fd;
	char buf[msg_buffer_len];

	debug("revents=%x\n", revents);

	client_fd = accept(connection.socket, NULL, NULL);

	if (client_fd < 0) {
		log("accept failed: %s\n", strerror(errno));
		assert(0);
		exit(EXIT_FAILURE);
	}

	result = client_read(client_fd, buf, sizeof(buf));
	
	if (result < 0) {
		return;
	}

	if (buf[3] != ':') {
		client_reply_and_close(client_fd, "ERR:format");
		return;
	} else if (!memcmp(buf, "CKI:", 4)) {
		process_cki(client_fd, buf + 4);
	} else if (!memcmp(buf, "CKO:", 4)) {
		process_cko(client_fd, buf + 4);
	} else if (!memcmp(buf, "CKQ:", 4)) {
		process_ckq(client_fd, buf + 4);
	} else if (!memcmp(buf, "DMP:", 4)) {
		process_dmp(client_fd, buf + 4);
	} else if (!memcmp(buf, "GET:", 4)) {
		process_get(client_fd, buf + 4);
	} else if (!memcmp(buf, "PUT:", 4)) {
		process_put(client_fd, buf + 4);
	} else {
		log("unknown cmd: '%s'\n", buf);
		client_reply_and_close(client_fd, "ERR:unknown-cmd");
	}
}

static void SIGTERM_handler(int __attribute__((unused)) signum)
{
	log("Exiting...\n");
	sig_events.term = true;
}

static void SIGALRM_handler(int __attribute__((unused)) signum)
{
	debug("\n");
	sig_events.alarm = true;
}

int main(int argc, char *argv[])
{
	int result;
	struct opts opts;
	unsigned int counter;
	enum {poll_sock = 0};
	struct pollfd pollfd[1];
	const unsigned int pollfd_len = sizeof(pollfd) / sizeof(pollfd[0]);

	if (opts_parse(&opts, argc, argv)) {
		print_usage(&opts);
		return EXIT_FAILURE;
	}

	if (opts.help == opt_yes) {
		print_usage(&opts);
		return EXIT_SUCCESS;
	}

	if (opts.version == opt_yes) {
		print_version();
		return EXIT_SUCCESS;
	}

	set_debug_on(!!opts.verbose);

	signal(SIGTERM, SIGTERM_handler);
	signal(SIGALRM, SIGALRM_handler);

	result = connection_setup(&connection, opts.port, get_debug_on());

	if (result) {
		return EXIT_FAILURE;
	}

	memset(pollfd, 0, sizeof(pollfd));

	pollfd[poll_sock].fd = connection.socket;
	//pollfd[poll_sock].events = POLLIN | POLLOUT | POLLMSG | POLLREMOVE | POLLRDHUP;
	pollfd[poll_sock].events = POLLIN;

	config_process_file(opts.config);
	mem_free(opts.config);
	opts.config = NULL;

	counter = 1;
	while (!sig_events.term) {
		debug_raw("[%u]=====================\n", counter++);
		dump_lists("- main", NULL, 0);
		debug_raw("--------------------------\n");

		result = poll(pollfd, pollfd_len, -1);

		log("poll up: %d %s(%d)\n", result, strerror(errno), errno);

		if (result <= 0 && errno != EINTR) {
			log("poll failed: %d %s(%d)\n", result, strerror(errno), errno);
			assert(0);
		}

		if (sig_events.term) {
			break;
		}

		get_clean_waiters();
		co_clean_waiters();

		if (sig_events.alarm) {
			sig_events.alarm = false;
			timer_start();
		}

		if (pollfd[poll_sock].revents) {
			procss_sock_events(pollfd[poll_sock].revents);
		}
	}

	return EXIT_SUCCESS;
}

