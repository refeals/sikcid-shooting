#!/usr/bin/env python3
"""Merges <game> entries into an EmulationStation gamelist.xml (Batocera).

Usage:  python3 merge_gamelist.py <gamelist.xml> <entries.xml>

Run by `./build.sh --deploy` ON the Batocera (its own python3), so the PC
needs no Python. Each <game> in entries.xml is matched to the target by its
<path>:
  * match: the entry's tags (name, desc, image...) replace the target's; tags
    the entry does not have (playcount, lastplayed, favorite...) are kept;
  * no match: the game is appended.
Every other game in the target is left untouched. The target is created if
missing, copied once to <gamelist.xml>.bak before its first change, and
written atomically (temp file + rename). Only the standard library is used.
"""
import copy
import os
import shutil
import sys
import xml.etree.ElementTree as ET


def norm(path, base):
    # "./X.sh" and "/userdata/roms/ports/X.sh" are the same game.
    path = (path or "").strip()
    if path.startswith(base + "/"):
        return path[len(base) + 1:]
    return path[2:] if path.startswith("./") else path


def indent(elem, level=0):
    # ET.indent only exists from Python 3.9 on.
    pad = "\n" + "\t" * level
    if len(elem):
        if not elem.text or not elem.text.strip():
            elem.text = pad + "\t"
        for child in elem:
            indent(child, level + 1)
        if not child.tail or not child.tail.strip():
            child.tail = pad
    if level and (not elem.tail or not elem.tail.strip()):
        elem.tail = pad


def main(argv):
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2])
        return 2
    target, entries = argv[1], argv[2]

    try:
        new_games = ET.parse(entries).getroot().findall("game")
    except (OSError, ET.ParseError) as e:
        print("gamelist: entrada invalida (%s): %s" % (entries, e))
        return 1

    existed = os.path.exists(target)
    if existed:
        try:
            tree = ET.parse(target)
        except ET.ParseError as e:
            # Never rewrite a file we could not read: it holds other games.
            print("gamelist: %s ilegivel, nada alterado: %s" % (target, e))
            return 1
        root = tree.getroot()
    else:
        root = ET.Element("gameList")
        tree = ET.ElementTree(root)

    base = os.path.dirname(os.path.abspath(target))
    by_path = {norm(g.findtext("path"), base): g for g in root.findall("game")}
    changed = False
    for game in new_games:
        cur = by_path.get(norm(game.findtext("path"), base))
        if cur is None:
            root.append(copy.deepcopy(game))
            changed = True
            continue
        for tag in game:
            old = cur.find(tag.tag)
            if old is None:
                cur.append(copy.deepcopy(tag))
                changed = True
            elif (old.text or "") != (tag.text or ""):
                old.text = tag.text
                changed = True

    if not changed:
        print("gamelist: ja atualizado")
        return 0

    if existed and not os.path.exists(target + ".bak"):
        shutil.copy2(target, target + ".bak")
    indent(root)
    tmp = target + ".tmp"
    tree.write(tmp, encoding="utf-8", xml_declaration=True)
    os.replace(tmp, target)
    print("gamelist: %s %s" % (target, "atualizado" if existed else "criado"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
