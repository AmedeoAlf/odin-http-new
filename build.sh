#!/usr/bin/env bash

mkdir build -p

TEMPLATE_LINE=$(grep -n '<?TEMPLATE?>' assets/directory_listing.html | sed 's/\(\d*\):.*$/\1/')

head -n$[TEMPLATE_LINE - 1] ./assets/directory_listing.html > build/directory_listing_start.html
tail -n +$[TEMPLATE_LINE + 1] ./assets/directory_listing.html > build/directory_listing_end.html

odin build $@ -out:build/odin-http src
