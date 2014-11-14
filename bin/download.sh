#!/bin/bash

QUERY_DIR=$(cd $(dirname $0); pwd)
DATA_DIR=$(cd $(dirname $0)/../data; pwd)
HTML_DIR=$(cd $(dirname $0)/../html; pwd)
IMAGES_DIR=$HTML_DIR/images

for state in Connecticut 
do
  if [[ ! -r "$DATA_DIR/$state" ]]
  then
    wget --user-agent="brianegge@gmail.com" -O "${DATA_DIR}/$state.xml" --post-file=${QUERY_DIR}/$state.xml "http://overpass-api.de/api/interpreter"
  fi
  mkdir -p "$DATA_DIR/$state"
  for t in dining cafes icecream entertainment arts leisure churches hotels
  do
    if [[ ! -r "$DATA_DIR/$state/$f.xml" ]]
    then
      wget --user-agent="brianegge@gmail.com" -O "${DATA_DIR}/$state/$t.xml" --post-file=${QUERY_DIR}/$t.xml "http://overpass-api.de/api/interpreter"
      sleep 1.1
    fi
  done
done
# curl 'http://nominatim.openstreetmap.org/search?X-Requested-With=overpass-turbo&format=json&q=Ridgefield+Connecticut' -H 'Origin: http://overpass-turbo.eu' -H 'Accept-Encoding: gzip,deflate,sdch' -H 'Accept-Language: en-US,en;q=0.8' -H 'User-Agent: brianegge@gmail.com' -H 'Accept: */*' -H 'Connection: keep-alive' --compressed
#wget -O data/dining.xml --post-file=bin/query2.xml "http://overpass-api.de/api/interpreter"
# wget -O html/images/skyline-color.png "http://staticmap.openstreetmap.de/staticmap.php?center=41.2861,-73.4989&zoom=15&size=900x200&maptype=mapnik"

#convert html/images/skyline-color.png -sepia-tone 90% -fill black -font Century -size 850x180  label:Ridgefield html/images/skyline.png
#convert html/images/skyline-color.png -sepia-tone 90% -gravity center -stroke grey -fill black -pointsize 150 -font Century -annotate 0 Ridgefield  html/images/skyline.png 

city=${1:-Ridgefield}
convert -background none -gravity center -stroke grey -size 900x200 -fill black  -font Century -blur 0x5 -fill black "label:$city" $IMAGES_DIR/text.png 
convert -background none -gravity center -stroke grey -size 900x200 -fill black  -font Century "label:$city"  $IMAGES_DIR/text2.png
convert -page 0 $IMAGES_DIR/skyline-color.png -page +5+5 $IMAGES_DIR/text.png -page -0 $IMAGES_DIR/text2.png -layers flatten $IMAGES_DIR/skyline.png
