{ stdenv, fetchurl, fetchgit, fetchhg, erlang, lib, rebar, coreutils }:

let
  repos = rec {
    procket =
      {
        name = "procket";
        url = "git://github.com/msantos/procket.git";
        rev = "94bd7bc2162f18f8b3f4ba60437d3c6d93054cb6";
        sha256 = "17hqj68q98629fwxhk1ckrgndwcj429l8p7c71ndba1yy1aai83n";
        fetcher = git;
      };
    msgpack =
      {
        name = "msgpack";
        url = "git://github.com/msgpack/msgpack-erlang.git";
        rev = "40da10c523f3d8fcbc138545120201ee1651d421";
        sha256 = "1kccfpl5wshc2pnk2aa7h24iffs2imp2nczkh8vg8hl7zwqqyc0a";
        fetcher = git;
      };
    pkt =
      {
        name = "pkt";
        url = "git://github.com/msantos/pkt.git";
        rev = "fd8830bebef70cc01252e246063e8e4a56b5799a";
        sha256 = "029qyvpf51h8n0x5d688mkjr2pmnpyvsc0d7s1sxbxyj0av206dd";
        fetcher = git;
      };
    tunctl =
      {
        name = "tunctl";
        url = "git://github.com/msantos/tunctl.git";
        rev = "54f4aa2dd3a7c88e75759144e40f001f6b9cc25e";
        sha256 = "1as3pk29l7pzwqbfhm4a49kz9y0ch48yp4ncwrzjqbdiv6ycsq44";
        fetcher = git;
        deps = [ procket ];
      };
    router =
      {
        name = "tsp-demo-router";
        url = "http://rabbit-hg-private.lon.pivotallabs.com/tsp-demo-router";
        sha256 = "0641m4x5qm1g5p0s73s369872amdnl6agf9vqxdaxsxxjhwa7bj6";
        tag = "6561c82ad2e8";
        fetcher = hg;
        deps = [ procket msgpack pkt tunctl ];
      };
  };
  git = desc: fetchgit { inherit (desc) url rev sha256; };
  hg = desc: fetchhg { inherit (desc) name url tag sha256; };
  setupDeps = deps:
    lib.concatStrings
      (map (dep:
            ''
              ln -s ${dep.path} $DEPSPATH/${dep.name}
            '') deps);
  builder = desc:
    let
      deps = map builder (if desc ? deps then desc.deps else []);
      path = stdenv.mkDerivation rec {
        inherit (desc) name;
        src = desc.fetcher desc;
        buildInputs = [ erlang rebar coreutils ] ++ (map (e: e.path) deps);
        buildPhase = ''
          export DEPSPATH=$(pwd)/deps
          mkdir $DEPSPATH
          mkdir -p priv/tmp
          ${setupDeps deps}
          rebar check-deps
          rebar compile skip_deps=true
        '';
        installPhase = ''
          ensureDir $out
          for d in ebin priv include; do
            if [ -d "$d" ]; then
              cp -a "$d" "$out/$d"
            fi
          done
          mkdir $out/deps
          export DEPSPATH=$out/deps
          ${setupDeps deps}
        '';
      };
    in
      desc // { inherit path; };
in
  builder repos.router
