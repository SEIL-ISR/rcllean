// The SIGINT and SIGTERM handlers, the thread they hand the work to, and the
// table of contexts that thread shuts down.

#include "signal_handler.h"

#include <pthread.h>
#include <semaphore.h>
#include <signal.h>
#include <string.h>

// Ctrl-C must reach an executor blocked in rcl_wait.  Shutting a context down
// is not async-signal-safe, so the handler only posts a semaphore and a
// dedicated thread does the work.

#define RCLLEAN_MAX_CONTEXTS 64

// Guards the table of live contexts, which the signal thread walks.
static pthread_mutex_t g_ctx_mutex = PTHREAD_MUTEX_INITIALIZER;
static rcllean_context_t *g_contexts[RCLLEAN_MAX_CONTEXTS];
static size_t g_context_count = 0;

static sem_t g_signal_sem;
static struct sigaction g_old_sigint;
static struct sigaction g_old_sigterm;
static pthread_once_t g_handlers_once = PTHREAD_ONCE_INIT;

static void rcllean_signal_handler(int signum, siginfo_t *info, void *uctx) {
  sem_post(&g_signal_sem);

  // Chain to the previously installed handler, so a debugger or a host
  // application still sees the signal.  An SA_SIGINFO handler lives in the
  // other union member and takes three arguments.
  const struct sigaction *old =
      signum == SIGINT ? &g_old_sigint : &g_old_sigterm;
  if (old->sa_flags & SA_SIGINFO) {
    if (old->sa_sigaction != NULL && old->sa_sigaction != rcllean_signal_handler) {
      old->sa_sigaction(signum, info, uctx);
    }
  } else if (old->sa_handler != SIG_DFL && old->sa_handler != SIG_IGN) {
    old->sa_handler(signum);
  }
}

// Never returns: the thread is detached at creation and dies with the
// process.  sem_wait is the only blocking point, so a spurious EINTR just
// loops.
static void *rcllean_signal_thread(void *arg) {
  (void)arg;
  for (;;) {
    if (sem_wait(&g_signal_sem) != 0) {
      continue;
    }
    // Holding the table lock keeps a context from unregistering, and so from
    // being torn down, while it is being shut down here.
    pthread_mutex_lock(&g_ctx_mutex);
    for (size_t i = 0; i < g_context_count; ++i) {
      rcllean_context_signal_shutdown(g_contexts[i]);
    }
    pthread_mutex_unlock(&g_ctx_mutex);
  }
  return NULL;
}

static void rcllean_signal_handlers_init(void) {
  if (sem_init(&g_signal_sem, 0, 0) != 0) {
    return;
  }
  pthread_t tid;
  if (pthread_create(&tid, NULL, rcllean_signal_thread, NULL) != 0) {
    sem_destroy(&g_signal_sem);
    return;
  }
  pthread_detach(tid);

  struct sigaction sa;
  memset(&sa, 0, sizeof sa);
  sa.sa_sigaction = rcllean_signal_handler;
  sigemptyset(&sa.sa_mask);
  sa.sa_flags = SA_RESTART | SA_SIGINFO;
  sigaction(SIGINT, &sa, &g_old_sigint);
  sigaction(SIGTERM, &sa, &g_old_sigterm);
}

void rcllean_signal_install_handlers(void) {
  pthread_once(&g_handlers_once, rcllean_signal_handlers_init);
}

// Past RCLLEAN_MAX_CONTEXTS the context is left out rather than failing the
// init; it just will not be shut down by Ctrl-C.
void rcllean_signal_register(rcllean_context_t *ctx) {
  pthread_mutex_lock(&g_ctx_mutex);
  if (g_context_count < RCLLEAN_MAX_CONTEXTS) {
    g_contexts[g_context_count++] = ctx;
  }
  pthread_mutex_unlock(&g_ctx_mutex);
}

void rcllean_signal_unregister(rcllean_context_t *ctx) {
  pthread_mutex_lock(&g_ctx_mutex);
  for (size_t i = 0; i < g_context_count; ++i) {
    if (g_contexts[i] == ctx) {
      g_contexts[i] = g_contexts[g_context_count - 1];
      g_context_count--;
      break;
    }
  }
  pthread_mutex_unlock(&g_ctx_mutex);
}
