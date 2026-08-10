#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int SelacoIOSVulkanSelfTest(void);
int SelacoIOSVulkanSurfaceSelfTest(void *metal_layer);
unsigned int SelacoIOSVulkanCompiledVersion(void);

#ifdef __cplusplus
}
#endif
