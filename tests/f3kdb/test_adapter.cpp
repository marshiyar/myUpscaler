#include "neo_adapter.h"
#include "ParameterReference.hpp"
#include <array>
#include <cassert>
#include <iostream>
#include <stdexcept>
#include <thread>

static void need(bool ok, const char *why) { if (!ok) throw std::runtime_error(why); }
static int checks = 0;
static void run(int width, int height, int inDepth, int outDepth, int sw, int sh, int sample, int dither,
                int blur, int tv, int threshold) {
    up60p_neo_options o{width, height, 3, inDepth, outDepth, sw, sh, 15, threshold, threshold/2, threshold/3,
                        0, sample, dither, blur, tv};
    InDelegator parameters;
    parameters.ints = {{"range",o.range},{"y",o.y},{"cb",o.cb},{"cr",o.cr},{"seed",o.seed},
        {"sample_mode",sample},{"dither_algo",dither},{"grainy",0},{"grainc",0},{"output_depth",outDepth},{"opt",0}};
    parameters.bools = {{"blur_first",blur!=0},{"keep_tv_range",tv!=0},{"mt",false}};
    DSVideoInfo vi; vi.Width=width; vi.Height=height; vi.Frames=3;
    vi.Format.BitsPerSample=inDepth; vi.Format.BytesPerSample=inDepth==8?1:2;
    vi.Format.SSW=sw; vi.Format.SSH=sh;
    ParameterReference reference;
    try { reference.Initialize(&parameters,vi); }
    catch (const char *e) { throw std::runtime_error(std::string(e)); }
    char error[1024]; up60p_neo_handle *handle = nullptr;
    need(up60p_neo_create(&o,&handle,error,sizeof(error))==0,error);
    std::unique_ptr<up60p_neo_handle,decltype(&up60p_neo_destroy)> owner(handle,up60p_neo_destroy);
    std::array<std::vector<uint8_t>,3> input, output, expected;
    up60p_neo_source sources[3]; up60p_neo_destination destinations[3];
    for (int p=0;p<3;++p) {
        int w=width>>(p?sw:0), h=height>>(p?sh:0);
        int row=w*(inDepth==8?1:2), outRow=w*(outDepth==8?1:2);
        int stride=((row+15)&~15)+16+p*2, outStride=((outRow+15)&~15)+32+p*2;
        input[p].assign(size_t(stride)*h+128,0xA5); output[p].assign(size_t(outStride)*h+128,0xA5);
        expected[p].resize(size_t(outRow)*h);
        for(int y=0;y<h;++y) for(int x=0;x<w;++x) {
            unsigned value=(32+(x/5)*3+(y/4)*2+p*11) << (inDepth-8);
            auto *a=input[p].data()+y*stride+x*(inDepth==8?1:2);
            a[0]=value&255; if(inDepth>8) a[1]=value>>8;
        }
        sources[p]={input[p].data(),input[p].size(),stride};
        destinations[p]={output[p].data(),output[p].size(),outStride};
    }
    const auto inputSnapshot=input;
    for(int frame : {2,0,1}) {
        need(up60p_neo_process(handle,frame,sources,destinations,nullptr,nullptr,error,sizeof(error))==0,error);
        for(int p=0;p<3;++p) {
            int w=width>>(p?sw:0), h=height>>(p?sh:0), row=w*(outDepth==8?1:2);
            reference.engine->process_plane(frame,p,expected[p].data(),row,sources[p].data,sources[p].stride);
            for(int y=0;y<h;++y) {
                need(!memcmp(expected[p].data()+y*row,output[p].data()+y*destinations[p].stride,row),"Reference pixel mismatch");
                for(int x=row;x<destinations[p].stride;++x) need(output[p][y*destinations[p].stride+x]==0xA5,"Padding changed");
            }
            for(size_t i=size_t(h)*destinations[p].stride;i<output[p].size();++i) need(output[p][i]==0xA5,"Guard changed");
        }
    }
    need(input==inputSnapshot,"Source mutated");
    auto before=output;
    auto shortSources=std::array<up60p_neo_source,3>{sources[0],sources[1],sources[2]}; shortSources[2].capacity=1;
    need(up60p_neo_process(handle,0,shortSources.data(),destinations,nullptr,nullptr,error,sizeof(error))==UP60P_NEO_INVALID,"Short buffer accepted");
    need(before==output,"Invalid frame partially written");
    need(up60p_neo_process(handle,-1,sources,destinations,nullptr,nullptr,error,sizeof(error))==UP60P_NEO_INVALID,"Negative frame accepted");
    need(up60p_neo_process(handle,3,sources,destinations,nullptr,nullptr,error,sizeof(error))==UP60P_NEO_INVALID,"Out-of-range frame accepted");
    auto overlapDestination=std::array<up60p_neo_destination,3>{destinations[0],destinations[1],destinations[2]};
    overlapDestination[1].data=const_cast<uint8_t *>(sources[0].data);
    need(up60p_neo_process(handle,0,sources,overlapDestination.data(),nullptr,nullptr,error,sizeof(error))==UP60P_NEO_INVALID,"Overlap accepted");
    auto cancelled=[](void*){return 1;};
    need(up60p_neo_process(handle,0,sources,destinations,cancelled,nullptr,error,sizeof(error))==UP60P_NEO_CANCELLED,"Cancellation ignored");
    need(before==output,"Before-frame cancellation wrote output");
    ++checks;
}
int main() {
    try {
        for(int depth : {8,10,16}) for(int out : {8,10,16}) for(int sw : {0,1}) for(int sh : {0,1})
            for(int sample : {1,2,7}) run(66,34,depth,out,sw,sh,sample,3,1,0,128);
        for(int sample=1;sample<=7;++sample) for(int dither=1;dither<=3;++dither)
            run(65,33,10,8,0,0,sample,dither,0,1,96);
        for(int depth : {8,10,16}) run(65,33,depth,depth,0,0,2,3,1,0,0);
        up60p_neo_options o{66,34,3,10,10,1,1,15,128,96,32,0,2,3,1,0};
        char error[128]; up60p_neo_handle *handle=nullptr;
        for(int kind=0;kind<10;++kind) {
            auto bad=o;
            switch(kind) {
                case 0:bad.y=-1;break; case 1:bad.cb=512;break; case 2:bad.sample_mode=0;break;
                case 3:bad.dither=5;break; case 4:bad.width=15;break; case 5:bad.frames=0;break;
                case 6:bad.width=65;break; case 7:bad.input_depth=12;break; case 8:bad.blur_first=2;break;
                case 9:bad.dither=4;break;
            }
            need(up60p_neo_create(&bad,&handle,error,sizeof(error))==UP60P_NEO_INVALID && !handle && error[0],"Invalid options accepted");
        }
        std::thread a([]{run(66,34,8,8,1,1,2,3,1,0,64);});
        a.join(); // Creation/destruction on an independent worker, no shared core.
        std::cout << checks << " reference parity/layout cases and 10 invalid-create cases passed\n";
        return 0;
    } catch(const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
