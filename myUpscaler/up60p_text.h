#ifndef UP60_HELPER_TEXT_H
#define UP60_HELPER_TEXT_H

// MARK: - HELPER TEXT CLI, TUI

static const char *HELP_TEXT =
"%s v4.9 — The Ultimate AI Restoration Pipeline\n"
"\n"
"USAGE:\n"
"  ./%s <input> [options]\n"
"  ./%s --settings\n"
"\n"
"CODEC / RATE CONTROL:\n"
"  --hevc                   Use HEVC/H.265 (default: H.264)\n"
"  --crf <0-51>             Constant Rate Factor (default 16)\n"
"  --preset <name>          Encoder preset (default fast)\n"
"  --10bit                  Output yuv420p10le (or p010le for HW)\n"
"  --x265-params <str>      Pass args to x265 (e.g. 'aq-mode=3:psy-rd=2.0')\n"
"\n"
"FRAME / SCALE:\n"
"  --fps <1-240|source>     Target FPS (default: 60). Use 'source' to lock FPS.\n"
"  --scale <0.1-10>         Upscale factor (default: 2).\n"
"  --mi-mode <mci|blend>    Interpolation method (default: mci)\n"
"\n"
"AI UPSCALING:\n"
"  --scaler <ai|lanczos|zscale|hw> Select upscaler (default: ai)\n"
"  --ai-backend <sr|dnn>    AI filter choice (default: sr).\n"
"  --ai-model <file>        Path to model (.pb/.model). Required for --scaler ai.\n"
"  --dnn-backend <name>     native|tensorflow|openvino\n"
"\n"
"FILTERS (Denoise/Deblock/Sharpen):\n"
"  --denoiser <bm3d|nlmeans|hqdn3d|atadenoise> (default: bm3d)\n"
"  --denoise-strength <f|auto>  Sigma value or 'auto' (default: 2.5)\n"
"  --dering                 Enable ringing artifact removal\n"
"  --sharpen-method <cas|unsharp>\n"
"  --usm-radius <3-23>      Unsharp Mask Radius (default: 5)\n"
"  --deband-method <deband|gradfun|f3kdb>\n"
"  --f3kdb-range <1-50>     F3KDB Range (default: 15)\n"
"\n"
"COLOR / I/O:\n"
//"  --lut <file>             Path to .cube 3D LUT\n" // LUT DEACTIVATED
"  --movflags <flags>       MOV container flags (default: +faststart)\n"
"  --preview                Enable Live View window during processing\n"
"  --pci-safe               Force yuv420p 8-bit for compatibility\n"
"\n"
"SETTINGS MODE:\n"
"  --settings               Launch interactive menu.\n";

// MARK:  HELPER TEXT CLI  END -

static const char *MANUAL_TEXT = "Refer to interactive settings for full documentation.\n";



#endif
