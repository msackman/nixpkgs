{ stdenv, makeWrapper, buildLXC, bash, coreutils, lib, erlang, nettools, iproute, netcat, host }:

buildLXC ({ configuration, lxcLib }:
  let
    tsp_bash = (import ../tsp-bash) { inherit stdenv buildLXC bash coreutils; };
    tsp_dev_proc_sys = (import ../tsp-dev-proc-sys) { inherit stdenv buildLXC coreutils; };
    tsp_home = (import ../tsp-home) { inherit stdenv buildLXC coreutils bash; };
    tsp_network = (import ../tsp-network) { inherit buildLXC lib; };
  in
    {
      name = "shell-lxc";
      storeMounts = { bash         = tsp_bash;
                      network      = tsp_network;
                      home         = tsp_home;
                      dev_proc_sys = tsp_dev_proc_sys;
                      inherit erlang nettools coreutils iproute netcat host; };
      configuration = {
        home.user  = "shell";
        home.uid   = 1000;
        home.group = "shell";
        home.gid   = 1000;
        bash.start = true;
      };
    })
