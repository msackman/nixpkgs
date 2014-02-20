{ stdenv, fetchurl, fetchgit, fetchhg, erlang, lib, rebar, coreutils }:

let
  repos = rec {
    mochiweb =
      {
        name = "mochiweb";
        url = "git://github.com/mochi/mochiweb.git";
        rev = "1d7338345360cb4de426fed69b6b2d005f2ac9f8";
        sha256 = "1l97dscn9wqr5v9z06vgavf7gv3svmvhw1p13vz5aslvc3kajjd0";
        fetcher = git;
      };
    http =
      {
        name = "tsp-demo-http";
        url = "http://rabbit-hg-private.lon.pivotallabs.com/tsp-demo-http";
        sha256 = "1pb08ajgyl61cd0vql2xhydhyya6x608z8m8q4qwjrs2506f6kic";
        tag = "2e14953a798e";
        fetcher = hg;
        deps = [ mochiweb ];
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
  (builder repos.http).path
