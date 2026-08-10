#!/usr/bin/env python3
"""Retain the Mach-O native class registry and guard it before ZScript startup."""

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
            "usage: patch-gzselaco-mach-class-registry-ios-m4d.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    dobject_h = root / "src" / "common" / "objects" / "dobject.h"
    d_main = root / "src" / "d_main.cpp"

    for path in (src_cmake, dobject_h, d_main):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4D prerequisite is missing: {path}")

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_TITLE_MENU_CLOSURE=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_TITLE_MENU_CLOSURE=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_MACH_CLASS_REGISTRY=1)\n",
        "enable the retained Mach-O native class registry",
    )

    replace_once(
        dobject_h,
        "#\tdefine _DECLARE_TI(cls) ClassReg * const cls::RegistrationInfoPtr __attribute__((section(SECTION_CREG))) = &cls::RegistrationInfo;\n",
        "#\tif defined(SELACO_IOS_MACH_CLASS_REGISTRY)\n"
        "#\t\tdefine _DECLARE_TI(cls) ClassReg * const cls::RegistrationInfoPtr __attribute__((used, section(SECTION_CREG))) = &cls::RegistrationInfo;\n"
        "#\telse\n"
        "#\t\tdefine _DECLARE_TI(cls) ClassReg * const cls::RegistrationInfoPtr __attribute__((section(SECTION_CREG))) = &cls::RegistrationInfo;\n"
        "#\tendif\n",
        "retain ClassReg pointers in the Mach-O creg section",
    )

    replace_once(
        d_main,
        "\t\tPClass::StaticInit();\n"
        "#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n"
        "\t\tSelacoIOSReportLicensedAssetProbe(\"pclass_static_init_passed\", \"PClass::StaticInit\");\n"
        "\t\tSelacoIOSReportLicensedAssetProbe(\"ptype_static_init_entered\", \"PType::StaticInit\");\n"
        "#endif\n"
        "\t\tPType::StaticInit();\n",
        "\t\tPClass::StaticInit();\n"
        "#if defined(SELACO_IOS_MACH_CLASS_REGISTRY)\n"
        "\t\tif (RUNTIME_CLASS(DObject) == nullptr)\n"
        "\t\t{\n"
        "\t\t\tSelacoIOSReportLicensedAssetProbe(\n"
        "\t\t\t\t\"native_class_registry_failed\",\n"
        "\t\t\t\t\"DObject is absent after PClass::StaticInit; Mach-O __DATA,creg was not retained or enumerated\");\n"
        "\t\t\tI_FatalError(\"SelacoiOS native class registry is unavailable\");\n"
        "\t\t}\n"
        "\t\tSelacoIOSReportLicensedAssetProbe(\n"
        "\t\t\t\"native_class_registry_passed\",\n"
        "\t\t\tRUNTIME_CLASS(DObject)->TypeName.GetChars());\n"
        "#endif\n"
        "#if defined(SELACO_IOS_ENGINE_INIT_PROBE)\n"
        "\t\tSelacoIOSReportLicensedAssetProbe(\"pclass_static_init_passed\", \"PClass::StaticInit\");\n"
        "\t\tSelacoIOSReportLicensedAssetProbe(\"ptype_static_init_entered\", \"PType::StaticInit\");\n"
        "#endif\n"
        "\t\tPType::StaticInit();\n",
        "validate the native class registry before PType and ZScript startup",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
