# PolishForever

WoW: Forever (Classic) addon that shows quest, gossip and (later) item, spell, skill and menu text in Polish,
with a toggle per category (`/pl`).

The code is in this repo. The translation data and fonts are **not**: they come from the WoWpoPolsku
translation pack and our own machine translations, and are generated locally by the pipeline in the parent
project (`tools/build_addon_data.py`, which writes `Data/*.lua` and `Fonts/`). Without them the addon loads
but has nothing to show.

Commands: `/pl` settings, `/pl status`, `/pl <module> on|off`, `/pl dump` (diagnostics).
