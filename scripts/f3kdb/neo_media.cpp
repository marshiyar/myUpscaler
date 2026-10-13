/* Private CPU-only NUT/rawvideo stage. Input is a bounded, owned intermediate,
 * never arbitrary compressed media. Audio packets and stream properties copy.
 * One frame of scratch is unpublished until all three planes have completed. */
#include "neo_adapter.h"
extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/imgutils.h>
#include <libavutil/pixdesc.h>
}
#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
#include <sys/stat.h>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;
static void stop(int) { stopping = 1; }
static int cancelled(void *) { return stopping != 0; }
static void check(int code, const char *message) {
    if (code < 0) {
        char text[AV_ERROR_MAX_STRING_SIZE]; av_strerror(code, text, sizeof(text));
        throw std::runtime_error(std::string(message) + ": " + text);
    }
    if (stopping) throw std::runtime_error("Neo processing cancelled");
}
static int integer(const char *text) {
    char *end; errno = 0;
    long value = strtol(text, &end, 10);
    if (end == text || *end || errno || value < 0 || value > INT_MAX) throw std::runtime_error("Invalid Neo integer argument");
    return int(value);
}
struct Media {
    AVFormatContext *input = nullptr, *output = nullptr;
    AVCodecContext *decoder = nullptr;
    AVPacket *packet = av_packet_alloc(), *result = av_packet_alloc();
    AVFrame *source = av_frame_alloc(), *destination = av_frame_alloc();
    up60p_neo_handle *handle = nullptr;
    ~Media() {
        up60p_neo_destroy(handle);
        av_packet_free(&packet); av_packet_free(&result);
        av_frame_free(&source); av_frame_free(&destination); avcodec_free_context(&decoder);
        avformat_close_input(&input);
        if (output) { if (output->pb) avio_closep(&output->pb); avformat_free_context(output); }
    }
};
static void open(Media &m, const char *path) {
    check(avformat_open_input(&m.input, path, nullptr, nullptr), "Open Neo input");
    check(avformat_find_stream_info(m.input, nullptr), "Read Neo streams");
    if (strcmp(m.input->iformat->name, "nut")) throw std::runtime_error("Neo stage requires an owned NUT intermediate");
    if (!m.packet || !m.result || !m.source || !m.destination) throw std::bad_alloc();
}
static int video(Media &m) {
    int index = -1;
    for (unsigned i = 0; i < m.input->nb_streams; ++i) {
        const auto *p = m.input->streams[i]->codecpar;
        if (p->codec_type == AVMEDIA_TYPE_VIDEO) {
            if (index >= 0 || p->codec_id != AV_CODEC_ID_RAWVIDEO) throw std::runtime_error("Neo requires exactly one rawvideo stream");
            index = int(i);
        } else if (p->codec_type != AVMEDIA_TYPE_AUDIO) throw std::runtime_error("Neo intermediate contains unsupported stream type");
    }
    if (index < 0) throw std::runtime_error("Neo input has no video stream");
    return index;
}
static int probe(const char *input, const char *output) {
    Media m;
    check(avformat_open_input(&m.input, input, nullptr, nullptr), "Probe source color metadata");
    check(avformat_find_stream_info(m.input, nullptr), "Probe source streams");
    int vi = -1;
    for (unsigned i = 0; i < m.input->nb_streams; ++i)
        if (m.input->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) { vi = int(i); break; }
    if (vi < 0) throw std::runtime_error("Probe source has no video stream");
    const auto *p = m.input->streams[vi]->codecpar;
    const auto *format = av_pix_fmt_desc_get(AVPixelFormat(p->format));
    if (!format || format->nb_components != 3 || (format->flags & (AV_PIX_FMT_FLAG_RGB | AV_PIX_FMT_FLAG_ALPHA)))
        throw std::runtime_error("Private genuine Neo pipeline requires a YUV source; RGB/alpha conversion is not yet implemented");
    if (p->field_order != AV_FIELD_UNKNOWN && p->field_order != AV_FIELD_PROGRESSIVE)
        throw std::runtime_error("Private genuine Neo pipeline does not yet carry interlaced field metadata");
    if (p->color_trc == AVCOL_TRC_SMPTE2084 || p->color_trc == AVCOL_TRC_ARIB_STD_B67 ||
        p->nb_coded_side_data > 0) {
        // The split prototype cannot carry HDR or display side data faithfully.
        // Refuse before creating output instead of silently losing it.
        throw std::runtime_error("Private Neo pipeline does not yet support HDR or coded display side data");
    }
    FILE *file = fopen(output, "wx");
    if (!file) throw std::runtime_error("Create owned Neo color metadata file failed");
    const int written = fprintf(file, "1 %d %d %d %d %d\n", p->color_primaries, p->color_trc,
                                p->color_space, p->color_range, p->chroma_location);
    const int closed = fclose(file);
    if (written < 0 || closed) { unlink(output); throw std::runtime_error("Write Neo color metadata failed"); }
    return 0;
}
static void formatOptions(up60p_neo_options &o, const AVCodecParameters *p) {
    const AVPixFmtDescriptor *d = av_pix_fmt_desc_get(AVPixelFormat(p->format));
    if (!d || !(d->flags & AV_PIX_FMT_FLAG_PLANAR) || (d->flags & (AV_PIX_FMT_FLAG_RGB | AV_PIX_FMT_FLAG_FLOAT | AV_PIX_FMT_FLAG_BE)) ||
        d->nb_components != 3 || d->comp[0].plane != 0 || d->comp[1].plane != 1 || d->comp[2].plane != 2 ||
        d->comp[0].shift || d->comp[1].shift || d->comp[2].shift ||
        d->comp[0].depth != d->comp[1].depth || d->comp[0].depth != d->comp[2].depth)
        throw std::runtime_error("Neo requires little-endian, low-aligned planar integer YUV");
    o.width = p->width; o.height = p->height;
    o.input_depth = o.output_depth = d->comp[0].depth;
    o.subsampling_width = d->log2_chroma_w; o.subsampling_height = d->log2_chroma_h;
}
static size_t extent(int stride, int height, int width, int bytes) {
    if (stride <= 0 || stride < width * bytes) throw std::runtime_error("Invalid decoded Neo stride");
    return size_t(stride) * (height - 1) + size_t(width * bytes);
}
static void processFrame(Media &m, const up60p_neo_options &o, int ordinal, int vi) {
    if (m.source->width != o.width || m.source->height != o.height || m.source->format != m.destination->format)
        throw std::runtime_error("Neo frame format changed midstream");
    check(av_frame_make_writable(m.destination), "Neo scratch buffer");
    up60p_neo_source source[3]; up60p_neo_destination destination[3];
    for (int p = 0; p < 3; ++p) {
        int w = o.width >> (p ? o.subsampling_width : 0), h = o.height >> (p ? o.subsampling_height : 0);
        source[p] = {m.source->data[p], extent(m.source->linesize[p], h, w, o.input_depth == 8 ? 1 : 2), m.source->linesize[p]};
        destination[p] = {m.destination->data[p], extent(m.destination->linesize[p], h, w, o.output_depth == 8 ? 1 : 2), m.destination->linesize[p]};
    }
    char error[1024];
    if (up60p_neo_process(m.handle, ordinal, source, destination, cancelled, nullptr, error, sizeof(error))) throw std::runtime_error(error);
    int bytes = av_image_get_buffer_size(AVPixelFormat(m.destination->format), o.width, o.height, 1);
    check(bytes, "Neo image size");
    check(av_new_packet(m.result, bytes), "Neo output packet");
    check(av_image_copy_to_buffer(m.result->data, bytes, m.destination->data, m.destination->linesize,
                                  AVPixelFormat(m.destination->format), o.width, o.height, 1), "Neo pack planes");
    check(av_packet_copy_props(m.result, m.packet), "Neo packet properties");
    m.result->stream_index = vi;
    av_packet_rescale_ts(m.result, m.input->streams[vi]->time_base, m.output->streams[vi]->time_base);
    check(av_interleaved_write_frame(m.output, m.result), "Write Neo video packet");
    av_frame_unref(m.source);
}
int main(int argc, char **argv) {
    bool created = false;
    try {
        signal(SIGTERM, stop); signal(SIGINT, stop);
        if (argc == 4 && !strcmp(argv[1], "--probe")) return probe(argv[2], argv[3]);
        if (argc != 7) throw std::runtime_error("usage: neo-media input.nut output.nut range Y Cb Cr");
        struct stat st;
        if (stat(argv[1], &st) || !S_ISREG(st.st_mode) || st.st_size > 512LL * 1024 * 1024) throw std::runtime_error("Neo intermediate exceeds private 512 MiB bound");
        if (access(argv[2], F_OK) == 0) throw std::runtime_error("Neo output must be a new owned path");
        up60p_neo_options o{};
        o.range = integer(argv[3]); o.y = integer(argv[4]); o.cb = integer(argv[5]); o.cr = integer(argv[6]);
        o.seed = 0; o.sample_mode = 2; o.dither = 3; o.blur_first = 1; o.keep_tv_range = 0;
        Media count; open(count, argv[1]); int vi = video(count); formatOptions(o, count.input->streams[vi]->codecpar);
        int read;
        while ((read = av_read_frame(count.input, count.packet)) >= 0) {
            check(0, "Count Neo frames");
            if (count.packet->stream_index == vi) {
                if (o.frames == 10000000) throw std::runtime_error("Neo frame count exceeds bound");
                ++o.frames;
            }
            av_packet_unref(count.packet);
        }
        if (read != AVERROR_EOF) check(read, "Count Neo packets");
        Media m; open(m, argv[1]); vi = video(m);
        char error[1024];
        if (up60p_neo_create(&o, &m.handle, error, sizeof(error))) throw std::runtime_error(error);
        check(avformat_alloc_output_context2(&m.output, nullptr, "nut", argv[2]), "Create Neo container");
        if (!m.output) throw std::bad_alloc();
        for (unsigned i = 0; i < m.input->nb_streams; ++i) {
            auto *s = avformat_new_stream(m.output, nullptr); if (!s) throw std::bad_alloc();
            auto *original = m.input->streams[i];
            check(avcodec_parameters_copy(s->codecpar, original->codecpar), "Copy Neo codec properties");
            s->time_base = original->time_base; s->avg_frame_rate = original->avg_frame_rate;
            s->sample_aspect_ratio = original->sample_aspect_ratio; s->disposition = original->disposition;
            check(av_dict_copy(&s->metadata, original->metadata, 0), "Copy Neo stream metadata");
        }
        check(av_dict_copy(&m.output->metadata, m.input->metadata, 0), "Copy Neo metadata");
        m.decoder = avcodec_alloc_context3(avcodec_find_decoder(AV_CODEC_ID_RAWVIDEO));
        if (!m.decoder) throw std::bad_alloc();
        check(avcodec_parameters_to_context(m.decoder, m.input->streams[vi]->codecpar), "Neo decoder properties");
        m.decoder->thread_count = 1;
        check(avcodec_open2(m.decoder, nullptr, nullptr), "Open Neo rawvideo decoder");
        m.destination->format = m.input->streams[vi]->codecpar->format;
        m.destination->width = o.width; m.destination->height = o.height;
        check(av_frame_get_buffer(m.destination, 32), "Allocate Neo planar scratch");
        check(avio_open(&m.output->pb, argv[2], AVIO_FLAG_WRITE), "Open Neo output"); created = true;
        check(avformat_write_header(m.output, nullptr), "Write Neo header");
        fprintf(stderr, "Neo F3kdb starting: %d frames; range=%d Y=%d Cb=%d Cr=%d; grain=0.\n",
                o.frames, o.range, o.y, o.cb, o.cr);
        fflush(stderr);
        int ordinal = 0;
        while ((read = av_read_frame(m.input, m.packet)) >= 0) {
            check(0, "Neo processing");
            int index = m.packet->stream_index;
            if (index == vi) {
                check(avcodec_send_packet(m.decoder, m.packet), "Send Neo raw frame");
                check(avcodec_receive_frame(m.decoder, m.source), "Receive Neo raw frame");
                processFrame(m, o, ordinal++, vi);
            } else {
                av_packet_rescale_ts(m.packet, m.input->streams[index]->time_base, m.output->streams[index]->time_base);
                check(av_interleaved_write_frame(m.output, m.packet), "Copy Neo audio packet");
            }
            av_packet_unref(m.packet);
        }
        if (read != AVERROR_EOF) check(read, "Read Neo packets");
        if (ordinal != o.frames) throw std::runtime_error("Neo actual frame count changed");
        check(av_write_trailer(m.output), "Finish Neo container");
        check(avio_closep(&m.output->pb), "Close Neo container");
        fprintf(stderr, "Neo F3kdb: %d frames; %d-bit planar; grain=0; seed=0; actual frame count preserved.\n", ordinal, o.input_depth);
        return 0;
    } catch (const std::exception &e) { fprintf(stderr, "%s: %s\n", stopping ? "CANCELLED" : "ERROR", e.what()); }
      catch (...) { fprintf(stderr, "ERROR: Unknown Neo media failure\n"); }
    if (created) unlink(argv[2]);
    return stopping ? 125 : 1;
}
