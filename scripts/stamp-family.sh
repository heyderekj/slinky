#!/bin/zsh
# Gives the shared family files (Dock, menu bar, ask) a ?v=<content hash> in every page that loads them, so a
# change reaches visitors right away instead of waiting out their browser cache. Run before deploying.
set -e
stamp() { # stamp <file that references them> <folder holding the shared files>
  local page=$1 dir=$2
  for f in family-menubar.css family-menubar.js family-ask.js family-dock.js site-tabs.css; do
    [ -f "$dir/$f" ] || continue
    local v=$(shasum "$dir/$f" | cut -c1-8)
    sed -i '' -E "s#(/$f)(\?v=[0-9a-f]+)?\"#\1?v=$v\"#g" "$page"
  done
}
stamp ~/slinky/site/src/layouts/Layout.astro ~/slinky/site/public
for r in dinky binky; do
  for page in $(grep -rlE 'family-(menubar|ask|dock)|site-tabs\.css' ~/$r/site --include='*.html'); do stamp "$page" ~/$r/site; done
done
