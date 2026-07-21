#!/usr/bin/env python3
"""Add bounded retail save-menu API diagnostics after the M4H physical pass."""

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


def replace_in_region(
    path: pathlib.Path,
    start_marker: str,
    end_marker: str,
    old: str,
    new: str,
    description: str,
) -> None:
    text = path.read_text(encoding="utf-8")
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"{description}: start marker is missing in {path}")
    end = text.find(end_marker, start + len(start_marker))
    if end < 0:
        raise RuntimeError(f"{description}: end marker is missing in {path}")
    region = text[start:end]
    count = region.count(old)
    if count != 1:
        raise RuntimeError(
            f"{description}: expected one exact regional match in {path}, found {count}"
        )
    region = region.replace(old, new, 1)
    path.write_text(text[:start] + region + text[end:], encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: patch-gzselaco-savegame-api-diagnostics-ios-m4i.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    codegen = root / "src" / "common" / "scripting" / "backend" / "codegen.cpp"

    for path in (src_cmake, codegen):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4I prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_RETAIL_SAVEGAME_SIGNATURES=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_RETAIL_SAVEGAME_SIGNATURES=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_SAVEGAME_API_DIAGNOSTICS=1)\n",
        "enable bounded retail save-menu API diagnostics",
    )

    replace_in_region(
        codegen,
        "FxExpression *FxIdentifier::Resolve(FCompileContext& ctx)\n",
        "foundit:\n",
        '    ScriptPosition.Message(MSG_ERROR, "Unknown identifier \'%s\'", Identifier.GetChars());\n'
        "    delete this;\n"
        "    return nullptr;\n",
        "#if defined(SELACO_IOS_SAVEGAME_API_DIAGNOSTICS)\n"
        "    const char *ownerClass = ctx.Class == nullptr\n"
        "        ? \"<none>\"\n"
        "        : ctx.Class->TypeName.GetChars();\n"
        "    const char *ownerFunction = ctx.Function == nullptr\n"
        "        ? \"<none>\"\n"
        "        : ctx.Function->SymbolName.GetChars();\n"
        "    const char *selfClass = (ctx.Function == nullptr ||\n"
        "        ctx.Function->Variants[0].SelfClass == nullptr)\n"
        "        ? \"<none>\"\n"
        "        : ctx.Function->Variants[0].SelfClass->TypeName.GetChars();\n"
        "    ScriptPosition.Message(\n"
        "        MSG_ERROR,\n"
        "        \"Unknown identifier '%s' [SELACO_IOS_M4I class=%s function=%s self=%s]\",\n"
        "        Identifier.GetChars(), ownerClass, ownerFunction, selfClass);\n"
        "#else\n"
        "    ScriptPosition.Message(MSG_ERROR, \"Unknown identifier '%s'\", Identifier.GetChars());\n"
        "#endif\n"
        "    delete this;\n"
        "    return nullptr;\n",
        "augment unresolved identifiers with their retail script ownership context",
    )

    replace_in_region(
        codegen,
        "FxExpression *FxVMFunctionCall::Resolve(FCompileContext& ctx)\n",
        "\t\tbool isvararg = (argtypes.Last() == nullptr);\n",
        '\t\t\tScriptPosition.Message(MSG_ERROR, "Too many arguments in call to %s", Function->SymbolName.GetChars());\n'
        "\t\t\tdelete this;\n"
        "\t\t\treturn nullptr;\n",
        "#if defined(SELACO_IOS_SAVEGAME_API_DIAGNOSTICS)\n"
        "            FString expectedTypes;\n"
        "            for (unsigned index = implicit; index < argtypes.Size(); ++index)\n"
        "            {\n"
        "                if (index != implicit) expectedTypes += \",\";\n"
        "                expectedTypes += argtypes[index] == nullptr\n"
        "                    ? \"<vararg>\"\n"
        "                    : argtypes[index]->DescriptiveName();\n"
        "            }\n"
        "            if (expectedTypes.IsEmpty()) expectedTypes = \"<none>\";\n"
        "\n"
        "            FString actualTypes;\n"
        "            for (unsigned index = 0; index < ArgList.Size(); ++index)\n"
        "            {\n"
        "                if (index != 0) actualTypes += \",\";\n"
        "                if (ArgList[index] == nullptr)\n"
        "                {\n"
        "                    actualTypes += \"<null>\";\n"
        "                    continue;\n"
        "                }\n"
        "                ArgList[index] = ArgList[index]->Resolve(ctx);\n"
        "                if (ArgList[index] == nullptr || ArgList[index]->ValueType == nullptr)\n"
        "                {\n"
        "                    actualTypes += \"<unresolved>\";\n"
        "                }\n"
        "                else\n"
        "                {\n"
        "                    actualTypes += ArgList[index]->ValueType->DescriptiveName();\n"
        "                }\n"
        "            }\n"
        "            if (actualTypes.IsEmpty()) actualTypes = \"<none>\";\n"
        "\n"
        "            const char *callerClass = ctx.Class == nullptr\n"
        "                ? \"<none>\"\n"
        "                : ctx.Class->TypeName.GetChars();\n"
        "            const char *callerFunction = ctx.Function == nullptr\n"
        "                ? \"<none>\"\n"
        "                : ctx.Function->SymbolName.GetChars();\n"
        "            const char *targetClass = Function->OwningClass == nullptr\n"
        "                ? \"<none>\"\n"
        "                : Function->OwningClass->TypeName.GetChars();\n"
        "            const unsigned declaredExplicit = argtypes.Size() >= implicit\n"
        "                ? unsigned(argtypes.Size() - implicit)\n"
        "                : 0;\n"
        "            ScriptPosition.Message(\n"
        "                MSG_ERROR,\n"
        "                \"Too many arguments in call to %s \"\n"
        "                \"[SELACO_IOS_M4I caller_class=%s caller_function=%s \"\n"
        "                \"target_class=%s actual_count=%u declared_explicit=%u \"\n"
        "                \"implicit=%u expected_types=%s actual_types=%s]\",\n"
        "                Function->SymbolName.GetChars(), callerClass, callerFunction,\n"
        "                targetClass, unsigned(ArgList.Size()), declaredExplicit, implicit,\n"
        "                expectedTypes.GetChars(), actualTypes.GetChars());\n"
        "#else\n"
        "            ScriptPosition.Message(MSG_ERROR, \"Too many arguments in call to %s\", Function->SymbolName.GetChars());\n"
        "#endif\n"
        "            delete this;\n"
        "            return nullptr;\n",
        "report the retail DoSave caller, target, counts, and resolvable argument types",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
