// SelacoiOS Milestone 3 platform closure for bounded engine startup.
//
// These functions replace desktop Cocoa/SDL shell behavior with iOS-safe
// equivalents. They do not start input, audio, graphics, scripting, or the
// game loop. Their only current consumer is the local IWAD-recognition probe.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#include "zstring.h"

extern "C" void SelacoIOSReportLicensedAssetProbe(
    const char *phase,
    const char *detail);

namespace {
FString IOSDirectory(NSSearchPathDirectory directory, const char *leaf)
{
    NSString *root = NSSearchPathForDirectoriesInDomains(
        directory, NSUserDomainMask, YES).firstObject;
    if (root.length == 0) {
        return FString();
    }
    if (leaf != nullptr && leaf[0] != '\0') {
        root = [root stringByAppendingPathComponent:
            [NSString stringWithUTF8String:leaf]];
    }
    [[NSFileManager defaultManager] createDirectoryAtPath:root
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return root.fileSystemRepresentation;
}
}

void I_DetectOS()
{
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    NSString *detail = [NSString stringWithFormat:
        @"iOS %ld.%ld.%ld",
        (long)version.majorVersion,
        (long)version.minorVersion,
        (long)version.patchVersion];
    SelacoIOSReportLicensedAssetProbe("ios_os_detected", detail.UTF8String);
}

void I_SetIWADInfo()
{
    SelacoIOSReportLicensedAssetProbe(
        "iwad_info_selected",
        "IWAD metadata accepted without a desktop console title update");
}

void I_ShutdownInput()
{
}

void I_ShutdownGraphics()
{
}

void I_PutInClipboard(const char *text)
{
    if (text == nullptr) {
        UIPasteboard.generalPasteboard.string = @"";
        return;
    }
    UIPasteboard.generalPasteboard.string = [NSString stringWithUTF8String:text];
}

FString I_GetFromClipboard(bool returnNothing)
{
    if (returnNothing) {
        return FString();
    }
    NSString *text = UIPasteboard.generalPasteboard.string;
    return text == nil ? FString() : FString(text.UTF8String);
}

void I_ShowFatalError(const char *message)
{
    SelacoIOSReportLicensedAssetProbe(
        "engine_fatal_error",
        message == nullptr ? "unknown engine error" : message);
}

void I_WriteIniFailed(const char *filename)
{
    NSString *detail = [NSString stringWithFormat:
        @"Unable to write configuration file: %s",
        filename == nullptr ? "unknown" : filename];
    SelacoIOSReportLicensedAssetProbe("ini_write_failed", detail.UTF8String);
}

FString M_GetAutoexecPath()
{
    FString root = IOSDirectory(NSDocumentDirectory, "Selaco");
    return root.IsEmpty() ? root : root + "/autoexec.cfg";
}

void M_GetMacSearchDirectories(
    FString& userDocuments,
    FString& userApplicationSupport,
    FString& localApplicationSupport)
{
    userDocuments = IOSDirectory(NSDocumentDirectory, "Selaco");
    userApplicationSupport = IOSDirectory(NSApplicationSupportDirectory, "Selaco");
    // iOS has no machine-wide writable application-support directory for an
    // app sandbox. Use the per-user container for all three legacy outputs.
    localApplicationSupport = userApplicationSupport;
}
