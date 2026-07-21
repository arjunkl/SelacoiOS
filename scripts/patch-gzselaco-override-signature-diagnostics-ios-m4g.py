#!/usr/bin/env python3
"""Report the exact retail override owner and prototype at the M4G boundary."""

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
            "usage: patch-gzselaco-override-signature-diagnostics-ios-m4g.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    compiler = (
        root
        / "src"
        / "common"
        / "scripting"
        / "frontend"
        / "zcc_compile.cpp"
    )
    src_cmake = root / "src" / "CMakeLists.txt"

    for path in (compiler, src_cmake):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4G prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_RETAIL_SAVEGAME_VIRTUALS=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_RETAIL_SAVEGAME_VIRTUALS=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_OVERRIDE_SIGNATURE_DIAGNOSTICS=1)\n",
        "enable retail override signature diagnostics",
    )

    old = '''\t\t\t\t\tif (virtindex == -1)\n\t\t\t\t\t{\n\t\t\t\t\t\tError(f, "Attempt to override non-existent virtual function %s", FName(f->Name).GetChars());\n\t\t\t\t\t}\n'''
    new = '''\t\t\t\t\tif (virtindex == -1)\n\t\t\t\t\t{\n#if defined(SELACO_IOS_OVERRIDE_SIGNATURE_DIAGNOSTICS)\n\t\t\t\t\t\tFString returnTypes;\n\t\t\t\t\t\tfor (unsigned index = 0; index < rets.Size(); ++index)\n\t\t\t\t\t\t{\n\t\t\t\t\t\t\tif (index != 0) returnTypes += ",";\n\t\t\t\t\t\t\treturnTypes += rets[index] == nullptr ? "<inferred>" : rets[index]->DescriptiveName();\n\t\t\t\t\t\t}\n\t\t\t\t\t\tif (returnTypes.IsEmpty()) returnTypes = "void";\n\n\t\t\t\t\t\tFString argumentTypes;\n\t\t\t\t\t\tfor (unsigned index = static_cast<unsigned>(implicitargs); index < args.Size(); ++index)\n\t\t\t\t\t\t{\n\t\t\t\t\t\t\tif (!argumentTypes.IsEmpty()) argumentTypes += ",";\n\t\t\t\t\t\t\targumentTypes += args[index] == nullptr ? "<inferred>" : args[index]->DescriptiveName();\n\t\t\t\t\t\t}\n\t\t\t\t\t\tif (argumentTypes.IsEmpty()) argumentTypes = "none";\n\n\t\t\t\t\t\tconst char *parentName = clstype->ParentClass == nullptr\n\t\t\t\t\t\t\t? "<none>"\n\t\t\t\t\t\t\t: clstype->ParentClass->TypeName.GetChars();\n\t\t\t\t\t\tError(\n\t\t\t\t\t\t\tf,\n\t\t\t\t\t\t\t"Attempt to override non-existent virtual function %s "\n\t\t\t\t\t\t\t"[SELACO_IOS_M4G class=%s parent=%s returns=%s args=%s implicit=%d flags=0x%x]",\n\t\t\t\t\t\t\tFName(f->Name).GetChars(),\n\t\t\t\t\t\t\tclstype->TypeName.GetChars(),\n\t\t\t\t\t\t\tparentName,\n\t\t\t\t\t\t\treturnTypes.GetChars(),\n\t\t\t\t\t\t\targumentTypes.GetChars(),\n\t\t\t\t\t\t\timplicitargs,\n\t\t\t\t\t\t\tunsigned(varflags));\n#else\n\t\t\t\t\t\tError(f, "Attempt to override non-existent virtual function %s", FName(f->Name).GetChars());\n#endif\n\t\t\t\t\t}\n'''
    replace_once(
        compiler,
        old,
        new,
        "augment the missing-override diagnostic with owner and prototype data",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
