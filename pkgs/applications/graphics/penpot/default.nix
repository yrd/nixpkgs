{ stdenv
, lib
, fetchFromGitHub
, callPackage
, mkYarnModules
, mkYarnPackage
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
    outputHash = lib.fakeSha256;

    buildInputs = [ clojure git ];
    buildPhase = ''
      export HOME=$(mktemp -d)

      pushd backend
      clojure -P
      popd

      pushd exporter
      clojure -P
      popd

      pushd frontend
      clojure -P
      popd
    '';

    installPhase = ''
      ls -al /build
      mkdir -p $out/.gitlibs
      mv /build/.m2 $out/
      mv /build/.gitlibs/libs $out/.gitlibs
      rm $out/.gitlibs/libs/*/*/*/.git
    '';

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
in clojureDependencies
