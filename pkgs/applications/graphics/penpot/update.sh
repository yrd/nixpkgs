#!/usr/bin/env bash
# Usage: ./update.sh [tag]

pushd "$(mktemp -d)" || exit

target=$(pwd)
git clone -b "$1" git@github.com:penpot/penpot.git $target

# The aliases specified in the following clj2nix calls are all the ones defined
# in the corresponding deps.edn file for each module.
cd frontend || exit
nix run github:hlolli/clj2nix --impure -- \
    deps.edn deps.nix \
    -A:outdated -A:jvm-repl -A:dev -A:shadow-cljs
cd ../backend || exit
nix run github:hlolli/clj2nix --impure -- \
    deps.edn deps.nix \
    -A:dev -A:build -A:kaocha -A:test -A:outdated -A:jmx-remote
cd ../exporter || exit
nix run github:hlolli/clj2nix --impure -- \
    deps.edn deps.nix \
    -A:outdated -A:dev -A:shadow-cljs

popd || exit

mkdir -p frontend backend exporter

mv "$target/frontend/deps.nix" frontend/deps.nix
mv "$target/frontend/package.json" frontend/package.json
mv "$target/frontend/yarn.lock" frontend/yarn.lock
mv "$target/backend/deps.nix" backend/deps.nix
mv "$target/exporter/deps.nix" exporter/deps.nix
mv "$target/exporter/package.json" exporter/package.json
mv "$target/exporter/yarn.lock" exporter/yarn.lock

#rm -rf "$folder"
