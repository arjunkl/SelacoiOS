// SelacoiOS Milestone 4A engine-initialization boundary.
//
// The diagnostic UIKit/CAMetalLayer Vulkan presenter remains the sole Vulkan
// owner. The real engine may initialize resources up to, but not including,
// V_Init2(), where GZSelaco would create its own renderer and framebuffer.

#include <stdlib.h>

extern "C" const char *SelacoIOSM4RendererStrategy()
{
    return "M4A stop-before-renderer: diagnostic presenter remains sole Vulkan owner; engine stops immediately before V_Init2";
}

unsigned int I_MakeRNGSeed()
{
    unsigned int seed = 0;
    arc4random_buf(&seed, sizeof(seed));
    return seed;
}
