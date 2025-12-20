#include "up60p.h"
#include "up60p_settings.h"
#include "up60p_common.h"

#ifndef UP60P_LIBRARY_MODE
int main(int argc, char **argv) {
    set_defaults();
    init_paths();
    ensure_conf_dirs();
    
    char ap[128];
    active_preset_name(ap, sizeof(ap));
    load_preset_file(ap, true);
    
    if (argc > 1 && argv[1][0] != '-') {
        struct stat st;
        if (stat(argv[1], &st) == 0) {
            const char *ffmpeg = get_bundled_ffmpeg_path();
            if (!ffmpeg) return 1;
            
            if (S_ISDIR(st.st_mode)) {
                process_directory(argv[1], ffmpeg);
            } else {
                process_file(argv[1], ffmpeg, false);
            }
            return 0;
        }
    }
    
    return interactive_mode(argv[0]);
}
#endif

#ifndef UP60P_LIBRARY_MODE
//#include <spawn.h>
//extern char **environ;
//
//static int execute_ffmpeg_command(char **args) {
//    pid_t pid;
//    int status = 0;
//
//    int result = posix_spawn(&pid, args[0], NULL, NULL, args, environ);
//    if (result != 0) {
//        perror("posix_spawn");
//        return result;
//    }
//
//    if (waitpid(pid, &status, 0) == -1) {
//        perror("waitpid");
//        return 1;
//    }
//
//    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
//}


static int execute_ffmpeg_command(char **args) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        execvp(args[0], args);
        perror("execvp");
        _exit(1);
    }
    int status;
    waitpid(pid, &status, 0);
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
#endif


#ifdef UP60P_LIBRARY_MODE
void log_message(const char *format, ...) {
    if (global_log_cb) {
        char buffer[4096];
        va_list args;
        va_start(args, format);
        vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);
        global_log_cb(buffer);
    } else {
        va_list args;
        va_start(args, format);
        vprintf(format, args);
        va_end(args);
    }
}
#endif

