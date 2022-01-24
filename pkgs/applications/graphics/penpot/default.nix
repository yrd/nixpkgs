{ stdenv
, lib
, fetchFromGitHub
, callPackage
, mkYarnModules
, mkYarnPackage
, fetchYarnDeps
, bash
, clojure
, nodejs
, yarn
}:

let
	pname = "penpot";
	version = "1.10.4-beta";

	src = fetchFromGitHub {
    owner = "penpot";
    repo = "penpot";
    rev = version;
    sha256 = "QhaUNnhFQVUPsqL+aH0XnizBy1Fo6qcpT+JrYc7kGrE=";
	};

	extraClasspaths = [ "src" "vendor" "resources" "test" "${src}/common/src" ];

	frontendDeps = callPackage ./deps-frontend.nix { };
	frontendClasspath = frontendDeps.makeClasspaths { inherit extraClasspaths; };
	frontendNodeModules = mkYarnModules rec {
		pname = "penpot-frontend-modules";
		inherit version;

		packageJSON = src + "/frontend/package.json";
		yarnLock = src + "/frontend/yarn.lock";
		offlineCache = fetchYarnDeps {
			inherit yarnLock;
	    sha256 = "1vfypzd9qfrl7dq1w5khhwghz424ss46hlchkr91hzfbv251g330";
		};
	};

	backendDeps = callPackage ./deps-backend.nix { };
	backendClasspath = backendDeps.makeClasspaths { inherit extraClasspaths; };

	exporterDeps = callPackage ./deps-exporter.nix { };
	exporterClasspath = exporterDeps.makeClasspaths { inherit extraClasspaths; };
	exporterNodeModules = mkYarnModules rec {
		pname = "penpot-exporter-modules";
		inherit version;

		packageJSON = src + "/exporter/package.json";
		yarnLock = src + "/exporter/yarn.lock";
		offlineCache = fetchYarnDeps {
			inherit yarnLock;
	    sha256 = "Ar3vX2in91RrcKH+VKOi4PJ+uw5+lDSrVmCdD8HiEmo=";
		};
	};
in
stdenv.mkDerivation {
	inherit pname version src;

	buildInputs = [ clojure nodejs ];

	buildPhase = let
		gulp = "${frontendNodeModules}/node_modules/.bin/gulp";
	in ''
    runHook preBuild

    export HOME=$(mktemp -d)
    export NODE_ENV=production

    #
    # Build the frontend
    # Reference: https://github.com/penpot/penpot/blob/develop/frontend/scripts/build
    #
    pushd frontend
		ln -s ${frontendNodeModules}/node_modules .
		${gulp} clean
		echo ${frontendClasspath}
		clojure \
			-J-Xms100M -J-Xmx800M -J-XX:+UseSerialGC \
		  -Scp ${frontendClasspath} \
			-M:dev:shadow-cljs \
			release main --config-merge "{:release-version \"${version}\"}"
		${gulp} build
		${gulp} dist:clean
		${gulp} dist:copy
		sed -i -re "s/\%version\%/${version}/g" ./target/dist/index.html
		popd

    #
    # Build the backend
    # Reference: https://github.com/penpot/penpot/blob/develop/backend/scripts/build
    #
		pushd backend
		pwd
		clojure -Scp ${backendClasspath} -T:build jar
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
