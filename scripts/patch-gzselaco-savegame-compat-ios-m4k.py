#!/usr/bin/env python3
"""Add the bounded M4K transient save-slot compatibility experiment."""

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


def require_text(path: pathlib.Path, needle: str, description: str) -> None:
    if needle not in path.read_text(encoding="utf-8"):
        raise RuntimeError(f"{description}: missing from {path}")


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: patch-gzselaco-savegame-compat-ios-m4k.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    compatibility = (
        root / "wadsrc" / "static" / "zscript" / "compatibility.zs"
    )
    codegen_cpp = (
        root / "src" / "common" / "scripting" / "backend" / "codegen.cpp"
    )
    savegamemanager = root / "src" / "common" / "menu" / "savegamemanager.cpp"
    g_game = root / "src" / "g_game.cpp"

    for path in (
        src_cmake,
        compatibility,
        codegen_cpp,
        savegamemanager,
        g_game,
    ):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4K prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS=1)\n",
        "enable bounded M4K compatibility diagnostics",
    )

    compatibility_surface = """extend class Object
{
	// SELACO_IOS_M4K_COMPAT field=levelnum owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
	transient int levelnum;
	// SELACO_IOS_M4K_COMPAT field=elapsedTime owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
	transient int elapsedTime;
	// SELACO_IOS_M4K_COMPAT field=saveDate owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
	transient int saveDate;
	// SELACO_IOS_M4K_COMPAT field=totaltime owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
	transient int totaltime;
	// SELACO_IOS_M4K_COMPAT field=saveFlags owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
	transient int saveFlags;
"""
    replace_once(
        compatibility,
        "extend class Object\n{\n",
        compatibility_surface,
        "add transient root-ancestor compatibility fields",
    )

    compatibility_reporter = """#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)
static void ReportSelacoIOSM4KCompatibilityField(
	FScriptPosition &position,
	const FName &identifier)
{
	const char *field = nullptr;
	if (identifier == FName("levelnum")) field = "levelnum";
	else if (identifier == FName("elapsedTime")) field = "elapsedTime";
	else if (identifier == FName("saveDate")) field = "saveDate";
	else if (identifier == FName("totaltime")) field = "totaltime";
	else if (identifier == FName("saveFlags")) field = "saveFlags";
	if (field == nullptr) return;

	position.Message(
		MSG_WARNING,
		"SELACO_IOS_M4K_COMPAT field=%s owner=Object type=SInt4 "
		"source=diagnostic-default default=0 read_only=0 persisted=0",
		field);
}
#endif

"""
    replace_once(
        codegen_cpp,
        "FxExpression *FxIdentifier::ResolveMember("
        "FCompileContext &ctx, PContainerType *classctx, "
        "FxExpression *&object, PContainerType *objtype)\n",
        compatibility_reporter
        + "FxExpression *FxIdentifier::ResolveMember("
        "FCompileContext &ctx, PContainerType *classctx, "
        "FxExpression *&object, PContainerType *objtype)\n",
        "add bounded compatibility-field resolution markers",
    )

    replace_once(
        codegen_cpp,
        "\t\telse if (sym->IsKindOf(RUNTIME_CLASS(PField)))\n"
        "\t\t{\n"
        "\t\t\tPField *vsym = static_cast<PField*>(sym);\n"
        "\t\t\tif (vsym->GetVersion() > ctx.Version)\n",
        "\t\telse if (sym->IsKindOf(RUNTIME_CLASS(PField)))\n"
        "\t\t{\n"
        "#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)\n"
        "\t\t\tReportSelacoIOSM4KCompatibilityField("
        "ScriptPosition, Identifier);\n"
        "#endif\n"
        "\t\t\tPField *vsym = static_cast<PField*>(sym);\n"
        "\t\t\tif (vsym->GetVersion() > ctx.Version)\n",
        "emit a marker only when a compatibility field resolves",
    )

    replace_once(
        savegamemanager,
        "int FSavegameManagerBase::RemoveSaveSlot(int index)\n"
        "{\n"
        "\tint listindex = SaveGames[0]->bNoDelete ? index - 1 : index;\n",
        "int FSavegameManagerBase::RemoveSaveSlot(int index)\n"
        "{\n"
        "#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)\n"
        "\tPrintf(\"SELACO_IOS_M4K_SAVE_BLOCKED "
        "path=SavegameManager.RemoveSaveSlot selected=%d no_write=1\\n\", "
        "index);\n"
        "\tI_Error(\"SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort "
        "before save deletion\");\n"
        "#endif\n"
        "\tint listindex = SaveGames[0]->bNoDelete ? index - 1 : index;\n",
        "block save deletion before RemoveFile and slot mutation",
    )

    replace_once(
        savegamemanager,
        "void FSavegameManagerBase::DoSave("
        "int Selected, const char *savegamestring)\n"
        "{\n"
        "\t// @Cockatrice - Consult the event managers to determine if we are "
        "actually allowed to save at this moment\n",
        "void FSavegameManagerBase::DoSave("
        "int Selected, const char *savegamestring)\n"
        "{\n"
        "#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)\n"
        "\tPrintf(\"SELACO_IOS_M4K_SAVE_BLOCKED "
        "path=SavegameManager.DoSave selected=%d no_write=1\\n\", Selected);\n"
        "\tI_Error(\"SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort "
        "before manager save\");\n"
        "#endif\n"
        "\t// @Cockatrice - Consult the event managers to determine if we are "
        "actually allowed to save at this moment\n",
        "block public two-argument manager saving in the diagnostic build",
    )

    replace_once(
        g_game,
        "void G_SaveGame (const char *filename, const char *description)\n"
        "{\n"
        "\tif (sendsave || gameaction == ga_savegame)\n",
        "void G_SaveGame (const char *filename, const char *description)\n"
        "{\n"
        "#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)\n"
        "\tPrintf(\"SELACO_IOS_M4K_SAVE_BLOCKED "
        "path=G_SaveGame no_write=1\\n\");\n"
        "\tI_Error(\"SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort "
        "before save scheduling\");\n"
        "#endif\n"
        "\tif (sendsave || gameaction == ga_savegame)\n",
        "block global save scheduling before state mutation",
    )

    replace_once(
        g_game,
        "void G_DoSaveGame (bool okForQuicksave, bool forceQuicksave, "
        "FString filename, const char *description)\n"
        "{\n"
        "\tTArray<FCompressedBuffer> savegame_content;\n",
        "void G_DoSaveGame (bool okForQuicksave, bool forceQuicksave, "
        "FString filename, const char *description)\n"
        "{\n"
        "#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)\n"
        "\tPrintf(\"SELACO_IOS_M4K_SAVE_BLOCKED "
        "path=G_DoSaveGame no_write=1\\n\");\n"
        "\tI_Error(\"SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort "
        "before save serialization\");\n"
        "#endif\n"
        "\tTArray<FCompressedBuffer> savegame_content;\n",
        "block global serialization before snapshot creation",
    )

    compatibility_text = compatibility.read_text(encoding="utf-8")
    for field in ("levelnum", "elapsedTime", "saveDate", "totaltime", "saveFlags"):
        require_text(
            compatibility,
            f"transient int {field};",
            f"transient {field} declaration",
        )
        require_text(
            compatibility,
            f"SELACO_IOS_M4K_COMPAT field={field} owner=Object type=SInt4",
            f"{field} diagnostic marker",
        )
    if "SELACO_IOS_M4K_COMPAT field=info" in compatibility_text:
        raise RuntimeError("ambiguous info field must not be declared")

    require_text(
        savegamemanager,
        "DEFINE_ACTION_FUNCTION(FSavegameManager, "
        "SelacoIOSM4JDoSaveDiagnostic)",
        "inherited M4J three-argument no-write adapter",
    )
    require_text(
        savegamemanager,
        "DEFINE_ACTION_FUNCTION(FSavegameManager, DoSave)",
        "original two-argument DoSave native thunk",
    )
    require_text(
        savegamemanager,
        "SELACO_IOS_M4K_SAVE_BLOCKED "
        "path=SavegameManager.RemoveSaveSlot",
        "save deletion guard",
    )
    require_text(
        savegamemanager,
        "SELACO_IOS_M4K_SAVE_BLOCKED path=SavegameManager.DoSave",
        "manager save guard",
    )
    require_text(g_game, "path=G_SaveGame no_write=1", "G_SaveGame guard")
    require_text(g_game, "path=G_DoSaveGame no_write=1", "G_DoSaveGame guard")

    if "FSerializer" in compatibility_text or "SaveGames" in compatibility_text:
        raise RuntimeError("script compatibility surface unexpectedly touches saves")

    print(
        "SELACO_IOS_M4K patch applied: five transient Object compatibility "
        "integers, info intentionally absent, and structural no-write guards"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)

