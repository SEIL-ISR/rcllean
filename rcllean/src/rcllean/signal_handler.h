// Ctrl-C handling.  A sigaction posts a semaphore and a dedicated thread
// shuts every registered context down, so an executor blocked in rcl_wait
// returns.

#ifndef RCLLEAN_SIGNAL_HANDLER_H
#define RCLLEAN_SIGNAL_HANDLER_H

#include "context.h"

// Add a context to the set the signal thread shuts down.
void rcllean_signal_register(rcllean_context_t *ctx);

// Drop a context from that set, from the context's own teardown.
void rcllean_signal_unregister(rcllean_context_t *ctx);

// Install the SIGINT and SIGTERM handlers and start the signal thread.  Only
// the first call does anything.
void rcllean_signal_install_handlers(void);

#endif // RCLLEAN_SIGNAL_HANDLER_H
