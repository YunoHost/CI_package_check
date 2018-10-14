#!/bin/bash

# Get the path of this script
script_dir="$(dirname "$(realpath "$0")")"

wget -nv https://img.shields.io/badge/Integration-Level_0-red.svg -O "$script_dir/level0.svg"
wget -nv https://img.shields.io/badge/Integration-Level_1-orange.svg -O "$script_dir/level1.svg"
wget -nv https://img.shields.io/badge/Integration-Level_2-yellow.svg -O "$script_dir/level2.svg"
wget -nv https://img.shields.io/badge/Integration-Level_3-yellow.svg -O "$script_dir/level3.svg"
wget -nv https://img.shields.io/badge/Integration-Level_4-yellowgreen.svg -O "$script_dir/level4.svg"
wget -nv https://img.shields.io/badge/Integration-Level_5-green.svg -O "$script_dir/level5.svg"
wget -nv https://img.shields.io/badge/Integration-Level_6-green.svg -O "$script_dir/level6.svg"
wget -nv https://img.shields.io/badge/Integration-Level_7-brightgreen.svg -O "$script_dir/level7.svg"
wget -nv https://img.shields.io/badge/Integration-Unknown-lightgrey.svg -O "$script_dir/unknown.svg"
