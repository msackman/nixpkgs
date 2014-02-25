{ stdenv, tsp_router, fetchhg, erlang, lib, rebar, coreutils }:

let
  repos = rec {
    router =
      {
        name = "tsp";
        path = tsp_router;
      };
    erlinetrc =
      {
        name = "tsp-demo-erlinetrc";
        url = "http://rabbit-hg-private.lon.pivotallabs.com/tsp-demo-erlinetrc";
        sha256 = "0cbz6nbhpzk3ig2gdivs1yhblfsk0nlqfb8wlq03xfh6p60kggjn";
        tag = "43dcf6fd3473";
        fetcher = hg;
        deps = [ router ];
      };
  };
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
      { inherit path; } // desc;
in
  (builder repos.erlinetrc).path
