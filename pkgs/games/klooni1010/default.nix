{ lib, stdenv
, fetchFromGitHub
, makeWrapper
, gradle
, jre
}:

stdenv.mkDerivation rec {
  pname = "klooni1010";
  version = "0.8.6";

  src = fetchFromGitHub {
    owner = "LonamiWebs";
    repo = "Klooni1010";
    rev = "v${version}";
    sha256 = "sha256-MzHdUAzCR2JtIdY1SGuge3xgR6qIhNYxUPOxA+TZtLE=";
  };

  nativeBuildInputs = [ makeWrapper gradle jre ];

  buildPhase = ''
    patchShebangs gradlew
    ./gradlew desktop:dist
  '';

  installPhase = ''
    install -Dm644 desktop/build/libs/desktop-${version}.jar $out/share/klooni-1010.jar
    mkdir $out/bin
    makeWrapper ${jre}/bin/java $out/bin/klooni-1010 \
      --add-flags "-jar $out/share/klooni-1010.jar"
  '';

  meta = with lib; {
    homepage = "https://lonami.dev/klooni/";
    downloadPage = "https://github.com/LonamiWebs/Klooni1010/releases";
    description = "libGDX game based on the original 1010!";
    license = licenses.gpl3Plus;
    maintainers = with maintainers; [ yrd ];
  };
}
