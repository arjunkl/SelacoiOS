// Bounded SelacoiOS native-platform runtime closure for Milestone 0.
//
// This file provides iOS-safe process, path, timing, console, and inert input
// hooks required to link the complete GZSelaco target. UIKit event delivery and
// Vulkan video creation remain separate runtime gates.

#import <Foundation/Foundation.h>

#include <cstdio>
#include <mach/mach_time.h>

#include "cmdlib.h"
#include "i_system.h"
#include "i_video.h"
#include "m_argv.h"
#include "tarray.h"
#include "zstring.h"

class FGameTexture;

FArgs *Args = nullptr;
IVideo *Video = nullptr;

double PerfToSec = 1.0e-9;
double PerfToMillisec = 1.0e-6;

namespace {
FString PathForDirectory(NSSearchPathDirectory directory, const char *leaf, bool create)
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        directory, NSUserDomainMask, YES);
    if (paths.count == 0) {
        return FString();
    }

    NSString *path = paths.firstObject;
    if (leaf != nullptr && leaf[0] != '\0') {
        path = [path stringByAppendingPathComponent:
            [NSString stringWithUTF8String:leaf]];
    }

    if (create) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if (error != nil) {
            std::fprintf(stderr, "SelacoiOS: unable to create %s: %s\n",
                path.fileSystemRepresentation,
                error.localizedDescription.UTF8String);
        }
    }

    return path.fileSystemRepresentation;
}

FString AppSupportPath(bool create)
{
    return PathForDirectory(NSApplicationSupportDirectory, "Selaco", create);
}

FString DocumentsPath(const char *leaf, bool create)
{
    FString root = PathForDirectory(NSDocumentDirectory, "Selaco", create);
    if (root.IsEmpty() || leaf == nullptr || leaf[0] == '\0') {
        return root;
    }

    NSString *rootString = [NSString stringWithUTF8String:root.GetChars()];
    NSString *path = [rootString stringByAppendingPathComponent:
        [NSString stringWithUTF8String:leaf]];
    if (create) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return path.fileSystemRepresentation;
}
} // namespace

void CalculateCPUSpeed()
{
#if defined(__aarch64__)
    uint64_t frequency = 0;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(frequency));
    if (frequency != 0) {
        PerfToSec = 1.0 / static_cast<double>(frequency);
        PerfToMillisec = 1000.0 / static_cast<double>(frequency);
    }
#else
    mach_timebase_info_data_t timebase{};
    if (mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.denom != 0) {
        const double nanosecondsPerTick =
            static_cast<double>(timebase.numer) / static_cast<double>(timebase.denom);
        PerfToSec = nanosecondsPerTick * 1.0e-9;
        PerfToMillisec = nanosecondsPerTick * 1.0e-6;
    }
#endif
}

void I_GetEvent() {}
void I_SetMouseCapture() {}
void I_ReleaseMouseCapture() {}
void I_LockMouseToWindow() {}
void I_UnlockMouseFromWindow() {}
void I_SetWindowTitle(const char *) {}
void I_OpenShellFolder(const char *) {}

bool I_SetCursor(FGameTexture *)
{
    return false;
}

void I_PrintStr(const char *message)
{
    if (message == nullptr) {
        return;
    }
    std::fputs(message, stdout);
    std::fflush(stdout);
}

FString I_GetCWD()
{
    NSString *path = [NSFileManager defaultManager].currentDirectoryPath;
    return path.fileSystemRepresentation;
}

FString M_GetAppDataPath(bool create)
{
    return AppSupportPath(create);
}

FString M_GetCachePath(bool create)
{
    return PathForDirectory(NSCachesDirectory, "Selaco", create);
}

FString M_GetConfigPath(bool)
{
    FString root = AppSupportPath(true);
    return root + "/selaco.ini";
}

FString M_GetDocumentsPath()
{
    return DocumentsPath(nullptr, true);
}

FString M_GetSavegamesPath()
{
    return DocumentsPath("Savegames", true);
}

void M_GetSavegamesPaths(TArray<FString>& paths)
{
    paths.Push(M_GetSavegamesPath());
}

FString M_GetScreenshotsPath()
{
    return DocumentsPath("Screenshots", true);
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        static FArgs processArgs(argc, argv);
        Args = &processArgs;
        CalculateCPUSpeed();
        return 0;
    }
}
