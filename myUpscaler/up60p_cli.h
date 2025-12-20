#ifndef UP60P_CLI_H
#define UP60P_CLI_H

int interactive_mode(const char *self_path);

int process_cli_args(int argc, char **argv, const char *ffmpeg_path);

#endif
