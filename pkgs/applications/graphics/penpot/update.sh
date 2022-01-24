#!/usr/bin/env bash
# Usage: ./update.sh [tag]

pushd "$(mktemp -d)" || exit

folder=$(pwd)
git clone -b "$1" git@github.com:penpot/penpot.git $folder

# The aliases specified in the following clj2nix calls are all the ones defined
# in the corresponding deps.edn file for each module.
cd frontend || exit
nix run github:hlolli/clj2nix -- \
    deps.edn deps.nix \
    -A:dev -A:outdated -A:jvm-repl
cd ../backend || exit
nix run github:hlolli/clj2nix -- \
    deps.edn deps.nix \
    -A:dev -A:build -A:kaocha -A:test -A:outdated -A:jmx-remote
cd ../exporter || exit
nix run github:hlolli/clj2nix -- \
    deps.edn deps.nix \
    -A:dev -A:outdated

popd || exit

mv "$folder/frontend/deps.nix" deps-frontend.nix
mv "$folder/backend/deps.nix" deps-backend.nix
mv "$folder/exporter/deps.nix" deps-exporter.nix

rm -rf "$folder"
