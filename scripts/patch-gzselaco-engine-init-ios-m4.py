#!/usr/bin/env python3
"""Advance the pinned GZSelaco startup to the bounded M4A pre-renderer boundary."""

from __future__ import annotations

import pathlib
import shutil
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
            "usage: patch-gzselaco-engine-init-ios-m4.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    repository_root = pathlib.Path(__file__).resolve().parents[1]
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
    strategy_overlay = (
        repository_root
        / "overlays"
        / "gzselaco-ios"
        / "i_engine_init_probe.mm"
    )
    strategy_destination = runtime_source.parent / "i_engine_init_probe.mm"

    for path in (src_cmake, runtime_source, d_main, strategy_overlay):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4 prerequisite is missing: {path}")

    shutil.copyfile(strategy_overlay, strategy_destination)

    replace_once(
        src_cmake,
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp\n"
        "\tcommon/platform/ios/i_platform_runtime.mm\n"
        "\tcommon/platform/ios/i_engine_startup_stubs.mm )\n",
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp\n"
        "\tcommon/platform/ios/i_platform_runtime.mm\n"
        "\tcommon/platform/ios/i_engine_startup_stubs.mm\n"
        "\tcommon/platform/ios/i_engine_init_probe.mm )\n",
        "add the separate Milestone 4 engine-init strategy source",
    )
    replace_once(
        src_cmake,
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.localasset.m3"',
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.engineinit.m4"',
        "assign the Milestone 4 bundle identifier",
    )
    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_LOCAL_ASSET_PROBE=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_LOCAL_ASSET_PROBE=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ENGINE_INIT_PROBE=1)\n",
        "enable the bounded Milestone 4 engine-init probe",
    )

    replace_once(
        runtime_source,
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n',
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n'
        'extern "C" const char *SelacoIOSM4RendererStrategy();\n',
        "declare the Milestone 4 renderer-ownership strategy",
    )
    replace_once(
        runtime_source,
        '        SelacoIOSReportLicensedAssetProbe(\n'
        '            "engine_probe_starting",\n'
        '            "Calling the real GZSelaco GameMain through IWAD recognition only");\n',
        '        SelacoIOSReportLicensedAssetProbe(\n'
        '            "renderer_strategy_selected",\n'
        '            SelacoIOSM4RendererStrategy());\n'
        '        SelacoIOSReportLicensedAssetProbe(\n'
        '            "engine_probe_starting",\n'
        '            "Calling the real GZSelaco GameMain through early initialization and stopping before V_Init2");\n',
        "record the controlled stop-before-renderer strategy",
    )
    replace_once(
        runtime_source,
        '            result == 73 ? "engine_iwad_recognized" : "engine_probe_returned",\n',
        '            result == 75 ? "engine_init_boundary_reached" :\n'
        '            (result == 73 ? "engine_iwad_recognized" : "engine_probe_returned"),\n',
        "classify the bounded Milestone 4 return code",
    )
    replace_once(
        runtime_source,
        '    NSString *line = [NSString stringWithFormat:@"phase=m3_%@ %@", phaseText, detailText];\n'
        '    WriteBreadcrumb(line);\n'
        '    NSString *path = DiagnosticPath(@"licensed-asset-status.txt");\n'
        '    if (path != nil) {\n'
        '        [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];\n'
        '    }\n',
        '    NSString *line = [NSString stringWithFormat:@"phase=m4_%@ %@", phaseText, detailText];\n'
        '    WriteBreadcrumb(line);\n'
        '    NSString *licensedPath = DiagnosticPath(@"licensed-asset-status.txt");\n'
        '    if (licensedPath != nil) {\n'
        '        [line writeToFile:licensedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];\n'
        '    }\n'
        '    NSString *enginePath = DiagnosticPath(@"engine-init-status.txt");\n'
        '    if (enginePath != nil) {\n'
        '        [line writeToFile:enginePath atomically:YES encoding:NSUTF8StringEncoding error:nil];\n'
        '    }\n'
        '    if ([phaseText containsString:@"renderer"] || [phaseText containsString:@"v_init2"]) {\n'
        '        NSString *rendererPath = DiagnosticPath(@"renderer-init-status.txt");\n'
        '        if (rendererPath != nil) {\n'
        '            [line writeToFile:rendererPath atomically:YES encoding:NSUTF8StringEncoding error:nil];\n'
        '        }\n'
        '    }\n',
        "persist Milestone 4 engine and renderer status files",
    )

    runtime_text = runtime_source.read_text(encoding="utf-8")
    runtime_text = runtime_text.replace("SelacoiOS Milestone 3", "SelacoiOS Milestone 4")
    runtime_text = runtime_text.replace("SelacoiOS Local Asset", "SelacoiOS Engine Init")
    runtime_source.write_text(runtime_text, encoding="utf-8")

    replace_once(
        d_main,
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n'
        '#endif\n',
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n'
        '#endif\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        'extern "C" const char *SelacoIOSM4RendererStrategy();\n'
        '#endif\n',
        "declare the Milestone 4 engine instrumentation in d_main",
    )
    replace_once(
        d_main,
        '\tD_DoomInit();\n'
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("doom_init_passed", "engine command line and core startup initialized");\n'
        '#endif\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("doom_init_entered", "entering D_DoomInit");\n'
        '#endif\n'
        '\tD_DoomInit();\n'
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("doom_init_passed", "engine command line and core startup initialized");\n'
        '#endif\n',
        "record entry into D_DoomInit",
    )
    replace_once(
        d_main,
        '\twad = BaseFileSearch(BASEWAD, NULL, true, GameConfig);\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("public_support_lookup_entered", BASEWAD);\n'
        '#endif\n'
        '\twad = BaseFileSearch(BASEWAD, NULL, true, GameConfig);\n',
        "record public support archive lookup",
    )
    replace_once(
        d_main,
        '\tiwad_man = new FIWadManager(basewad.GetChars(), optionalwad.GetChars());\n\n'
        '\t// Now that we have the IWADINFO, initialize the autoload ini sections.\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("iwad_manager_construct_entered", basewad.GetChars());\n'
        '#endif\n'
        '\tiwad_man = new FIWadManager(basewad.GetChars(), optionalwad.GetChars());\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("iwad_manager_construct_passed", basewad.GetChars());\n'
        '#endif\n\n'
        '\t// Now that we have the IWADINFO, initialize the autoload ini sections.\n',
        "instrument FIWadManager construction",
    )
    replace_once(
        d_main,
        '\t\tPClass::StaticInit();\n'
        '\t\tPType::StaticInit();\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("pclass_static_init_entered", "PClass::StaticInit");\n'
        '#endif\n'
        '\t\tPClass::StaticInit();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("pclass_static_init_passed", "PClass::StaticInit");\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("ptype_static_init_entered", "PType::StaticInit");\n'
        '#endif\n'
        '\t\tPType::StaticInit();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("ptype_static_init_passed", "PType::StaticInit");\n'
        '#endif\n',
        "instrument PClass and PType static initialization",
    )
    replace_once(
        d_main,
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\t\tif (!iwad_info)\n'
        '\t\t{\n'
        '\t\t\tSelacoIOSReportLicensedAssetProbe("iwad_not_recognized", iwad.GetChars());\n'
        '\t\t\treturn 74;\n'
        '\t\t}\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("iwad_recognized", iwad.GetChars());\n'
        '\t\treturn 73;\n'
        '#endif\n\n'
        '\t\tGetCmdLineFiles(pwads); // [RL0] Update with files passed on the launcher extra args\n',
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE) && !defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tif (!iwad_info)\n'
        '\t\t{\n'
        '\t\t\tSelacoIOSReportLicensedAssetProbe("iwad_not_recognized", iwad.GetChars());\n'
        '\t\t\treturn 74;\n'
        '\t\t}\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("iwad_recognized", iwad.GetChars());\n'
        '\t\treturn 73;\n'
        '#endif\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tif (!iwad_info)\n'
        '\t\t{\n'
        '\t\t\tSelacoIOSReportLicensedAssetProbe("iwad_not_recognized", iwad.GetChars());\n'
        '\t\t\treturn 74;\n'
        '\t\t}\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("iwad_recognized", iwad.GetChars());\n'
        '#endif\n\n'
        '\t\tGetCmdLineFiles(pwads); // [RL0] Update with files passed on the launcher extra args\n',
        "continue beyond IWAD recognition only for Milestone 4",
    )
    replace_once(
        d_main,
        '\t\tint ret = D_InitGame(iwad_info, allwads, pwads);\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("d_init_game_call_entered", "calling D_InitGame");\n'
        '#endif\n'
        '\t\tint ret = D_InitGame(iwad_info, allwads, pwads);\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tif (ret == 75)\n'
        '\t\t{\n'
        '\t\t\tSelacoIOSReportLicensedAssetProbe("d_init_game_pre_renderer_passed", SelacoIOSM4RendererStrategy());\n'
        '\t\t}\n'
        '#endif\n',
        "instrument the D_InitGame call boundary",
    )
    replace_once(
        d_main,
        'static int D_InitGame(const FIWADInfo* iwad_info, std::vector<std::string>& allwads, std::vector<std::string>& pwads)\n'
        '{\n'
        '\tcycle_t timer = cycle_t();\n'
        '\tNetworkEntityManager::InitializeNetworkEntities();\n',
        'static int D_InitGame(const FIWADInfo* iwad_info, std::vector<std::string>& allwads, std::vector<std::string>& pwads)\n'
        '{\n'
        '\tcycle_t timer = cycle_t();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("d_init_game_entered", "D_InitGame");\n'
        '#endif\n'
        '\tNetworkEntityManager::InitializeNetworkEntities();\n',
        "record D_InitGame entry",
    )
    replace_once(
        d_main,
        '\t\tV_InitScreenSize();\n'
        '\t\t// This allocates a dummy framebuffer as a stand-in until V_Init2 is called.\n'
        '\t\tV_InitScreen();\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("v_init_screen_size_entered", "V_InitScreenSize");\n'
        '#endif\n'
        '\t\tV_InitScreenSize();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("v_init_screen_size_passed", "V_InitScreenSize");\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("v_init_screen_entered", "creating dummy framebuffer only");\n'
        '#endif\n'
        '\t\t// This allocates a dummy framebuffer as a stand-in until V_Init2 is called.\n'
        '\t\tV_InitScreen();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\t\tSelacoIOSReportLicensedAssetProbe("v_init_screen_passed", "dummy framebuffer created");\n'
        '#endif\n',
        "instrument dummy screen setup",
    )
    replace_once(
        d_main,
        '\tgameinfo.ConfigName = iwad_info->Configname;\n\n'
        '\tconst char *v = Args->CheckValue("-rngseed");\n',
        '\tgameinfo.ConfigName = iwad_info->Configname;\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("game_metadata_setup_passed", gameinfo.ConfigName.GetChars());\n'
        '#endif\n\n'
        '\tconst char *v = Args->CheckValue("-rngseed");\n',
        "record game metadata setup",
    )
    replace_once(
        d_main,
        '\tFBaseCVar::DisableCallbacks();\n'
        '\tGameConfig->DoGameSetup (gameinfo.ConfigName.GetChars());\n',
        '\tFBaseCVar::DisableCallbacks();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("game_config_setup_entered", gameinfo.ConfigName.GetChars());\n'
        '#endif\n'
        '\tGameConfig->DoGameSetup (gameinfo.ConfigName.GetChars());\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("game_config_setup_passed", gameinfo.ConfigName.GetChars());\n'
        '#endif\n',
        "instrument GameConfig DoGameSetup",
    )
    replace_once(
        d_main,
        '\tbool allowduplicates = Args->CheckParm("-allowduplicates");\n'
        '\tauto hashfile = D_GetHashFile();\n'
        '\tif (!fileSystem.InitMultipleFiles(allwads, &lfi, FileSystemPrintf, allowduplicates, hashfile))\n',
        '\tbool allowduplicates = Args->CheckParm("-allowduplicates");\n'
        '\tauto hashfile = D_GetHashFile();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("resource_mount_entered", "FileSystem::InitMultipleFiles");\n'
        '#endif\n'
        '\tif (!fileSystem.InitMultipleFiles(allwads, &lfi, FileSystemPrintf, allowduplicates, hashfile))\n',
        "record resource mount entry",
    )
    replace_once(
        d_main,
        '\tallwads.clear();\n'
        '\tallwads.shrink_to_fit();\n'
        '\tSetMapxxFlag();\n\n'
        '\tD_GrabCVarDefaults(); //parse DEFCVARS\n'
        '\tInitPalette();\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("resource_mount_passed", "FileSystem::InitMultipleFiles");\n'
        '#endif\n'
        '\tallwads.clear();\n'
        '\tallwads.shrink_to_fit();\n'
        '\tSetMapxxFlag();\n\n'
        '\tD_GrabCVarDefaults(); //parse DEFCVARS\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("palette_init_entered", "InitPalette");\n'
        '#endif\n'
        '\tInitPalette();\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("palette_init_passed", "InitPalette");\n'
        '#endif\n',
        "record resource and palette initialization",
    )
    replace_once(
        d_main,
        '\tif (!restart)\n'
        '\t\tV_Init2();\n\n'
        '\tCLOCK_START\n',
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("renderer_creation_deferred", SelacoIOSM4RendererStrategy());\n'
        '\treturn 75;\n'
        '#endif\n'
        '\tif (!restart)\n'
        '\t\tV_Init2();\n\n'
        '\tCLOCK_START\n',
        "stop immediately before engine renderer creation",
    )
    replace_once(
        d_main,
        'int GameMain()\n'
        '{\n'
        '\tint ret = 0;\n',
        'int GameMain()\n'
        '{\n'
        '#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n'
        '\tSelacoIOSReportLicensedAssetProbe("game_main_entered", "real pinned GZSelaco GameMain");\n'
        '#endif\n'
        '\tint ret = 0;\n',
        "record GameMain entry",
    )
    replace_once(
        d_main,
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\tif (ret == 73 || ret == 74) return ret;\n'
        '#endif\n',
        '#if defined(SELACO_IOS_LOCAL_ASSET_PROBE)\n'
        '\tif (ret == 73 || ret == 74 || ret == 75) return ret;\n'
        '#endif\n',
        "avoid unsafe teardown after the bounded M4 return",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
