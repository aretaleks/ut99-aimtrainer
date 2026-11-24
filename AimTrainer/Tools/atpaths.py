"""Folders on this computer that the tools use, from AimTrainer/Tools/paths.local.ini
(not in the repository) or environment variables.

    [paths]
    ; the UT install whose System (and System\\Demos) folder has your demos,
    ; and whose Maps / Textures / Sounds / Music / Cache the test runs read
    main_install = C:\\Games\\UnrealTournament
    ; a UT 469e install with the UnrealEd MCP map generator (only for make_range_map.py)
    mapping_install = C:\\Games\\UT469e_mapping
"""
import configparser
import os

HERE = os.path.dirname(os.path.abspath(__file__))
LOCAL = os.path.join(HERE, "paths.local.ini")


def get(key, env=None):
    if env and os.environ.get(env):
        return os.environ[env]
    if os.path.exists(LOCAL):
        cp = configparser.ConfigParser()
        cp.read(LOCAL, encoding="utf-8")
        if cp.has_option("paths", key):
            return cp.get("paths", key).strip()
    raise SystemExit("Set '%s' in %s (see atpaths.py)%s" % (key, LOCAL, " or the %s environment variable" % env if env else ""))
