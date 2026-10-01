#ifndef UP60P_PROCESS_H
#define UP60P_PROCESS_H
#include "up60p.h"
#define UP60P_PROCESS_CANCELLED (-2)
int up60p_execute_owned_process(const char *supervisor, char *const argv[], up60p_log_callback callback);
void up60p_cancel_active_process(void);
void up60p_stop_processes(void);
#endif
