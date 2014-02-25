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
        sha256 = "171iyj08ilbvp4xfscaa5wv8g0zcmj0sj68qj9kalrs70j96k3pi";
        tag = "e218da301979";
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
