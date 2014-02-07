{ stdenv, fetchurl, erlang }:

stdenv.mkDerivation {
  name = "tsp-rebar-2.0.0";

  src = fetchurl {
    url = "https://github.com/basho/rebar/archive/2.0.0.tar.gz";
    sha256 = "05kl6kv77p8872azxfs628zlngyjmsav1gcmw0ic6jli32dqv6mi";
  };

  buildInputs = [ erlang ];

  buildPhase = "escript bootstrap";
  installPhase = ''
    mkdir -p $out/bin
    cp rebar $out/bin/rebar
  '';

  meta = {
    homepage = "https://github.com/rebar/rebar";
    description = "Erlang build tool that makes it easy to compile and test Erlang applications, port drivers and releases";

    longDescription = ''
      rebar is a self-contained Erlang script, so it's easy to
      distribute or even embed directly in a project. Where possible,
      rebar uses standard Erlang/OTP conventions for project
      structures, thus minimizing the amount of build configuration
      work. rebar also provides dependency management, enabling
      application writers to easily re-use common libraries from a
      variety of locations (git, hg, etc).
      '';

    platforms = stdenv.lib.platforms.linux;
    maintainers = [ stdenv.lib.maintainers.the-kenny ];
  };
}
