#!/usr/bin/python3

import sys
import yaml

fname=sys.argv[1]

with open(fname, "r") as file:
    repos = yaml.load(file, Loader=yaml.FullLoader)

modules = repos["modules"]
#for m in modules:
#    print(m)

sep = "|"

for r in repos["rules"]:
    for m in r["modules"]:
        mod_name = m["name"]
        mod = modules[mod_name]
        print(r["local"], sep,
            mod["url"], sep,
            m["commit"], sep,
            mod_name)

