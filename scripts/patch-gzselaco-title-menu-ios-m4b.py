#!/usr/bin/env python3
"""Continue M4B through V_Init2, menus, title startup, and the engine loop."""

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
        print("usage: patch-gzselaco-title-menu-ios-m4b.py <GZSelaco source>", file=sys.stderr)
        return 2
    d_main = pathlib.Path(sys.argv[1]).resolve() / "src" / "d_main.cpp"
    if not d_main.is_file():
        raise RuntimeError(f"Milestone 4B d_main prerequisite is missing: {d_main}")

    replace_once(
        d_main,
        """#if defined(SELACO_IOS_ENGINE_INIT_PROBE)
\tSelacoIOSReportLicensedAssetProbe("renderer_creation_deferred", SelacoIOSM4RendererStrategy());
\treturn 75;
#endif
\tif (!restart)
\t\tV_Init2();

\tCLOCK_START
""",
        """#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\tSelacoIOSReportLicensedAssetProbe("v_init2_entered", SelacoIOSM4RendererStrategy());
#endif
\tif (!restart)
\t\tV_Init2();
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\tSelacoIOSReportLicensedAssetProbe("v_init2_passed", "engine video backend and framebuffer initialized");
#endif

\tCLOCK_START
""",
        "continue through V_Init2",
    )
    replace_once(
        d_main,
        """\tif (!batchrun) Printf("M_Init: Init menus.\\n");
\tSetDefaultMenuColors();
\tM_Init();
\tM_CreateGameMenus();
""",
        """\tif (!batchrun) Printf("M_Init: Init menus.\\n");
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\tSelacoIOSReportLicensedAssetProbe("menu_init_entered", "M_Init and M_CreateGameMenus");
#endif
\tSetDefaultMenuColors();
\tM_Init();
\tM_CreateGameMenus();
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\tSelacoIOSReportLicensedAssetProbe("menu_init_passed", "game menus created");
#endif
""",
        "instrument menu initialization",
    )
    replace_once(
        d_main,
        """\t\t\t\t\t\tif (multiplayer || cl_nointros || Args->CheckParm("-nointro"))
\t\t\t\t\t\t{
\t\t\t\t\t\t\tD_StartTitle();
\t\t\t\t\t\t}
""",
        """\t\t\t\t\t\tif (multiplayer || cl_nointros || Args->CheckParm("-nointro"))
\t\t\t\t\t\t{
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\t\t\t\t\t\t\tSelacoIOSReportLicensedAssetProbe("title_loop_entered", "D_StartTitle");
#endif
\t\t\t\t\t\t\tD_StartTitle();
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\t\t\t\t\t\t\tSelacoIOSReportLicensedAssetProbe("title_loop_started", "title loop initialized; entering engine loop");
#endif
\t\t\t\t\t\t}
""",
        "instrument the no-intro title loop",
    )
    replace_once(
        d_main,
        "\t\tI_UpdateWindowTitle();\n"
        "\t\tI_FocusWindow();\n"
        "\t\tD_DoomLoop ();\t\t// this only returns if a 'restart' CCMD is given.\n",
        "\t\tI_UpdateWindowTitle();\n"
        "\t\tI_FocusWindow();\n"
        "#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)\n"
        "\t\tSelacoIOSReportLicensedAssetProbe(\"engine_loop_entered\", \"D_DoomLoop\");\n"
        "#endif\n"
        "\t\tD_DoomLoop ();\t\t// this only returns if a 'restart' CCMD is given.\n",
        "instrument engine-loop entry",
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
