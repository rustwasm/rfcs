#!/bin/sh

set -eu

cd $(dirname $0)

if [ ! -d src ]; then
    mkdir src
fi

echo "[Introduction](introduction.md)\n" > src/SUMMARY.md

for f in $(ls text | sort)
do
    echo "- [$(basename $f ".md")]($f)" >> src/SUMMARY.md
    cp text/$f src
done

cp README.md src/introduction.md

mdbook build
