#!/usr/bin/env python3
"""Add bounded M4J save-slot context and no-write DoSave diagnostics."""

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
            "usage: patch-gzselaco-savegame-context-diagnostics-ios-m4j.py "
            "<GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    codegen_h = root / "src" / "common" / "scripting" / "backend" / "codegen.h"
    codegen_cpp = root / "src" / "common" / "scripting" / "backend" / "codegen.cpp"
    zcc_compile = (
        root / "src" / "common" / "scripting" / "frontend" / "zcc_compile.cpp"
    )
    loadsavemenu = (
        root
        / "wadsrc"
        / "static"
        / "zscript"
        / "engine"
        / "ui"
        / "menu"
        / "loadsavemenu.zs"
    )
    savegamemanager = root / "src" / "common" / "menu" / "savegamemanager.cpp"

    for path in (
        src_cmake,
        codegen_h,
        codegen_cpp,
        zcc_compile,
        loadsavemenu,
        savegamemanager,
    ):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4J prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_API_DIAGNOSTICS=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_API_DIAGNOSTICS=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE "
        "SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS=1)\n",
        "enable bounded M4J save-slot context diagnostics",
    )

    replace_once(
        codegen_h,
        "\tbool isresolved = false;\n"
        "\tbool NeedResult = true;\t// should be set to false if not needed and "
        "properly handled by all nodes for their subnodes to eliminate redundant code\n"
        "\tEFxType ExprType;\n\n"
        "\tvoid *operator new(size_t size)\n",
        "\tbool isresolved = false;\n"
        "\tbool NeedResult = true;\t// should be set to false if not needed and "
        "properly handled by all nodes for their subnodes to eliminate redundant code\n"
        "\tEFxType ExprType;\n\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\tconst char *SelacoIOSM4JNode = \"<unknown>\";\n"
        "\tconst char *SelacoIOSM4JUsage = \"<unknown>\";\n"
        "\tconst char *SelacoIOSM4JExpectedCategory = \"<unknown>\";\n"
        "\tPType *SelacoIOSM4JExpectedType = nullptr;\n\n"
        "\tvoid SetSelacoIOSM4JContext(\n"
        "\t\tconst char *usage,\n"
        "\t\tconst char *expectedCategory = \"<unknown>\",\n"
        "\t\tPType *expectedType = nullptr)\n"
        "\t{\n"
        "\t\tSelacoIOSM4JUsage = usage == nullptr ? \"<unknown>\" : usage;\n"
        "\t\tSelacoIOSM4JExpectedCategory = expectedCategory == nullptr\n"
        "\t\t\t? \"<unknown>\"\n"
        "\t\t\t: expectedCategory;\n"
        "\t\tSelacoIOSM4JExpectedType = expectedType;\n"
        "\t}\n"
        "#endif\n\n"
        "\tvoid *operator new(size_t size)\n",
        "add diagnostic-only expression context metadata",
    )

    replace_once(
        codegen_cpp,
        "FxIdentifier::FxIdentifier(FName name, const FScriptPosition &pos)\n"
        ": FxExpression(EFX_Identifier, pos)\n"
        "{\n"
        "\tIdentifier = name;\n"
        "}\n",
        "FxIdentifier::FxIdentifier(FName name, const FScriptPosition &pos)\n"
        ": FxExpression(EFX_Identifier, pos)\n"
        "{\n"
        "\tIdentifier = name;\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\tSelacoIOSM4JNode = \"bare-identifier\";\n"
        "\tSetSelacoIOSM4JContext(\"read\");\n"
        "#endif\n"
        "}\n",
        "classify bare identifier nodes without source-text inspection",
    )

    old_identifier_helper = """#if defined(SELACO_IOS_SAVEGAME_API_DIAGNOSTICS)
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
    new_identifier_helper = """#if defined(SELACO_IOS_SAVEGAME_API_DIAGNOSTICS)
static void ReportSelacoIOSM4IUnknownIdentifier(
\tFScriptPosition &position,
\tconst FName &identifier,
\tFCompileContext &ctx,
\tFxExpression *expression)
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
#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)
\tFString parentChain;
\tFString infoFieldOwner = "<none>";
\tbool infoFieldFound = false;
\tauto classType = PType::toClass(ctx.Class);
\tPClass *chainClass = classType == nullptr ? nullptr : classType->Descriptor;
\tunsigned depth = 0;
\tfor (; chainClass != nullptr && depth < 8;
\t\tchainClass = chainClass->ParentClass, ++depth)
\t{
\t\tif (!parentChain.IsEmpty()) parentChain += ">";
\t\tparentChain += chainClass->TypeName.GetChars();
\t\tif (!infoFieldFound && chainClass->VMType != nullptr)
\t\t{
\t\t\tauto infoSymbol = chainClass->VMType->Symbols.FindSymbol(
\t\t\t\tFName("info"), false);
\t\t\tif (infoSymbol != nullptr &&
\t\t\t\tinfoSymbol->IsKindOf(RUNTIME_CLASS(PField)))
\t\t\t{
\t\t\t\tinfoFieldOwner = chainClass->TypeName.GetChars();
\t\t\t\tinfoFieldFound = true;
\t\t\t}
\t\t}
\t}
\tif (chainClass != nullptr) parentChain += ">...";
\tif (parentChain.IsEmpty()) parentChain = "<none>";
\tconst char *expectedType =
\t\texpression != nullptr && expression->SelacoIOSM4JExpectedType != nullptr
\t\t? expression->SelacoIOSM4JExpectedType->DescriptiveName()
\t\t: (expression == nullptr
\t\t\t? "<unknown>"
\t\t\t: expression->SelacoIOSM4JExpectedCategory);
\tposition.Message(
\t\tMSG_ERROR,
\t\t"Unknown identifier '%s' "
\t\t"[SELACO_IOS_M4J identifier=%s source=%s line=%d column=<unknown> "
\t\t"class=%s function=%s self=%s parent_chain=%s "
\t\t"info_field_owner=%s info_sibling=<unknown> node=%s usage=%s "
\t\t"expected_type=%s resolved_value_type=unresolved]",
\t\tidentifier.GetChars(), identifier.GetChars(),
\t\tposition.FileName.GetChars(), position.ScriptLine,
\t\townerClass, ownerFunction, selfClass, parentChain.GetChars(),
\t\tinfoFieldOwner.GetChars(),
\t\texpression == nullptr ? "<unknown>" : expression->SelacoIOSM4JNode,
\t\texpression == nullptr ? "<unknown>" : expression->SelacoIOSM4JUsage,
\t\texpectedType);
#else
\tposition.Message(
\t\tMSG_ERROR,
\t\t"Unknown identifier '%s' [SELACO_IOS_M4I class=%s function=%s self=%s]",
\t\tidentifier.GetChars(), ownerClass, ownerFunction, selfClass);
#endif
}
#endif

"""
    replace_once(
        codegen_cpp,
        old_identifier_helper,
        new_identifier_helper,
        "upgrade the goto-safe M4I helper with bounded M4J context",
    )

    replace_once(
        codegen_cpp,
        "\tReportSelacoIOSM4IUnknownIdentifier(ScriptPosition, Identifier, ctx);\n",
        "\tReportSelacoIOSM4IUnknownIdentifier("
        "ScriptPosition, Identifier, ctx, this);\n",
        "pass the unresolved bare identifier node to the M4J helper",
    )

    replace_once(
        codegen_cpp,
        "\tObject = left;\n"
        "\tExprType = EFX_MemberIdentifier;\n"
        "}\n",
        "\tObject = left;\n"
        "\tExprType = EFX_MemberIdentifier;\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\tSelacoIOSM4JNode = \"member-access\";\n"
        "\tSetSelacoIOSM4JContext(\"property-read\");\n"
        "#endif\n"
        "}\n",
        "classify member access nodes",
    )

    replace_once(
        codegen_cpp,
        "\telse\n"
        "\t{\n"
        "\t\tScriptPosition.Message(MSG_ERROR, \"Unknown identifier '%s'\", "
        "Identifier.GetChars());\n"
        "\t\tdelete object;\n"
        "\t\tobject = nullptr;\n"
        "\t\treturn nullptr;\n"
        "\t}\n"
        "}\n\n"
        "//==========================================================================\n"
        "//\n"
        "//\n"
        "//\n"
        "//==========================================================================\n\n"
        "FxMemberIdentifier::FxMemberIdentifier",
        "\telse\n"
        "\t{\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\tReportSelacoIOSM4IUnknownIdentifier("
        "ScriptPosition, Identifier, ctx, this);\n"
        "#else\n"
        "\t\tScriptPosition.Message(MSG_ERROR, \"Unknown identifier '%s'\", "
        "Identifier.GetChars());\n"
        "#endif\n"
        "\t\tdelete object;\n"
        "\t\tobject = nullptr;\n"
        "\t\treturn nullptr;\n"
        "\t}\n"
        "}\n\n"
        "//==========================================================================\n"
        "//\n"
        "//\n"
        "//\n"
        "//==========================================================================\n\n"
        "FxMemberIdentifier::FxMemberIdentifier",
        "add bounded member-access diagnostics while retaining the ordinary error",
    )

    replace_once(
        zcc_compile,
        "//==========================================================================\n"
        "//\n"
        "// Convert an AST node and its children\n"
        "//\n"
        "//==========================================================================\n\n"
        "FxExpression *ZCCCompiler::ConvertNode",
        "//==========================================================================\n"
        "//\n"
        "// Convert an AST node and its children\n"
        "//\n"
        "//==========================================================================\n\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "static FArgumentList &SetSelacoIOSM4JArgumentContexts(\n"
        "\tFArgumentList &args, const char *usage)\n"
        "{\n"
        "\tfor (auto expression : args)\n"
        "\t{\n"
        "\t\tif (expression != nullptr)\n"
        "\t\t\texpression->SetSelacoIOSM4JContext(usage, \"<from-call-signature>\");\n"
        "\t}\n"
        "\treturn args;\n"
        "}\n"
        "#endif\n\n"
        "FxExpression *ZCCCompiler::ConvertNode",
        "add an AST-only argument-context annotator",
    )

    replace_once(
        zcc_compile,
        "\t\tcase AST_ExprID:\n"
        "\t\t\t// The function name is a simple identifier.\n"
        "\t\t\treturn new FxFunctionCall("
        "static_cast<ZCC_ExprID *>(fcall->Function)->Identifier, NAME_None, "
        "std::move(ConvertNodeList(args, fcall->Parameters)), *ast);\n",
        "\t\tcase AST_ExprID:\n"
        "\t\t\t// The function name is a simple identifier.\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\t\treturn new FxFunctionCall("
        "static_cast<ZCC_ExprID *>(fcall->Function)->Identifier, NAME_None, "
        "std::move(SetSelacoIOSM4JArgumentContexts(\n"
        "\t\t\t\tConvertNodeList(args, fcall->Parameters),\n"
        "\t\t\t\tstatic_cast<ZCC_ExprID *>(fcall->Function)->Identifier == "
        "FName(\"Format\") ? \"format\" : \"call-arg\")), *ast);\n"
        "#else\n"
        "\t\t\treturn new FxFunctionCall("
        "static_cast<ZCC_ExprID *>(fcall->Function)->Identifier, NAME_None, "
        "std::move(ConvertNodeList(args, fcall->Parameters)), *ast);\n"
        "#endif\n",
        "classify plain function-call arguments",
    )

    replace_once(
        zcc_compile,
        "\t\t{\n"
        "\t\t\tauto ema = static_cast<ZCC_ExprMemberAccess *>(fcall->Function);\n"
        "\t\t\treturn new FxMemberFunctionCall(ConvertNode(ema->Left, true), "
        "ema->Right, std::move(ConvertNodeList(args, fcall->Parameters)), *ast);\n"
        "\t\t}\n",
        "\t\t{\n"
        "\t\t\tauto ema = static_cast<ZCC_ExprMemberAccess *>(fcall->Function);\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\t\treturn new FxMemberFunctionCall(ConvertNode(ema->Left, true), "
        "ema->Right, std::move(SetSelacoIOSM4JArgumentContexts(\n"
        "\t\t\t\tConvertNodeList(args, fcall->Parameters),\n"
        "\t\t\t\tema->Right == FName(\"Format\") ? \"format\" : \"call-arg\")), "
        "*ast);\n"
        "#else\n"
        "\t\t\treturn new FxMemberFunctionCall(ConvertNode(ema->Left, true), "
        "ema->Right, std::move(ConvertNodeList(args, fcall->Parameters)), *ast);\n"
        "#endif\n"
        "\t\t}\n",
        "classify member function-call and format arguments",
    )

    replace_once(
        zcc_compile,
        "\t\tauto op = binary->Operation;\n"
        "\t\tauto tok = Pex2Tok[op];\n"
        "\t\tswitch (op)\n",
        "\t\tauto op = binary->Operation;\n"
        "\t\tauto tok = Pex2Tok[op];\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\tswitch (op)\n"
        "\t\t{\n"
        "\t\tcase PEX_Assign:\n"
        "\t\tcase PEX_AddAssign:\n"
        "\t\tcase PEX_SubAssign:\n"
        "\t\tcase PEX_MulAssign:\n"
        "\t\tcase PEX_DivAssign:\n"
        "\t\tcase PEX_ModAssign:\n"
        "\t\tcase PEX_LshAssign:\n"
        "\t\tcase PEX_RshAssign:\n"
        "\t\tcase PEX_URshAssign:\n"
        "\t\tcase PEX_AndAssign:\n"
        "\t\tcase PEX_OrAssign:\n"
        "\t\tcase PEX_XorAssign:\n"
        "\t\t\tleft->SetSelacoIOSM4JContext(\n"
        "\t\t\t\tleft->ExprType == EFX_MemberIdentifier\n"
        "\t\t\t\t\t? \"property-write\"\n"
        "\t\t\t\t\t: \"write\");\n"
        "\t\t\tright->SetSelacoIOSM4JContext(\"assignment-source\");\n"
        "\t\t\tbreak;\n"
        "\t\tcase PEX_LT:\n"
        "\t\tcase PEX_LTEQ:\n"
        "\t\tcase PEX_GT:\n"
        "\t\tcase PEX_GTEQ:\n"
        "\t\tcase PEX_EQEQ:\n"
        "\t\tcase PEX_NEQ:\n"
        "\t\tcase PEX_APREQ:\n"
        "\t\tcase PEX_LTGTEQ:\n"
        "\t\tcase PEX_Is:\n"
        "\t\t\tleft->SetSelacoIOSM4JContext(\"comparison\", \"<comparable>\");\n"
        "\t\t\tright->SetSelacoIOSM4JContext(\"comparison\", \"<comparable>\");\n"
        "\t\t\tbreak;\n"
        "\t\tcase PEX_Concat:\n"
        "\t\t\tleft->SetSelacoIOSM4JContext(\"format\", \"<string-compatible>\");\n"
        "\t\t\tright->SetSelacoIOSM4JContext(\"format\", \"<string-compatible>\");\n"
        "\t\t\tbreak;\n"
        "\t\tcase PEX_Add:\n"
        "\t\tcase PEX_Sub:\n"
        "\t\tcase PEX_Mul:\n"
        "\t\tcase PEX_Div:\n"
        "\t\tcase PEX_Mod:\n"
        "\t\tcase PEX_Pow:\n"
        "\t\tcase PEX_LeftShift:\n"
        "\t\tcase PEX_RightShift:\n"
        "\t\tcase PEX_URightShift:\n"
        "\t\tcase PEX_BitAnd:\n"
        "\t\tcase PEX_BitOr:\n"
        "\t\tcase PEX_BitXor:\n"
        "\t\tcase PEX_CrossProduct:\n"
        "\t\tcase PEX_DotProduct:\n"
        "\t\t\tleft->SetSelacoIOSM4JContext(\"arithmetic\", \"<numeric>\");\n"
        "\t\t\tright->SetSelacoIOSM4JContext(\"arithmetic\", \"<numeric>\");\n"
        "\t\t\tbreak;\n"
        "\t\tdefault:\n"
        "\t\t\tbreak;\n"
        "\t\t}\n"
        "#endif\n"
        "\t\tswitch (op)\n",
        "classify immediate binary-expression use contexts",
    )

    replace_once(
        zcc_compile,
        "\t\t\t\tFxExpression *val = node->Init ? ConvertNode(node->Init) : nullptr;\n"
        "\t\t\t\tlist->Add(new FxLocalVariableDeclaration("
        "type, node->Name, val, 0, *node));\t// todo: Handle flags in the grammar.\n",
        "\t\t\t\tFxExpression *val = node->Init ? ConvertNode(node->Init) : nullptr;\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\t\t\tif (val != nullptr)\n"
        "\t\t\t\t\tval->SetSelacoIOSM4JContext("
        "\"assignment-source\", type->DescriptiveName(), type);\n"
        "#endif\n"
        "\t\t\t\tlist->Add(new FxLocalVariableDeclaration("
        "type, node->Name, val, 0, *node));\t// todo: Handle flags in the grammar.\n",
        "record exact local-initializer target types",
    )

    replace_once(
        codegen_cpp,
        "\tValueType = Base->ValueType;\n\n"
        "\tSAFE_RESOLVE(Right, ctx);\n",
        "\tValueType = Base->ValueType;\n\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\tRight->SetSelacoIOSM4JContext("
        "\"assignment-source\", ValueType->DescriptiveName(), ValueType);\n"
        "#endif\n"
        "\tSAFE_RESOLVE(Right, ctx);\n",
        "record exact assignment-source target types before resolution",
    )

    replace_once(
        codegen_cpp,
        "\t\t\tassert(ArgList[i]);\n\n"
        "\t\t\tFxExpression *x = nullptr;\n",
        "\t\t\tassert(ArgList[i]);\n\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\t\t\tArgList[i]->SelacoIOSM4JExpectedCategory = "
        "type->DescriptiveName();\n"
        "\t\t\tArgList[i]->SelacoIOSM4JExpectedType = type;\n"
        "#endif\n"
        "\t\t\tFxExpression *x = nullptr;\n",
        "record exact call-argument target types before resolution",
    )

    replace_once(
        codegen_cpp,
        "isresolved:\n"
        "\tbool error = false;\n",
        "isresolved:\n"
        "#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)\n"
        "\tif (cls != nullptr && cls->TypeName == FName(\"SavegameManager\") &&\n"
        "\t\tMethodName == FName(\"DoSave\") && ArgList.Size() == 3)\n"
        "\t{\n"
        "\t\tconst char *callerClass = ctx.Class == nullptr\n"
        "\t\t\t? \"<none>\"\n"
        "\t\t\t: ctx.Class->TypeName.GetChars();\n"
        "\t\tconst char *callerFunction = ctx.Function == nullptr\n"
        "\t\t\t? \"<none>\"\n"
        "\t\t\t: ctx.Function->SymbolName.GetChars();\n"
        "\t\tScriptPosition.Message(\n"
        "\t\t\tMSG_WARNING,\n"
        "\t\t\t\"SELACO_IOS_M4J_DOSAVE_ADAPTER caller_class=%s \"\n"
        "\t\t\t\"caller_function=%s target_class=%s actual_count=3 \"\n"
        "\t\t\t\"mapped_to=SelacoIOSM4JDoSaveDiagnostic no_write=1\",\n"
        "\t\t\tcallerClass, callerFunction, cls->TypeName.GetChars());\n"
        "\t\tMethodName = FName(\"SelacoIOSM4JDoSaveDiagnostic\");\n"
        "\t}\n"
        "#endif\n"
        "\tbool error = false;\n",
        "map only the exact three-argument SavegameManager call to no-write code",
    )

    original_dosave_declaration = (
        "\tnative void DoSave(int Selected, String savegamestring);\n"
    )
    replace_once(
        loadsavemenu,
        original_dosave_declaration,
        original_dosave_declaration
        + "\t// SELACO_IOS_M4J diagnostic-only; compiler adapter target.\n"
        + "\tnative void SelacoIOSM4JDoSaveDiagnostic("
        "int Selected, String savegamestring, int diagnosticValue);\n",
        "add a separately named diagnostic native entry point",
    )

    original_dosave_thunk = """DEFINE_ACTION_FUNCTION(FSavegameManager, DoSave)
{
\tPARAM_SELF_STRUCT_PROLOGUE(FSavegameManagerBase);
\tPARAM_INT(sel);
\tPARAM_STRING(name);
\tself->DoSave(sel, name.GetChars());
\treturn 0;
}
"""
    diagnostic_dosave_thunk = """
#if defined(SELACO_IOS_SAVEGAME_CONTEXT_DIAGNOSTICS)
DEFINE_ACTION_FUNCTION(FSavegameManager, SelacoIOSM4JDoSaveDiagnostic)
{
\tPARAM_SELF_STRUCT_PROLOGUE(FSavegameManagerBase);
\tPARAM_INT(sel);
\tPARAM_STRING(name);
\tPARAM_INT(diagnosticValue);
\tPrintf(
\t\t"SELACO_IOS_M4J_DOSAVE_NO_WRITE selected=%d third=%d "
\t\t"title_length=%u write_attempted=0 abort=recoverable\\n",
\t\tsel, diagnosticValue, unsigned(name.Len()));
\tI_Error(
\t\t"SELACO_IOS_M4J_DOSAVE_NO_WRITE bounded diagnostic abort "
\t\t"before save write");
}
#endif
"""
    replace_once(
        savegamemanager,
        original_dosave_thunk,
        original_dosave_thunk + diagnostic_dosave_thunk,
        "add the value-logging recoverable no-write native target",
    )

    require_text(
        codegen_cpp,
        '#else\n\tScriptPosition.Message(MSG_ERROR, "Unknown identifier \'%s\'", '
        "Identifier.GetChars());\n#endif",
        "ordinary bare-identifier diagnostic",
    )
    require_text(
        loadsavemenu,
        original_dosave_declaration,
        "original public two-argument DoSave declaration",
    )
    require_text(
        savegamemanager,
        original_dosave_thunk,
        "original public two-argument DoSave native thunk",
    )

    patched_save_text = savegamemanager.read_text(encoding="utf-8")
    diagnostic_start = patched_save_text.index(
        "DEFINE_ACTION_FUNCTION(FSavegameManager, "
        "SelacoIOSM4JDoSaveDiagnostic)"
    )
    diagnostic_end = patched_save_text.index("#endif", diagnostic_start)
    diagnostic_region = patched_save_text[diagnostic_start:diagnostic_end]
    forbidden_calls = (
        "self->DoSave(",
        "PerformSaveGame(",
        "G_SaveGame(",
        "G_DoSaveGame(",
        "RemoveSaveSlot(",
        "DeleteSave",
    )
    for forbidden in forbidden_calls:
        if forbidden in diagnostic_region:
            raise RuntimeError(
                "diagnostic DoSave path is not no-write: "
                f"found forbidden call {forbidden}"
            )

    print(
        "SELACO_IOS_M4J patch applied: AST context diagnostics and "
        "recoverable no-write DoSave adapter"
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
