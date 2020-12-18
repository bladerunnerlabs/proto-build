#!/usr/bin/python3

import sys
import yaml


if len(sys.argv) > 1:
    modules_fname=sys.argv[1]
else:
    manifest_fname = "manifest.yaml"

if len(sys.argv) > 2:
    manifest_fname=sys.argv[2]
else:
    modules_fname = "modules.yaml"

with open(modules_fname, "r") as file:
    modules_root = yaml.load(file, Loader=yaml.FullLoader)

modules = modules_root["modules"]
#for m in modules:
#    print(m)

with open(manifest_fname, "r") as file:
    manifest_root = yaml.load(file, Loader=yaml.FullLoader)

if 'develop' in manifest_root:
    develop_modules = manifest_root["develop"]
else:
    develop_modules = []

if 'consume' in manifest_root:
    consume_modules = manifest_root["consume"]
else:
    consume_modules = []

proj_modules = develop_modules + consume_modules

sep = " | "

for m in proj_modules:
    mod_name = m["module"]
    mod = modules[mod_name]
    print("*", sep, mod["url"], sep, m["from"], sep, mod_name)

