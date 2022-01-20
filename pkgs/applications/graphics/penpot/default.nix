{ stdenv
, lib
, fetchFromGitHub
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

	mavenDependencies = stdenv.mkDerivation {
		pname = "penpot-dependencies";
		inherit version src;

		buildInputs = [ clojure nodejs ];

		# This build script runs the clojure commands we need when actually
		# compiling the app, but with -Spath which makes Clojure only
		# download dependencies, output the classpath and terminate.
		buildPhase = ''
			export HOME=$(mktemp -d)

			pushd frontend
			ln -s ${frontendNodeModules}/node_modules .
			clojure -Spath \
				-J-Xms100M -J-Xmx800M -J-XX:+UseSerialGC \
				-M:dev:shadow-cljs compile main
			popd

			pushd backend
			clojure -T:build jar
			popd

			pushd exporter
			ln -s ${exporterNodeModules}/node_modules .
			clojure -Spath \
				-M:dev:shadow-cljs compile main
			popd
		'';

    # Maven packaging inspired by this post:
    # https://fzakaria.com/2020/07/20/packaging-a-maven-application-with-nix.html
    # It seems that in our setup the .m2 folder lands in /build/.m2 (no idea
    # why), which is one folder up from the source.
    installPhase = ''
    	cd ..
      find .m2 -type f ! -regex '.*\(pom\|jar\|sha1\|xml\)' -delete
      mkdir $out
      mv .m2 $out
    '';

    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash = "cCSrabfDgxLVF0OewXImQyfEmP8YFv43aZNjsMuxWXM=";
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
    cp -r ${mavenDependencies}/.m2 ..

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
    # Build the backend
    # Reference: https://github.com/penpot/penpot/blob/develop/backend/scripts/build
    #
		pushd backend
		pwd
		clojure -T:build jar
		popd

    #
    # Build the exporter
    # Reference: https://github.com/penpot/penpot/blob/develop/exporter/scripts/build
    #
    pushd exporter
		ln -s ${exporterNodeModules}/node_modules .
		clojure -M:dev:shadow-cljs release main
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
