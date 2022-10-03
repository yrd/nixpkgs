{ stdenv
, lib
, fetchFromGitHub
, callPackage
, mkYarnModules
, mkYarnPackage
, runCommand
, fetchYarnDeps
, bash
, cacert
, jdk
, git
, clojure
, nodejs
, yarn
}:

let
	pname = "penpot";
	version = "1.15.0-beta";

	src = fetchFromGitHub {
    owner = "penpot";
    repo = "penpot";
    rev = version;
    sha256 = "sha256-DEvOKC8FGq47UL3eGLdnYKGlHg7Di0gPgDz9hlB9EpU=";
	};

	clojureDependencies = stdenv.mkDerivation {
	  inherit version src;
	  pname = "penpot-deps";

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
#    outputHash = lib.fakeSha256;
    outputHash = "sha256-RrLuDevVblAKkSMKB+LRW6VN22oqnOEM394rhvIQ6ws=";

    buildInputs = [ clojure git ];
    buildPhase = ''
      export HOME=$(mktemp -d)

      pushd backend
      clojure -P
      clojure -T:build || true
      popd

      pushd frontend
      clojure -P
      clojure -M:dev:shadow-cljs
      popd

      pushd exporter
      clojure -P
      clojure -M:dev:shadow-cljs
      popd

      # Delete anything in the maven dependency tree that has timestamps.
      find /build/.m2 -type f -regex '.+\(\.lastUpdated\|resolver-status\.properties\|_remote\.repositories\)' -delete
      find /build/.m2 -type f -iname '*.pom' -exec sed -i -e 's/\r\+$//' {} \;

      # Make the git repositories in the dependency bundle deterministic. See
      # nixpkgs/pkgs/build-support/fetchgit/deterministic-git for details.
      find "/build/.gitlibs/" -name .git -type f | while read -r dotGit; do
        pushd "$(dirname "$dotGit")"
        git config pack.threads 1 >&2
        git repack -A -d -f >&2
        git gc --prune=all --keep-largest-pack >&2
        popd
      done
      find /build/.gitlibs -path "*/worktrees/*/logs/HEAD" -delete
      find /build/.gitlibs -path "*/worktrees/*/index" -delete
      find /build/.gitlibs -path "*/hooks/*.sample" -delete
    '';

    installPhase = ''
      mkdir $out
      mv /build/.m2 /build/.gitlibs $out/
    '';

    # This makes sure we don't get any store paths in our fixed-output
    # derivation. Normally the fixup phase would patch the remaining
    # /build paths into /nix/store/something, but given that we will
    # symlink everything back into /build when using the dependency
    # bundle that doesn't really matter here.
    dontFixup = true;

    GIT_SSL_CAINFO = "${cacert}/etc/ssl/certs/ca-bundle.crt";
	};

	frontendNodeModules = mkYarnModules rec {
		pname = "penpot-frontend-modules";
		inherit version;

		packageJSON = ./frontend/package.json;
		yarnLock = ./frontend/yarn.lock;
		offlineCache = fetchYarnDeps {
			inherit yarnLock;
	    sha256 = "sha256-G7zrA/gYQ7XTRqLcZ+s7RKb+AuNHSXSg6P58oYzmHTo=";
		};
	};

	exporterNodeModules = mkYarnModules rec {
		pname = "penpot-exporter-modules";
		inherit version;

		packageJSON = ./exporter/package.json;
		yarnLock = ./exporter/yarn.lock;
		offlineCache = fetchYarnDeps {
			inherit yarnLock;
	    sha256 = "sha256-mL/QyGvjdmHWVdztgoFaFAusRUMTD25Iiei1Iy7AbtE=";
		};
	};
a= stdenv.mkDerivation {
	inherit pname version src;

	buildInputs = [ clojure git jdk nodejs ];

	buildPhase = let
		gulp = "${frontendNodeModules}/node_modules/.bin/gulp";
	in ''
    runHook preBuild

    export HOME=$(mktemp -d)
    cp -r ${clojureDependencies}/.m2 /build/.m2
    cp -r ${clojureDependencies}/.gitlibs /build/.gitlibs
    export NODE_ENV=production

    echo ${clojureDependencies}

    #
    # Build the backend
    # Reference: https://github.com/penpot/penpot/blob/develop/backend/scripts/build
    #
		pushd backend
		clojure -T:build jar
		popd

    #
    # Build the frontend
    # Reference: https://github.com/penpot/penpot/blob/develop/frontend/scripts/build
    #
    pushd frontend
		ln -s ${frontendNodeModules}/node_modules .
		${gulp} clean
		clojure \
		  -J-Xms100M -J-Xmx800M -J-XX:+UseSerialGC \
		  -M:dev:shadow-cljs \
			release main --config-merge "{:release-version \"${version}\"}"
		${gulp} build
		${gulp} dist:clean
		${gulp} dist:copy
		sed -i -re "s/\%version\%/${version}/g" ./target/dist/index.html
		popd

    #
    # Build the exporter
    # Reference: https://github.com/penpot/penpot/blob/develop/exporter/scripts/build
    #
    pushd exporter
		ln -s ${exporterNodeModules}/node_modules .
		clojure \
		  -M:dev:shadow-cljs release main
    patchShebangs target
		popd

    runHook postBuild
	'';

	installPhase = ''
		mkdir -p $out/bin $out/opt

		mv frontend/target/dist $out/frontend
		mv backend/target/penpot.jar $out/opt/backend.jar
		mv exporter/target/app.js $out/bin/exporter.js
	'';

  meta = with lib; {
    description = "Web-based design and prototyping platform";
    homepage = "https://penpot.app";
    changelog = "https://github.com/penpot/penpot/releases";
    license = licenses.mpl20;
    maintainers = with maintainers; [ yrd ];
  };
};
in a
