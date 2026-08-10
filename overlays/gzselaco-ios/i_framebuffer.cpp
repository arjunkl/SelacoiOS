#include "gl_sysfb.h"

#include <algorithm>
#include <atomic>

namespace
{
std::atomic<int> gDrawableWidth{1};
std::atomic<int> gDrawableHeight{1};
std::atomic<bool> gFullscreen{true};
}

extern "C" void SelacoIOSSetDrawableSize(int width, int height)
{
    gDrawableWidth.store(std::max(width, 1), std::memory_order_relaxed);
    gDrawableHeight.store(std::max(height, 1), std::memory_order_relaxed);
}

SystemBaseFrameBuffer::SystemBaseFrameBuffer(void *, bool fullscreen)
    : DFrameBuffer(gDrawableWidth.load(std::memory_order_relaxed),
                   gDrawableHeight.load(std::memory_order_relaxed))
{
    gFullscreen.store(fullscreen, std::memory_order_relaxed);
}

bool SystemBaseFrameBuffer::IsFullscreen()
{
    return gFullscreen.load(std::memory_order_relaxed);
}

int SystemBaseFrameBuffer::GetClientWidth()
{
    return gDrawableWidth.load(std::memory_order_relaxed);
}

int SystemBaseFrameBuffer::GetClientHeight()
{
    return gDrawableHeight.load(std::memory_order_relaxed);
}

void SystemBaseFrameBuffer::ToggleFullscreen(bool yes)
{
    // iPhone applications always own the full drawable. Preserve the engine
    // state request without attempting desktop window-mode transitions.
    gFullscreen.store(yes, std::memory_order_relaxed);
}

void SystemBaseFrameBuffer::SetWindowSize(int clientWidth, int clientHeight)
{
    SelacoIOSSetDrawableSize(clientWidth, clientHeight);
    SetSize(GetClientWidth(), GetClientHeight());
}

SystemGLFrameBuffer::SystemGLFrameBuffer(void *monitor, bool fullscreen)
    : SystemBaseFrameBuffer(monitor, fullscreen)
{
}

void SystemGLFrameBuffer::SetVSync(bool)
{
}

void SystemGLFrameBuffer::SwapBuffers()
{
}

void SystemGLFrameBuffer::setNULLContext()
{
}

bool SystemGLFrameBuffer::setMainContext()
{
    return false;
}

bool SystemGLFrameBuffer::setAuxContext(int)
{
    return false;
}

int SystemGLFrameBuffer::createAuxContext()
{
    return -1;
}

int SystemGLFrameBuffer::numAuxContexts()
{
    return 0;
}
