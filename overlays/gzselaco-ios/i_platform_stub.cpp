// Milestone 0 source-selection boundary only.
//
// This file proves that the full GZSelaco target selects a dedicated iOS
// platform source set instead of the desktop Cocoa or SDL implementations.
// UIKit lifecycle, input, audio interruption handling, and presentation remain
// owned by later gated work.

extern "C" int SelacoIOSPlatformSourceSelectionBoundary(void)
{
    return 0x53454C41;
}
