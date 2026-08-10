#!/usr/bin/env python3
"""Add the bounded Milestone 3 local licensed-asset recognition probe."""

from __future__ import annotations

import pathlib
import sys


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{description}: expected one exact match in {path}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: patch-gzselaco-local-asset-ios-m3.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    runtime_source = (
        root
        / "src"
        / "common"
        / "platform"
        / "ios"
        / "i_platform_runtime.mm"
    )
    d_main = root / "src" / "d_main.cpp"

    for path in (src_cmake, runtime_source, d_main):
        if not path.is_file():
            raise RuntimeError(f"Milestone 3 prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.swapchain.m2"',
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.localasset.m3"',
        "assign the Milestone 3 bundle identifier",
    )
    replace_once(
        src_cmake,
        '\ttarget_link_libraries(zdoom "${MOLTENVK_DYNAMIC_BINARY}")\n',
        '\ttarget_link_libraries(zdoom "${MOLTENVK_DYNAMIC_BINARY}")\n'
        '\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_LOCAL_ASSET_PROBE=1)\n',
        "enable the bounded local-asset engine probe",
    )

    replace_once(
        runtime_source,
        '#include <dlfcn.h>\n',
        '#include <dlfcn.h>\n#include <CommonCrypto/CommonDigest.h>\n#include <unistd.h>\n',
        "include local file hashing and process-path APIs",
    )
    replace_once(
        runtime_source,
        '#include "zstring.h"\n',
        '#include "zstring.h"\n\n'
        'extern int GameMain();\n'
        'extern FString progdir;\n'
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n',
        "declare the real engine entry point and probe reporter",
    )

    helper_marker = 'void UncaughtExceptionHandler(NSException *exception)\n'
    helper_block = r'''NSString * const kLicensedAssetProbeNotification = @"SelacoIOSLicensedAssetProbeStatus";

NSString *FindLicensedAssetPath()
{
    NSString *directory = DiagnosticDirectory();
    if (directory == nil) {
        return nil;
    }

    NSString *preferred = [directory stringByAppendingPathComponent:@"Selaco.ipk3"];
    if ([[NSFileManager defaultManager] isReadableFileAtPath:preferred]) {
        return preferred;
    }

    NSArray<NSString *> *entries = [[NSFileManager defaultManager]
        contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *entry in entries) {
        if ([entry.pathExtension caseInsensitiveCompare:@"ipk3"] == NSOrderedSame) {
            NSString *candidate = [directory stringByAppendingPathComponent:entry];
            if ([[NSFileManager defaultManager] isReadableFileAtPath:candidate]) {
                return candidate;
            }
        }
    }
    return nil;
}

NSString *SHA256ForFile(NSString *path)
{
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        return nil;
    }

    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    while (true) {
        @autoreleasepool {
            NSData *chunk = [handle readDataOfLength:1024 * 1024];
            if (chunk.length == 0) {
                break;
            }
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    }
    [handle closeFile];

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (unsigned char byte : digest) {
        [hex appendFormat:@"%02x", byte];
    }
    return hex;
}

bool HasZipSignature(NSString *path)
{
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (handle == nil) {
        return false;
    }
    NSData *prefix = [handle readDataOfLength:4];
    [handle closeFile];
    if (prefix.length != 4) {
        return false;
    }
    const unsigned char *bytes = static_cast<const unsigned char *>(prefix.bytes);
    return bytes[0] == 'P' && bytes[1] == 'K' &&
        ((bytes[2] == 3 && bytes[3] == 4) ||
         (bytes[2] == 5 && bytes[3] == 6) ||
         (bytes[2] == 7 && bytes[3] == 8));
}

void RunLicensedAssetProbe()
{
    @autoreleasepool {
        NSString *assetPath = FindLicensedAssetPath();
        if (assetPath == nil) {
            SelacoIOSReportLicensedAssetProbe(
                "asset_missing",
                "Copy Selaco.ipk3 to Files > On My iPhone > SelacoiOS Local Asset > Selaco");
            return;
        }

        NSDictionary *attributes = [[NSFileManager defaultManager]
            attributesOfItemAtPath:assetPath error:nil];
        unsigned long long fileSize = [attributes fileSize];
        if (fileSize == 0 || !HasZipSignature(assetPath)) {
            SelacoIOSReportLicensedAssetProbe(
                "asset_invalid",
                "The local .ipk3 is unreadable, empty, or lacks a ZIP/IPK3 signature");
            return;
        }

        NSString *sha256 = SHA256ForFile(assetPath);
        NSString *identity = [NSString stringWithFormat:
            @"file=%@ size=%llu sha256=%@",
            assetPath.lastPathComponent,
            fileSize,
            sha256 ?: @"unavailable"];
        SelacoIOSReportLicensedAssetProbe("asset_validated", identity.UTF8String);

        NSString *bundlePath = NSBundle.mainBundle.bundlePath;
        NSString *baseArchive = [bundlePath stringByAppendingPathComponent:@"gzdoom.pk3"];
        if (![[NSFileManager defaultManager] isReadableFileAtPath:baseArchive]) {
            SelacoIOSReportLicensedAssetProbe(
                "public_support_missing",
                "The IPA lacks its generated public gzdoom.pk3 support archive");
            return;
        }

        [[NSFileManager defaultManager] changeCurrentDirectoryPath:bundlePath];
        NSString *programDirectory = [bundlePath stringByAppendingString:@"/"];
        progdir = programDirectory.fileSystemRepresentation;

        std::vector<std::string> arguments = {
            NSBundle.mainBundle.executablePath.fileSystemRepresentation,
            "-iwad",
            assetPath.fileSystemRepresentation,
            "-noautoload",
            "-noautoexec",
            "-nosound",
            "-nomusic",
        };
        std::vector<char *> argv;
        argv.reserve(arguments.size());
        for (std::string& argument : arguments) {
            argv.push_back(argument.data());
        }

        Args = new FArgs(static_cast<int>(argv.size()), argv.data());
        SelacoIOSReportLicensedAssetProbe(
            "engine_probe_starting",
            "Calling the real GZSelaco GameMain through IWAD recognition only");
        const int result = GameMain();
        if (Args != nullptr) {
            delete Args;
            Args = nullptr;
        }

        NSString *completion = [NSString stringWithFormat:@"GameMain returned bounded probe code %d", result];
        SelacoIOSReportLicensedAssetProbe(
            result == 73 ? "engine_iwad_recognized" : "engine_probe_returned",
            completion.UTF8String);
    }
}

'''
    replace_once(
        runtime_source,
        helper_marker,
        helper_block + helper_marker,
        "install local asset validation and engine-launch helpers",
    )

    replace_once(
        runtime_source,
        '} // namespace\n\nvoid CalculateCPUSpeed()\n',
        '} // namespace\n\n'
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail)\n'
        '{\n'
        '    NSString *phaseText = phase == nullptr ? @"unknown" : [NSString stringWithUTF8String:phase];\n'
        '    NSString *detailText = detail == nullptr ? @"" : [NSString stringWithUTF8String:detail];\n'
        '    NSString *line = [NSString stringWithFormat:@"phase=m3_%@ %@", phaseText, detailText];\n'
        '    WriteBreadcrumb(line);\n'
        '    NSString *path = DiagnosticPath(@"licensed-asset-status.txt");\n'
        '    if (path != nil) {\n'
        '        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];\n'
        '    }\n'
        '    dispatch_async(dispatch_get_main_queue(), ^{\n'
        '        [[NSNotificationCenter defaultCenter] postNotificationName:kLicensedAssetProbeNotification\n'
        '                                                            object:nil\n'
        '                                                          userInfo:@{@"text": line}];\n'
        '    });\n'
        '}\n\n'
        'void CalculateCPUSpeed()\n',
        "expose the engine-to-UIKit asset probe reporter",
    )

    replace_once(
        runtime_source,
        '@property(nonatomic, assign) BOOL initializationStarted;\n',
        '@property(nonatomic, assign) BOOL initializationStarted;\n'
        '@property(nonatomic, assign) BOOL assetProbeStarted;\n'
        '@property(nonatomic, strong) NSString *assetStatusText;\n',
        "add licensed-asset UI state",
    )
    runtime_text = runtime_source.read_text(encoding="utf-8")
    runtime_text = runtime_text.replace("SelacoiOS Milestone 2", "SelacoiOS Milestone 3")
    runtime_source.write_text(runtime_text, encoding="utf-8")

    replace_once(
        runtime_source,
        'NSString *text = StatusText(_presenter->Status());',
        'NSString *text = [self combinedStatusText:_presenter->Status()];',
        "combine initial swapchain and asset status",
    )
    replace_once(
        runtime_source,
        'NSString *text = StatusText(_presenter->Status());',
        'NSString *text = [self combinedStatusText:_presenter->Status()];',
        "combine initialized swapchain and asset status",
    )
    replace_once(
        runtime_source,
        'NSString *text = StatusText(status);',
        'NSString *text = [self combinedStatusText:status];',
        "combine recurring swapchain and asset status",
    )

    replace_once(
        runtime_source,
        '            WriteBreadcrumb(@"phase=m2_display_link_started");\n\n'
        '            [[NSNotificationCenter defaultCenter]\n',
        '            WriteBreadcrumb(@"phase=m2_display_link_started");\n'
        '            self.assetStatusText = @"Licensed asset: checking Documents/Selaco/Selaco.ipk3…";\n'
        '            [[NSNotificationCenter defaultCenter]\n'
        '                addObserver:self\n'
        '                   selector:@selector(licensedAssetProbeStatus:)\n'
        '                       name:kLicensedAssetProbeNotification\n'
        '                     object:nil];\n'
        '            if (!self.assetProbeStarted) {\n'
        '                self.assetProbeStarted = YES;\n'
        '                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{\n'
        '                    RunLicensedAssetProbe();\n'
        '                });\n'
        '            }\n\n'
        '            [[NSNotificationCenter defaultCenter]\n',
        "start the local asset probe after swapchain presentation is stable",
    )

    replace_once(
        runtime_source,
        '- (void)renderFrame:(CADisplayLink *)displayLink\n',
        '- (NSString *)combinedStatusText:(const SwapchainStatus&)status\n'
        '{\n'
        '    NSString *base = StatusText(status);\n'
        '    NSString *asset = self.assetStatusText ?: @"Licensed asset probe: pending";\n'
        '    return [NSString stringWithFormat:@"%@\\n\\n%@", base, asset];\n'
        '}\n\n'
        '- (void)licensedAssetProbeStatus:(NSNotification *)notification\n'
        '{\n'
        '    NSString *text = notification.userInfo[@"text"];\n'
        '    if (text.length > 0) {\n'
        '        self.assetStatusText = text;\n'
        '        if (_presenter) {\n'
        '            NSString *combined = [self combinedStatusText:_presenter->Status()];\n'
        '            self.statusLabel.text = combined;\n'
        '            WriteStatusSnapshot(combined);\n'
        '        }\n'
        '    }\n'
        '}\n\n'
        '- (void)renderFrame:(CADisplayLink *)displayLink\n',
        "add combined swapchain and licensed-asset status rendering",
    )

    replace_once(
        d_main,
        'void Local_Job_Init();\n',
        'void Local_Job_Init();\n'
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n'
        '#endif\n',
        "declare the iOS licensed-asset probe reporter in the engine",
    )
    replace_once(
        d_main,
        '\tD_DoomInit();\n\t\n\t// [RH] Make sure zdoom.pk3 is always loaded,\n',
        '\tD_DoomInit();\n'
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("doom_init_passed", "engine command line and core startup initialized");\n'
        '#endif\n\t\n\t// [RH] Make sure zdoom.pk3 is always loaded,\n',
        "record core startup before public support archive lookup",
    )
    replace_once(
        d_main,
        '\tLoadHexFont(wad);\t// load hex font early so we have it during startup.\n',
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("public_support_loaded", wad);\n'
        '#endif\n'
        '\tLoadHexFont(wad);\t// load hex font early so we have it during startup.\n',
        "record public gzdoom.pk3 recognition",
    )
    replace_once(
        d_main,
        '\t\tconst FIWADInfo *iwad_info = iwad_man->FindIWAD(allwads, iwad.GetChars(), basewad.GetChars(), optionalwad.GetChars());\n\n'
        '\t\tGetCmdLineFiles(pwads); // [RL0] Update with files passed on the launcher extra args\n\n'
        '\t\tif (!iwad_info) return 0;\t// user exited the selection popup via cancel button.\n',
        '\t\tconst FIWADInfo *iwad_info = iwad_man->FindIWAD(allwads, iwad.GetChars(), basewad.GetChars(), optionalwad.GetChars());\n\n'
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\t\tif (!iwad_info)\n'
        '\t\t{\n'
        '\t\t\tSelacoIOSReportLicensedAssetProbe("iwad_not_recognized", iwad.GetChars());\n'
        '\t\t\treturn 74;\n'
        '\t\t}\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("iwad_recognized", iwad.GetChars());\n'
        '\t\treturn 73;\n'
        '#endif\n\n'
        '\t\tGetCmdLineFiles(pwads); // [RL0] Update with files passed on the launcher extra args\n\n'
        '\t\tif (!iwad_info) return 0;\t// user exited the selection popup via cancel button.\n',
        "stop after the real IWAD manager classifies the local archive",
    )
    replace_once(
        d_main,
        '\t// Unless something really bad happened, the game should only exit through this single point in the code.\n',
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\tif (ret == 73 || ret == 74) return ret;\n'
        '#endif\n'
        '\t// Unless something really bad happened, the game should only exit through this single point in the code.\n',
        "avoid full teardown after the deliberately bounded pre-game probe",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
