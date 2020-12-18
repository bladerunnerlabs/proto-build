#!/bin/bash

url=$1; shift
remote=$1; shift
branch=$1; shift
dir=$1; shift

if [ -d ${dir} ]; then
    pushd ${dir} && git fetch ${remote} && git checkout -t ${remote}/${branch} && popd
else # no dir
    git clone --origin ${remote} --branch ${branch} ${url} ${dir}
fi
