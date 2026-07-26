#!/usr/bin/env python3
"""Add bounded retail save-menu API diagnostics after the M4H physical pass."""

from __future__ import annotations

import pathlib
import re
import sys


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{description}: expected one exact match in {path}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def replace_regex_in_region(
    path: pathlib.Path,
    start_marker: str,
    end_marker: str,
    pattern: str,
    replacement: str,
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
    updated, count = re.subn(pattern, replacement, region, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(
            f"{description}: expected one structural match in {path}, found {count}"
        )
    path.write_text(text[:start] + updated + text[end:], encoding="utf-8")


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

    identifier_resolve_marker = (
        "FxExpression *FxIdentifier::Resolve(FCompileContext& ctx)\n"
    )
    identifier_helper = """#if defined(SELACO_IOS_SAVEGAME_API_DIAGNOSTICS)
static void ReportSelacoIOSM4IUnknownIdentifier(
\tFScriptPosition &position,
\tconst FName &identifier,
\tFCompileContext &ctx)
{
\tconst char *ownerClass = ctx.Class == nullptr
\t\t? "<none>"
\t\t: ctx.Class->TypeName.GetChars();
\tconst char *ownerFunction = ctx.Function == nullptr
\t\t? "<none>"
\t\t: ctx.Function->SymbolName.GetChars();
\tconst char *selfClass = (ctx.Function == nullptr ||
\t\tctx.Function->Variants[0].SelfClass == nullptr)
\t\t? "<none>"
\t\t: ctx.Function->Variants[0].SelfClass->TypeName.GetChars();
\tposition.Message(
\t\tMSG_ERROR,
\t\t"Unknown identifier '%s' [SELACO_IOS_M4I class=%s function=%s self=%s]",
\t\tidentifier.GetChars(), ownerClass, ownerFunction, selfClass);
}
#endif

"""
    replace_once(
        codegen,
        identifier_resolve_marker,
        identifier_helper + identifier_resolve_marker,
        "add a goto-safe unresolved identifier diagnostic helper",
    )

    identifier_replacement = """#if defined(SELACO_IOS_SAVEGAME_API_DIAGNOSTICS)
\tReportSelacoIOSM4IUnknownIdentifier(ScriptPosition, Identifier, ctx);
#else
\tScriptPosition.Message(MSG_ERROR, "Unknown identifier '%s'", Identifier.GetChars());
#endif
\tdelete this;
\treturn nullptr;
"""
    replace_regex_in_region(
        codegen,
        identifier_resolve_marker,
        "foundit:\n",
        r'^[ \t]*ScriptPosition\.Message\(MSG_ERROR, "Unknown identifier \'%s\'", Identifier\.GetChars\(\)\);\n'
        r'^[ \t]*delete this;\n'
        r'^[ \t]*return nullptr;\n',
        identifier_replacement,
        "augment unresolved identifiers with their retail script ownership context",
    )

    call_replacement = """#if defined(SELACO_IOS_SAVEGAME_API_DIAGNOSTICS)
\t\t\tFString expectedTypes;
\t\t\tfor (unsigned index = implicit; index < argtypes.Size(); ++index)
\t\t\t{
\t\t\t\tif (index != implicit) expectedTypes += ",";
\t\t\t\texpectedTypes += argtypes[index] == nullptr
\t\t\t\t\t? "<vararg>"
\t\t\t\t\t: argtypes[index]->DescriptiveName();
\t\t\t}
\t\t\tif (expectedTypes.IsEmpty()) expectedTypes = "<none>";

\t\t\tFString actualTypes;
\t\t\tfor (unsigned index = 0; index < ArgList.Size(); ++index)
\t\t\t{
\t\t\t\tif (index != 0) actualTypes += ",";
\t\t\t\tif (ArgList[index] == nullptr)
\t\t\t\t{
\t\t\t\t\tactualTypes += "<null>";
\t\t\t\t\tcontinue;
\t\t\t\t}
\t\t\t\tArgList[index] = ArgList[index]->Resolve(ctx);
\t\t\t\tif (ArgList[index] == nullptr || ArgList[index]->ValueType == nullptr)
\t\t\t\t{
\t\t\t\t\tactualTypes += "<unresolved>";
\t\t\t\t}
\t\t\t\telse
\t\t\t\t{
\t\t\t\t\tactualTypes += ArgList[index]->ValueType->DescriptiveName();
\t\t\t\t}
\t\t\t}
\t\t\tif (actualTypes.IsEmpty()) actualTypes = "<none>";

\t\t\tconst char *callerClass = ctx.Class == nullptr
\t\t\t\t? "<none>"
\t\t\t\t: ctx.Class->TypeName.GetChars();
\t\t\tconst char *callerFunction = ctx.Function == nullptr
\t\t\t\t? "<none>"
\t\t\t\t: ctx.Function->SymbolName.GetChars();
\t\t\tconst char *targetClass = Function->OwningClass == nullptr
\t\t\t\t? "<none>"
\t\t\t\t: Function->OwningClass->TypeName.GetChars();
\t\t\tconst unsigned declaredExplicit = argtypes.Size() >= implicit
\t\t\t\t? unsigned(argtypes.Size() - implicit)
\t\t\t\t: 0;
\t\t\tScriptPosition.Message(
\t\t\t\tMSG_ERROR,
\t\t\t\t"Too many arguments in call to %s "
\t\t\t\t"[SELACO_IOS_M4I caller_class=%s caller_function=%s "
\t\t\t\t"target_class=%s actual_count=%u declared_explicit=%u "
\t\t\t\t"implicit=%u expected_types=%s actual_types=%s]",
\t\t\t\tFunction->SymbolName.GetChars(), callerClass, callerFunction,
\t\t\t\ttargetClass, unsigned(ArgList.Size()), declaredExplicit, implicit,
\t\t\t\texpectedTypes.GetChars(), actualTypes.GetChars());
#else
\t\t\tScriptPosition.Message(MSG_ERROR, "Too many arguments in call to %s", Function->SymbolName.GetChars());
#endif
\t\t\tdelete this;
\t\t\treturn nullptr;
"""
    replace_regex_in_region(
        codegen,
        "FxExpression *FxVMFunctionCall::Resolve(FCompileContext& ctx)\n",
        "\t\tbool isvararg = (argtypes.Last() == nullptr);\n",
        r'^[ \t]*ScriptPosition\.Message\(MSG_ERROR, "Too many arguments in call to %s", Function->SymbolName\.GetChars\(\)\);\n'
        r'^[ \t]*delete this;\n'
        r'^[ \t]*return nullptr;\n',
        call_replacement,
        "report the retail DoSave caller, target, counts, and resolvable argument types",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
