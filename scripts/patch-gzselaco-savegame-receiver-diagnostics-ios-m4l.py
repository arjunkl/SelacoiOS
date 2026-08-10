#!/usr/bin/env python3
"""Replace the invalid M4K Object shim with receiver-type diagnostics."""

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


def replace_count(
    path: pathlib.Path,
    old: str,
    new: str,
    expected: int,
    description: str,
) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != expected:
        raise RuntimeError(
            f"{description}: expected {expected} exact matches in {path}, found {count}"
        )
    path.write_text(text.replace(old, new), encoding="utf-8")


def require_text(path: pathlib.Path, needle: str, description: str) -> None:
    if needle not in path.read_text(encoding="utf-8"):
        raise RuntimeError(f"{description}: missing from {path}")


def forbid_text(path: pathlib.Path, needle: str, description: str) -> None:
    if needle in path.read_text(encoding="utf-8"):
        raise RuntimeError(f"{description}: unexpectedly present in {path}")


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: patch-gzselaco-savegame-receiver-diagnostics-ios-m4l.py "
            "<GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    compatibility = root / "wadsrc" / "static" / "zscript" / "compatibility.zs"
    codegen_cpp = (
        root / "src" / "common" / "scripting" / "backend" / "codegen.cpp"
    )
    codegen_h = root / "src" / "common" / "scripting" / "backend" / "codegen.h"
    savegamemanager = root / "src" / "common" / "menu" / "savegamemanager.cpp"
    g_game = root / "src" / "g_game.cpp"

    for path in (
        src_cmake,
        compatibility,
        codegen_cpp,
        codegen_h,
        savegamemanager,
        g_game,
    ):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4L prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_RECEIVER_DIAGNOSTICS=1)\n",
        "replace the M4K compatibility mode with bounded M4L diagnostics",
    )

    compatibility_surface = """\t// SELACO_IOS_M4K_COMPAT field=levelnum owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
\ttransient int levelnum;
\t// SELACO_IOS_M4K_COMPAT field=elapsedTime owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
\ttransient int elapsedTime;
\t// SELACO_IOS_M4K_COMPAT field=saveDate owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
\ttransient int saveDate;
\t// SELACO_IOS_M4K_COMPAT field=totaltime owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
\ttransient int totaltime;
\t// SELACO_IOS_M4K_COMPAT field=saveFlags owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0
\ttransient int saveFlags;
"""
    replace_once(
        compatibility,
        compatibility_surface,
        "\t// SELACO_IOS_M4L: M4K Object fields removed; receiver ownership "
        "must be measured before compatibility is added.\n",
        "remove the invalid native Object compatibility surface",
    )

    compatibility_reporter = """#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)
static void ReportSelacoIOSM4KCompatibilityField(
\tFScriptPosition &position,
\tconst FName &identifier)
{
\tconst char *field = nullptr;
\tif (identifier == FName("levelnum")) field = "levelnum";
\telse if (identifier == FName("elapsedTime")) field = "elapsedTime";
\telse if (identifier == FName("saveDate")) field = "saveDate";
\telse if (identifier == FName("totaltime")) field = "totaltime";
\telse if (identifier == FName("saveFlags")) field = "saveFlags";
\tif (field == nullptr) return;

\tposition.Message(
\t\tMSG_WARNING,
\t\t"SELACO_IOS_M4K_COMPAT field=%s owner=Object type=SInt4 "
\t\t"source=diagnostic-default default=0 read_only=0 persisted=0",
\t\tfield);
}
#endif

"""
    replace_once(
        codegen_cpp,
        compatibility_reporter,
        "",
        "remove the misleading M4K field-resolution reporter",
    )
    replace_once(
        codegen_cpp,
        "#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)\n"
        "\t\t\tReportSelacoIOSM4KCompatibilityField("
        "ScriptPosition, Identifier);\n"
        "#endif\n",
        "",
        "remove the M4K resolution hook",
    )

    replace_once(
        codegen_h,
        "\tPType *SelacoIOSM4JExpectedType = nullptr;\n\n",
        "\tPType *SelacoIOSM4JExpectedType = nullptr;\n"
        "\tFName SelacoIOSM4LRequestedMember = NAME_None;\n\n",
        "record the right-hand member requested from an unresolved left operand",
    )

    replace_once(
        codegen_cpp,
        "\tFCompileContext &ctx,\n\tFxExpression *expression)\n{\n",
        "\tFCompileContext &ctx,\n\tFxExpression *expression,\n"
        "\tPContainerType *receiverType)\n{\n",
        "extend the unknown-identifier reporter with receiver type",
    )
    replace_once(
        codegen_cpp,
        "\tconst char *selfClass = (ctx.Function == nullptr ||\n"
        "\t\tctx.Function->Variants[0].SelfClass == nullptr)\n"
        "\t\t? \"<none>\"\n"
        "\t\t: ctx.Function->Variants[0].SelfClass->TypeName.GetChars();\n",
        "\tconst char *selfClass = (ctx.Function == nullptr ||\n"
        "\t\tctx.Function->Variants[0].SelfClass == nullptr)\n"
        "\t\t? \"<none>\"\n"
        "\t\t: ctx.Function->Variants[0].SelfClass->TypeName.GetChars();\n"
        "\tconst char *receiverTypeName = receiverType == nullptr\n"
        "\t\t? \"<none>\"\n"
        "\t\t: receiverType->DescriptiveName();\n"
        "\tconst char *receiverKind = receiverType == nullptr\n"
        "\t\t? \"<none>\"\n"
        "\t\t: (receiverType->isClass() ? \"class\" : \"struct\");\n"
        "\tconst char *requestedMember = (expression == nullptr ||\n"
        "\t\texpression->SelacoIOSM4LRequestedMember == NAME_None)\n"
        "\t\t? \"<none>\"\n"
        "\t\t: expression->SelacoIOSM4LRequestedMember.GetChars();\n",
        "derive a stable receiver description",
    )
    replace_once(
        codegen_cpp,
        "\t\t\"[SELACO_IOS_M4J identifier=%s source=%s line=%d column=<unknown> \"\n"
        "\t\t\"class=%s function=%s self=%s parent_chain=%s \"\n",
        "\t\t\"[SELACO_IOS_M4L_UNKNOWN_MEMBER identifier=%s source=%s line=%d column=<unknown> \"\n"
        "\t\t\"class=%s function=%s self=%s parent_chain=%s \"\n"
        "\t\t\"receiver_type=%s receiver_kind=%s requested_member=%s \"\n",
        "promote the diagnostic marker to M4L",
    )
    replace_once(
        codegen_cpp,
        "\t\townerClass, ownerFunction, selfClass, parentChain.GetChars(),\n"
        "\t\tinfoFieldOwner.GetChars(),\n",
        "\t\townerClass, ownerFunction, selfClass, parentChain.GetChars(),\n"
        "\t\treceiverTypeName, receiverKind, requestedMember,\n"
        "\t\tinfoFieldOwner.GetChars(),\n",
        "include receiver fields in the diagnostic arguments",
    )
    replace_count(
        codegen_cpp,
        "ReportSelacoIOSM4IUnknownIdentifier("
        "ScriptPosition, Identifier, ctx, this);",
        "ReportSelacoIOSM4IUnknownIdentifier("
        "ScriptPosition, Identifier, ctx, this, nullptr);",
        2,
        "add default receiver arguments to both diagnostic call sites",
    )
    replace_once(
        codegen_cpp,
        "\telse\n\t{\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\tReportSelacoIOSM4IUnknownIdentifier("
        "ScriptPosition, Identifier, ctx, this, nullptr);\n",
        "\telse\n\t{\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\tReportSelacoIOSM4IUnknownIdentifier("
        "ScriptPosition, Identifier, ctx, this, objtype);\n",
        "pass the resolved member receiver container to the reporter",
    )

    replace_once(
        codegen_cpp,
        "\tSAFE_RESOLVE(Object, ctx);\n\n"
        "\t// check for class or struct constants/functions if the left side is a type name.\n",
        "#if defined(SELACO_IOS_SAVEGAME_RECEIVER_DIAGNOSTICS)\n"
        "\tObject->SelacoIOSM4LRequestedMember = Identifier;\n"
        "#endif\n"
        "\tSAFE_RESOLVE(Object, ctx);\n\n"
        "\t// check for class or struct constants/functions if the left side is a type name.\n",
        "annotate an unresolved left operand with its requested member",
    )

    remove_slot_guard = """#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)
\tPrintf("SELACO_IOS_M4K_SAVE_BLOCKED path=SavegameManager.RemoveSaveSlot selected=%d no_write=1\\n", index);
\tI_Error("SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort before save deletion");
#endif
"""
    manager_save_guard = """#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)
\tPrintf("SELACO_IOS_M4K_SAVE_BLOCKED path=SavegameManager.DoSave selected=%d no_write=1\\n", Selected);
\tI_Error("SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort before manager save");
#endif
"""
    schedule_guard = """#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)
\tPrintf("SELACO_IOS_M4K_SAVE_BLOCKED path=G_SaveGame no_write=1\\n");
\tI_Error("SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort before save scheduling");
#endif
"""
    serialization_guard = """#if defined(SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS)
\tPrintf("SELACO_IOS_M4K_SAVE_BLOCKED path=G_DoSaveGame no_write=1\\n");
\tI_Error("SELACO_IOS_M4K_SAVE_BLOCKED bounded diagnostic abort before save serialization");
#endif
"""
    replace_once(
        savegamemanager,
        remove_slot_guard,
        "",
        "remove the broad M4K save deletion guard",
    )
    replace_once(
        savegamemanager,
        manager_save_guard,
        "",
        "remove the broad M4K manager save guard",
    )
    replace_once(
        g_game,
        schedule_guard,
        "",
        "remove the broad M4K save scheduling guard",
    )
    replace_once(
        g_game,
        serialization_guard,
        "",
        "remove the broad M4K serialization guard",
    )

    for field in ("levelnum", "elapsedTime", "saveDate", "totaltime", "saveFlags"):
        forbid_text(
            compatibility,
            f"transient int {field};",
            f"invalid M4K Object field {field}",
        )
    forbid_text(
        codegen_cpp,
        "ReportSelacoIOSM4KCompatibilityField",
        "M4K compatibility resolution reporter",
    )
    forbid_text(
        src_cmake,
        "SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS=1",
        "enabled M4K compatibility macro",
    )
    require_text(
        codegen_cpp,
        "[SELACO_IOS_M4L_UNKNOWN_MEMBER identifier=%s",
        "M4L diagnostic marker",
    )
    require_text(
        codegen_cpp,
        "receiver_type=%s receiver_kind=%s",
        "receiver diagnostic fields",
    )
    require_text(
        codegen_cpp,
        "requested_member=%s",
        "left-operand sibling diagnostic field",
    )
    require_text(
        codegen_h,
        "SelacoIOSM4LRequestedMember",
        "left-operand sibling metadata",
    )
    require_text(
        codegen_cpp,
        "ScriptPosition, Identifier, ctx, this, objtype",
        "member receiver diagnostic call",
    )

    for path, marker in (
        (savegamemanager, "SELACO_IOS_M4K_SAVE_BLOCKED"),
        (g_game, "SELACO_IOS_M4K_SAVE_BLOCKED"),
    ):
        forbid_text(path, marker, f"broad M4K guard marker {marker}")
    require_text(
        savegamemanager,
        "DEFINE_ACTION_FUNCTION(FSavegameManager, SelacoIOSM4JDoSaveDiagnostic)",
        "exact M4J three-argument no-write adapter",
    )

    print(
        "SELACO_IOS_M4L patch applied: invalid Object fields removed, "
        "receiver type diagnostics enabled, and only the exact M4J adapter retained"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
