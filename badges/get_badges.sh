#!/bin/bash

# Get the path of this script
script_dir="$(dirname "$(realpath "$0")")"

wget -q https://img.shields.io/badge/Integration-Level_0-red.svg         -O "$script_dir/level0.svg"
wget -q https://img.shields.io/badge/Integration-Level_1-orange.svg      -O "$script_dir/level1.svg"
wget -q https://img.shields.io/badge/Integration-Level_2-orange.svg      -O "$script_dir/level2.svg"
wget -q https://img.shields.io/badge/Integration-Level_3-yellow.svg      -O "$script_dir/level3.svg"
wget -q https://img.shields.io/badge/Integration-Level_4-yellow.svg      -O "$script_dir/level4.svg"
wget -q https://img.shields.io/badge/Integration-Level_5-yellowgreen.svg -O "$script_dir/level5.svg"
wget -q https://img.shields.io/badge/Integration-Level_6-green.svg       -O "$script_dir/level6.svg"
wget -q https://img.shields.io/badge/Integration-Level_7-green.svg       -O "$script_dir/level7.svg"
wget -q https://img.shields.io/badge/Integration-Level_8-brightgreen.svg -O "$script_dir/level8.svg"
wget -q https://img.shields.io/badge/Integration-Level_9-blue.svg        -O "$script_dir/level9.svg"
wget -q https://img.shields.io/badge/Integration-Unknown-lightgrey.svg   -O "$script_dir/unknown.svg"

wget -q https://img.shields.io/badge/Status-Maintained-brightgreen.svg -O "$script_dir/maintained.svg"
wget -q https://img.shields.io/badge/Status-Need%20help-yellow.svg -O "$script_dir/request_help.svg"
wget -q https://img.shields.io/badge/Status-Waiting%20adoption-orange.svg -O "$script_dir/request_adoption.svg"
wget -q https://img.shields.io/badge/Status-Not%20maintained-red.svg -O "$script_dir/orphaned.svg"

wget -q https://img.shields.io/badge/Status-High%20quality-blueviolet.svg -O "$script_dir/high_quality.svg"
wget -q https://img.shields.io/badge/Status-working-brightgreen.svg -O "$script_dir/working.svg"
wget -q https://img.shields.io/badge/Status-In%20progress-orange.svg -O "$script_dir/inprogress.svg"
wget -q https://img.shields.io/badge/Status-Not%20working-red.svg -O "$script_dir/notworking.svg"
