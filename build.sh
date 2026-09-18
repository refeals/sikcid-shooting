#!/bin/sh
set -e
cd "$(dirname "$0")"

# Apaga o anterior: zip sobre arquivo existente nunca remove entradas antigas.
rm -f sikcid-shootin.love
zip -9 -r sikcid-shootin.love main.lua conf.lua src assets -x '*/.gitkeep'

love sikcid-shootin.love
