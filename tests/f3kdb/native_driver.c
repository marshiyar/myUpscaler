#include "up60p.h"
#include "up60p_utils.h"
#include <pthread.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
static int cancel_delay;
static void logger(const char *message) {
    fputs(message,stderr);
    // Test-only deterministic cancellation after the irreversible commit.
    if (getenv("UP60P_TEST_CANCEL_AFTER_DONE") && !strcmp(message,"Done.\n")) up60p_request_cancel();
}
static void *cancel_later(void *unused) {
    (void)unused;
    struct timespec time = {cancel_delay/1000, (cancel_delay%1000)*1000000L};
    nanosleep(&time,NULL); up60p_request_cancel(); return NULL;
}
int main(int argc,char **argv) {
    if (argc<4) return 99;
    if (up60p_init(NULL,logger)!=UP60P_OK) return 98;
    up60p_options options; up60p_default_options(&options);
    options.no_denoise=options.no_deblock=options.no_sharpen=options.no_decimate=options.no_interpolate=true;
    options.no_eq=options.no_grain=true;
    options.no_deband=strcmp(argv[1],"secondary")==0 || strcmp(argv[1],"bypass")==0;
    options.use_deband_2=strcmp(argv[1],"primary")!=0 && strcmp(argv[1],"bypass")!=0;
    snprintf(options.deband_method,sizeof(options.deband_method),"neo_f3kdb");
    snprintf(options.deband_method_2,sizeof(options.deband_method_2),"neo_f3kdb");
    snprintf(options.f3kdb_range,sizeof(options.f3kdb_range),"15");
    snprintf(options.f3kdb_range_2,sizeof(options.f3kdb_range_2),"17");
    snprintf(options.f3kdb_y,sizeof(options.f3kdb_y),"128");
    snprintf(options.f3kdb_cbcr,sizeof(options.f3kdb_cbcr),"96");
    snprintf(options.f3kdb_y_2,sizeof(options.f3kdb_y_2),"64");
    snprintf(options.f3kdb_cbcr_2,sizeof(options.f3kdb_cbcr_2),"32");
    snprintf(options.scale_factor,sizeof(options.scale_factor),"1");
    snprintf(options.fps,sizeof(options.fps),"source");
    snprintf(options.threads,sizeof(options.threads),"1");
    snprintf(options.preset,sizeof(options.preset),"ultrafast");
    snprintf(options.outdir,sizeof(options.outdir),"%s",argv[3]);
    if (argc>4 && !strcmp(argv[4],"10")) options.use10=true;
    if (argc>4 && !strcmp(argv[4],"invalid")) snprintf(options.f3kdb_y,sizeof(options.f3kdb_y),"512");
    if (argc>4 && !strcmp(argv[4],"zero")) {
        snprintf(options.f3kdb_range,sizeof(options.f3kdb_range),"0");
        snprintf(options.f3kdb_y,sizeof(options.f3kdb_y),"0");
        snprintf(options.f3kdb_cbcr,sizeof(options.f3kdb_cbcr),"0");
    }
    if (argc>4 && !strcmp(argv[4],"neutral-f3")) {
        snprintf(options.f3kdb_y,sizeof(options.f3kdb_y),"0");
        snprintf(options.f3kdb_cbcr,sizeof(options.f3kdb_cbcr),"0");
    }
    pthread_t control; bool has_control=argc>5;
    if (has_control) { cancel_delay=atoi(argv[5]); pthread_create(&control,NULL,cancel_later,NULL); }
    int result=up60p_process_path(argv[2],&options);
    if (has_control) pthread_join(control,NULL);
    up60p_shutdown();
    if (result == UP60P_OK_COMMITTED) {
        fputs("Native result: UP60P_OK_COMMITTED\n",stderr);
        return 0;
    }
    return result;
}
