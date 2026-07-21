// SelacoiOS Milestone 4C title/menu platform closure.
//
// This file intentionally provides only the inert input and optional-feature
// boundaries needed to display the first engine-owned title/menu frame. It does
// not implement gameplay controls, VR, statistics networking, or audio.

#include <cstddef>

#include "c_cvars.h"
#include "i_joystick.h"
#include "m_joy.h"
#include "tarray.h"

extern void I_GetEvent();

extern "C" const char *SelacoIOSM4CTitleMenuClosure()
{
    return "M4C title/menu closure: inert input, VR disabled, stats RPC disabled, native startup window bypassed, Vulkan renderer retained";
}

void I_StartTic()
{
    // UIKit input translation is outside M4C. Keep the event pump contract alive
    // so the engine loop can advance without inventing gameplay input.
    I_GetEvent();
}

void I_StartFrame()
{
}

IJoystickConfig *I_UpdateDeviceList()
{
    return nullptr;
}

void I_GetJoysticks(TArray<IJoystickConfig *> &sticks)
{
    sticks.Clear();
}

void I_GetAxes(float axes[NUM_JOYAXIS])
{
    for (int index = 0; index < NUM_JOYAXIS; ++index) {
        axes[index] = 0.0f;
    }
}

void UpdateVRModes(bool)
{
    // VR is explicitly unavailable in the title/menu-only iOS closure.
}

// These renderer settings are consumed by the Vulkan backend even though their
// historical definitions live in desktop OpenGL source units excluded on iOS.
CVAR(Int, gl_dither_bpc, 0, CVAR_ARCHIVE | CVAR_GLOBALCONFIG | CVAR_NOINITCALL)
CVAR(Int, gl_multisample, 1, CVAR_ARCHIVE | CVAR_GLOBALCONFIG | CVAR_NOINITCALL)
