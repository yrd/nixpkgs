{ stdenv
, lib
, fetchFromGitHub
, callPackage
, mkYarnModules
, mkYarnPackage
, fetchYarnDeps
, bash
, jdk
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

	extraClasspaths = [
#	  "src" "vendor" "resources" "test" "${src}/common/src"
	  "${clojure}/libexec/exec.jar"
	];

	frontendDeps = callPackage ./frontend/deps.nix { };
	frontendClasspath = frontendDeps.makeClasspaths { inherit extraClasspaths; };
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

	backendDeps = callPackage ./backend/deps.nix { };
	backendClasspath = backendDeps.makeClasspaths { inherit extraClasspaths; };

	exporterDeps = callPackage ./exporter/deps.nix { };
	exporterClasspath = exporterDeps.makeClasspaths { inherit extraClasspaths; };
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
in
stdenv.mkDerivation {
	inherit pname version src;

	buildInputs = [ clojure jdk nodejs ];

	buildPhase = let
		gulp = "${frontendNodeModules}/node_modules/.bin/gulp";
		toolsCp = "${clojure}/libexec/clojure-tools-${clojure.version}.jar";
	in ''
    runHook preBuild

    export HOME=$(mktemp -d)
    export NODE_ENV=production

    #
    # Build the backend
    # Reference: https://github.com/penpot/penpot/blob/develop/backend/scripts/build
    #
		pushd backend
		#echo ${backendClasspath}
		java -classpath .:${backendClasspath}:${toolsCp} clojure.main -m clojure.tools.deps.alpha.script.make-classpath2 \
		  --config-project ./deps.edn --basis-file $HOME/backend.basis
		cat $HOME/backend.basis
		echo java -classpath .:${backendClasspath} \
		  clojure.main -m clojure.run.exec jar
		popd

    #
    # Build the frontend
    # Reference: https://github.com/penpot/penpot/blob/develop/frontend/scripts/build
    #
    pushd frontend
		ln -s ${frontendNodeModules}/node_modules .
		${gulp} clean
		clojure -Scp .:${frontendClasspath} \
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
		  -Scp ${exporterClasspath} \
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
}
