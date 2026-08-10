#pragma once

#include "v_video.h"

// Publish the current UIKit/Metal drawable size to the engine-facing
// framebuffer contract. The platform shell will own the actual CAMetalLayer.
extern "C" void SelacoIOSSetDrawableSize(int width, int height);

class SystemBaseFrameBuffer : public DFrameBuffer
{
    using Super = DFrameBuffer;

public:
    SystemBaseFrameBuffer(void *monitor, bool fullscreen);

    bool IsFullscreen() override;
    int GetClientWidth() override;
    int GetClientHeight() override;
    void ToggleFullscreen(bool yes) override;
    void SetWindowSize(int clientWidth, int clientHeight) override;

protected:
    SystemBaseFrameBuffer() : DFrameBuffer(1, 1) {}
};

// GZSelaco compiles shared OpenGL renderer declarations even when Vulkan is
// selected. This no-context class satisfies that compile-time contract without
// importing SDL, Cocoa, or a pretend OpenGL implementation into the iOS port.
class SystemGLFrameBuffer : public SystemBaseFrameBuffer
{
    using Super = SystemBaseFrameBuffer;

public:
    SystemGLFrameBuffer() = default;
    SystemGLFrameBuffer(void *monitor, bool fullscreen);
    ~SystemGLFrameBuffer() override = default;

    void SetVSync(bool vsync) override;
    void SwapBuffers();
    void setNULLContext();
    bool setMainContext();
    bool setAuxContext(int index);
    int createAuxContext();
    int numAuxContexts();
};
