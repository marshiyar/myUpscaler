#include "neo_adapter.h"
#include <array>
#include <cstdio>
#include <climits>
#include <stdexcept>
extern double rand_uniform(int &, double);
extern double rand_old(int &, double);
static void require(bool valid) { if (!valid) throw std::runtime_error("Neo arithmetic regression"); }
int main() {
    try {
        int seed=1;
        for (int expected : {1015568748,1586005467,-2129264258}) {
            rand_uniform(seed,1); require(seed==expected);
        }
        seed=1;
        for (int expected : {270369,67634689,-1647531835}) {
            rand_old(seed,1); require(seed==expected);
        }
        for (int frames : {32768,65536,10000000}) for (int initial : {INT_MIN,0,INT_MAX}) {
            up60p_neo_options o{16,16,frames,8,8,0,0,15,128,96,32,initial,2,1,1,0};
            up60p_neo_handle *handle=nullptr; char error[256];
            require(up60p_neo_create(&o,&handle,error,sizeof(error))==0);
            std::array<std::array<uint8_t,256>,3> input{},output{};
            up60p_neo_source source[3];up60p_neo_destination destination[3];
            for(int p=0;p<3;++p) { source[p]={input[p].data(),256,16}; destination[p]={output[p].data(),256,16}; }
            require(up60p_neo_process(handle,frames-1,source,destination,nullptr,nullptr,error,sizeof(error))==0);
            up60p_neo_destroy(handle);
        }
        puts("PASS: fixed LCG/xorshift bit patterns; long counts32768/65536/10000000 and extreme seeds process under UBSan");
        return 0;
    } catch(const std::exception &e) { fprintf(stderr,"%s\n",e.what());return 1; }
}
