#!/usr/bin/env python3
"""Capture private on-device ZScript diagnostics after the retained class registry."""

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
            "usage: patch-gzselaco-zscript-diagnostics-ios-m4e.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    runtime = (
        root
        / "src"
        / "common"
        / "platform"
        / "ios"
        / "i_platform_runtime.mm"
    )
    d_main = root / "src" / "d_main.cpp"

    for path in (src_cmake, runtime, d_main):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4E prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_MACH_CLASS_REGISTRY=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_MACH_CLASS_REGISTRY=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ZSCRIPT_DIAGNOSTICS=1)\n",
        "enable private on-device ZScript diagnostic capture",
    )

    replace_once(
        runtime,
        "#include <memory>\n",
        "#include <memory>\n#include <mutex>\n",
        "include synchronization for the console diagnostic sink",
    )
    replace_once(
        runtime,
        '#include "zstring.h"\n',
        '#include "zstring.h"\n#include "v_text.h"\n',
        "include GZDoom text-colour definitions",
    )

    helper_marker = "void UncaughtExceptionHandler(NSException *exception)\n"
    helper_block = r'''std::mutex gEngineConsoleLogMutex;

std::string StripEngineConsoleColors(const char *message)
{
    std::string plain;
    if (message == nullptr) {
        return plain;
    }

    const unsigned char *cursor =
        reinterpret_cast<const unsigned char *>(message);
    while (*cursor != 0) {
        if (*cursor != static_cast<unsigned char>(TEXTCOLOR_ESCAPE)) {
            plain.push_back(static_cast<char>(*cursor++));
        } else if (cursor[1] == '[') {
            cursor += 2;
            while (*cursor != 0 && *cursor != ']') {
                ++cursor;
            }
            if (*cursor == ']') {
                ++cursor;
            }
        } else if (cursor[1] != 0) {
            cursor += 2;
        } else {
            break;
        }
    }
    return plain;
}

void ResetEngineConsoleLog()
{
    std::lock_guard<std::mutex> lock(gEngineConsoleLogMutex);
    NSString *path = DiagnosticPath(@"zscript-compile.log");
    if (path == nil) {
        return;
    }
    [@"SelacoiOS M4E engine console and ZScript diagnostics\n"
        writeToFile:path
          atomically:YES
            encoding:NSUTF8StringEncoding
               error:nil];
}

void AppendEngineConsoleLog(const char *message)
{
    const std::string plain = StripEngineConsoleColors(message);
    if (plain.empty()) {
        return;
    }

    std::lock_guard<std::mutex> lock(gEngineConsoleLogMutex);
    NSString *path = DiagnosticPath(@"zscript-compile.log");
    if (path == nil) {
        return;
    }
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        [@"SelacoiOS M4E engine console and ZScript diagnostics\n"
            writeToFile:path
              atomically:YES
                encoding:NSUTF8StringEncoding
                   error:nil];
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (handle == nil) {
        return;
    }
    NSData *data = [NSData dataWithBytes:plain.data() length:plain.size()];
    [handle seekToEndOfFile];
    [handle writeData:data];
    [handle synchronizeFile];
    [handle closeFile];
}

NSString *EngineConsoleLogTail(NSUInteger maximumLines)
{
    std::lock_guard<std::mutex> lock(gEngineConsoleLogMutex);
    NSString *path = DiagnosticPath(@"zscript-compile.log");
    NSString *contents = path == nil
        ? nil
        : [NSString stringWithContentsOfFile:path
                                    encoding:NSUTF8StringEncoding
                                       error:nil];
    if (contents.length == 0) {
        return @"zscript-compile.log contains no captured console output";
    }

    NSArray<NSString *> *lines = [contents componentsSeparatedByCharactersInSet:
        NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *nonempty = [NSMutableArray array];
    for (NSString *line in lines) {
        if (line.length > 0) {
            [nonempty addObject:line];
        }
    }
    const NSUInteger count = nonempty.count;
    const NSUInteger start = count > maximumLines ? count - maximumLines : 0;
    return [[nonempty subarrayWithRange:NSMakeRange(start, count - start)]
        componentsJoinedByString:@"\n"];
}

'''
    replace_once(
        runtime,
        helper_marker,
        helper_block + helper_marker,
        "install the private engine-console diagnostic sink",
    )

    replace_once(
        runtime,
        "void I_PrintStr(const char *message)\n"
        "{\n"
        "    if (message != nullptr) {\n"
        "        std::fputs(message, stdout);\n"
        "        std::fflush(stdout);\n"
        "    }\n"
        "}\n",
        "void I_PrintStr(const char *message)\n"
        "{\n"
        "    if (message != nullptr) {\n"
        "#if defined(SELACO_IOS_ZSCRIPT_DIAGNOSTICS)\n"
        "        AppendEngineConsoleLog(message);\n"
        "#endif\n"
        "        std::fputs(message, stdout);\n"
        "        std::fflush(stdout);\n"
        "    }\n"
        "}\n",
        "mirror GZDoom console output into the on-device diagnostic file",
    )

    replace_once(
        runtime,
        "        const int result = GameMain();\n",
        "#if defined(SELACO_IOS_ZSCRIPT_DIAGNOSTICS)\n"
        "        ResetEngineConsoleLog();\n"
        "        SelacoIOSReportLicensedAssetProbe(\n"
        "            \"zscript_diagnostics_ready\",\n"
        "            \"capturing colour-stripped console output in zscript-compile.log\");\n"
        "#endif\n"
        "        const int result = GameMain();\n",
        "reset the ZScript diagnostic log immediately before GameMain",
    )

    replace_once(
        runtime,
        "        if ([text containsString:@\"phase=m4_engine_first_frame_presented\"]) {\n"
        "            self.statusLabel.hidden = YES;\n"
        "        }\n",
        "        if ([text containsString:@\"phase=m4_engine_first_frame_presented\"]) {\n"
        "            self.statusLabel.hidden = YES;\n"
        "        } else if ([text containsString:@\"phase=m4_engine_fatal_error\"] ||\n"
        "                   [text containsString:@\"phase=m4_engine_probe_returned\"]) {\n"
        "            self.statusLabel.hidden = NO;\n"
        "#if defined(SELACO_IOS_ZSCRIPT_DIAGNOSTICS)\n"
        "            NSString *tail = EngineConsoleLogTail(12);\n"
        "            self.statusLabel.text = [NSString stringWithFormat:\n"
        "                @\"%@\\n\\nLast engine console lines:\\n%@\\n\\n\"\n"
        "                 \"Full log: Files > SelacoiOS Engine Init > Selaco > zscript-compile.log\",\n"
        "                text, tail];\n"
        "#else\n"
        "            self.statusLabel.text = text;\n"
        "#endif\n"
        "        }\n",
        "show the captured compiler diagnostics after engine failure",
    )

    replace_once(
        d_main,
        "\tR_ParseTrnslate();\n"
        "\tPClassActor::StaticInit ();\n"
        "\tFBaseCVar::InitZSCallbacks ();\n",
        "\tR_ParseTrnslate();\n"
        "#if defined(SELACO_IOS_ZSCRIPT_DIAGNOSTICS)\n"
        "\tSelacoIOSReportLicensedAssetProbe(\n"
        "\t\t\"actor_zscript_compile_entered\",\n"
        "\t\t\"PClassActor::StaticInit and Selaco.ipk3:zscript\");\n"
        "#endif\n"
        "\tPClassActor::StaticInit ();\n"
        "#if defined(SELACO_IOS_ZSCRIPT_DIAGNOSTICS)\n"
        "\tSelacoIOSReportLicensedAssetProbe(\n"
        "\t\t\"actor_zscript_compile_passed\",\n"
        "\t\t\"PClassActor::StaticInit completed\");\n"
        "#endif\n"
        "\tFBaseCVar::InitZSCallbacks ();\n",
        "instrument the actor and ZScript compilation boundary",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
