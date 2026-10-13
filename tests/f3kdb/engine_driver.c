#include "up60p.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static int cancel_ms;
static void log_message(const char *text) { fputs(text,stderr); }
static void *cancel_worker(void *unused) {
    (void)unused;
    struct timespec delay={cancel_ms/1000,(cancel_ms%1000)*1000000L};
    nanosleep(&delay,NULL); up60p_request_cancel(); return NULL;
}
int main(int argc,char **argv) {
    if (argc<5) return 99;
    if (up60p_init(NULL,log_message)!=UP60P_OK) return 98;
    up60p_options o; up60p_default_options(&o);
    o.no_decimate=o.no_interpolate=o.no_denoise=o.no_deblock=o.no_sharpen=o.no_eq=o.no_grain=true;
    o.no_deband=strcmp(argv[3],"primary") && strcmp(argv[3],"both");
    o.use_deband_2=!strcmp(argv[3],"secondary") || !strcmp(argv[3],"both");
    snprintf(o.deband_method,sizeof(o.deband_method),"f3kdb");
    snprintf(o.deband_method_2,sizeof(o.deband_method_2),"f3kdb");
    snprintf(o.f3kdb_range,sizeof(o.f3kdb_range),"15");
    snprintf(o.f3kdb_y,sizeof(o.f3kdb_y),"128");
    snprintf(o.f3kdb_cbcr,sizeof(o.f3kdb_cbcr),"96");
    snprintf(o.f3kdb_range_2,sizeof(o.f3kdb_range_2),"7");
    snprintf(o.f3kdb_y_2,sizeof(o.f3kdb_y_2),"32");
    snprintf(o.f3kdb_cbcr_2,sizeof(o.f3kdb_cbcr_2),"16");
    snprintf(o.outdir,sizeof(o.outdir),"%s",argv[2]);
    snprintf(o.scale_factor,sizeof(o.scale_factor),"1");
    snprintf(o.fps,sizeof(o.fps),"source");
    snprintf(o.encoder,sizeof(o.encoder),"cpu");
    snprintf(o.hwaccel,sizeof(o.hwaccel),"none");
    snprintf(o.codec,sizeof(o.codec),"h264");
    snprintf(o.threads,sizeof(o.threads),"1");
    snprintf(o.preset,sizeof(o.preset),"ultrafast");
    o.use10=atoi(argv[4])==10;
    if (argc>5 && !strcmp(argv[5],"zero")) {
        snprintf(o.f3kdb_range,sizeof(o.f3kdb_range),"0");
        snprintf(o.f3kdb_y,sizeof(o.f3kdb_y),"0");
        snprintf(o.f3kdb_cbcr,sizeof(o.f3kdb_cbcr),"0");
    }
    if (argc>5 && !strcmp(argv[5],"invalid")) snprintf(o.f3kdb_y,sizeof(o.f3kdb_y),"512");
    pthread_t worker; bool join=false;
    if (argc>5 && (cancel_ms=atoi(argv[5]))>0) { pthread_create(&worker,NULL,cancel_worker,NULL);join=true; }
    up60p_error result=up60p_process_path(argv[1],&o);
    if(join)pthread_join(worker,NULL);
    fprintf(stderr,"ENGINE_RESULT=%d\n",result);
    return result;
}
