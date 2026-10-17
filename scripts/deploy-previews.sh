#!/bin/zsh
# Deploys the three family sites to their preview copies on Cloudflare Pages (not the real domains):
#   https://slinky-preview.pages.dev  https://dinky-preview.pages.dev  https://binky-preview.pages.dev
# The Dock links between the previews; each has Workers AI for Spotlight answers and is kept out of search.
set -e
~/slinky/scripts/stamp-family.sh   # fresh ?v= on the shared files, so browsers don't keep old copies
(cd ~/slinky/site && npx astro build && npx wrangler pages deploy dist --project-name slinky-preview --branch main --commit-dirty=true)
(cd ~/dinky && npx wrangler pages deploy site --project-name dinky-preview --branch main --commit-dirty=true)
(cd ~/binky && npx wrangler pages deploy site --project-name binky-preview --branch main --commit-dirty=true)
