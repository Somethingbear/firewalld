#!/usr/bin/env python3
import json
import shutil
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
PUBLIC_XML = BASE_DIR / "public.xml"
AH_JSON = BASE_DIR / "ah.json"
CZ_JSON = BASE_DIR / "cz.json"
BACKUP_XML = BASE_DIR / "public.xml.before-subip.bak"

DEFAULT_DESTINATION_IP = "112.121.186.186"
AH_DESTINATION_IP = "112.121.186.189"
CZ_DESTINATION_IP = "112.121.186.187"


def load_dest_set(json_path: Path) -> set[str]:
    rows = json.loads(json_path.read_text(encoding="utf-8"))
    dests: set[str] = set()

    for row in rows:
        raw_config = row.get("config") or "{}"
        try:
            config = json.loads(raw_config)
        except json.JSONDecodeError as exc:
            raise ValueError(f"{json_path.name} id={row.get('id')} config 不是有效 JSON: {exc}") from exc

        for dest in config.get("dest", []) or []:
            if not isinstance(dest, str):
                continue
            if ":" not in dest:
                continue
            dests.add(dest)

    return dests


def build_rule(forward_port: ET.Element, destination_ip: str) -> ET.Element:
    rule = ET.Element("rule", {"family": "ipv4"})
    ET.SubElement(rule, "destination", {"address": destination_ip})

    attrs = {}
    for key in ("port", "protocol", "to-port", "to-addr"):
        value = forward_port.get(key)
        if value is not None:
            attrs[key] = value

    ET.SubElement(rule, "forward-port", attrs)
    return rule


def forward_dest(forward_port: ET.Element) -> str | None:
    to_addr = forward_port.get("to-addr")
    to_port = forward_port.get("to-port")
    if not to_addr or not to_port:
        return None
    return f"{to_addr}:{to_port}"


def get_source_tree() -> tuple[ET.ElementTree, Path]:
    tree = ET.parse(PUBLIC_XML)
    root = tree.getroot()
    if any(child.tag == "forward-port" for child in root):
        return tree, PUBLIC_XML

    if not BACKUP_XML.exists():
        raise RuntimeError("public.xml 已经转换过，且找不到原始备份 public.xml.before-subip.bak")

    return ET.parse(BACKUP_XML), BACKUP_XML


def convert_public_xml() -> tuple[Counter, Path]:
    ah_dests = load_dest_set(AH_JSON)
    cz_dests = load_dest_set(CZ_JSON)
    overlap_dests = ah_dests & cz_dests

    tree, source_xml = get_source_tree()
    root = tree.getroot()

    new_children = []
    stats = Counter()

    for child in list(root):
        if child.tag != "forward-port":
            new_children.append(child)
            continue

        stats["forward_port_total"] += 1
        dest = forward_dest(child)
        destination_ip = DEFAULT_DESTINATION_IP

        if dest in ah_dests:
            destination_ip = AH_DESTINATION_IP
            stats["matched_forward_port"] += 1
            stats["matched_ah_forward_port"] += 1
            if dest in overlap_dests:
                stats["overlap_forward_port"] += 1
        elif dest in cz_dests:
            destination_ip = CZ_DESTINATION_IP
            stats["matched_forward_port"] += 1
            stats["matched_cz_forward_port"] += 1
        else:
            stats["default_forward_port"] += 1

        new_children.append(build_rule(child, destination_ip))

    root[:] = new_children

    if stats["forward_port_total"] == 0:
        raise RuntimeError("public.xml 中没有找到顶层 forward-port，可能已经转换过了")

    if source_xml == PUBLIC_XML and not BACKUP_XML.exists():
        shutil.copy2(PUBLIC_XML, BACKUP_XML)

    ET.indent(tree, space="  ")
    tree.write(PUBLIC_XML, encoding="utf-8", xml_declaration=True, short_empty_elements=True)

    return stats, source_xml


def main() -> None:
    stats, source_xml = convert_public_xml()
    print(f"已转换 public.xml: {PUBLIC_XML}")
    print(f"转换源文件: {source_xml}")
    print(f"原始备份: {BACKUP_XML}")
    print(f"转换的 forward-port 行数: {stats['forward_port_total']}")
    print(f"匹配 ah.json 后走 {AH_DESTINATION_IP} 的行数: {stats['matched_ah_forward_port']}")
    print(f"匹配 cz.json 后走 {CZ_DESTINATION_IP} 的行数: {stats['matched_cz_forward_port']}")
    print(f"ah/cz 重叠且按 ah 处理的行数: {stats['overlap_forward_port']}")
    print(f"剩余走 {DEFAULT_DESTINATION_IP} 的行数: {stats['default_forward_port']}")


if __name__ == "__main__":
    main()
