//#include "up60p.h"
//#include "up60p_settings.h"
//#include "up60p_common.h"
//#include "up60p_utils.h"
//#include "up60p_cli.h"
//
//void process_directory(const char *dir, const char *ffmpeg);
//void process_file(const char *in, const char *ffmpeg, bool batch);
//const char* get_bundled_ffmpeg_path(void);
//
//
//int main(int argc, char **argv) {
//    
//    set_defaults();
//    init_paths();
//    ensure_conf_dirs();
//    
//    char ap[128];
//    active_preset_name(ap, sizeof(ap));
//    load_preset_file(ap, true);
//
//    if (argc > 1 && argv[1][0] != '-') {
//        struct stat st;
//        if (stat(argv[1], &st) == 0) {
//            const char *ffmpeg = get_bundled_ffmpeg_path();
//            if (!ffmpeg) {
//                fprintf(stderr, "Error: bundled ffmpeg not found.\n");
//                return 1;
//            }
//            
//            if (S_ISDIR(st.st_mode)) {
//                process_directory(argv[1], ffmpeg);
//            } else {
//                process_file(argv[1], ffmpeg, false);
//            }
//            return 0;
//        }
//    }
//    
//    return interactive_mode(argv[0]);
//}
