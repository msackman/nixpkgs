{ tsp, coreutils, erlang, nettools, iproute, netcat, host, callPackage }:

tsp.container ({ configuration, lxcLib }:
  let
    tsp_bash = callPackage ../tsp-bash { };
    tsp_dev_proc_sys = callPackage ../tsp-dev-proc-sys { };
    tsp_home = callPackage ../tsp-home { };
    tsp_network = callPackage ../tsp-network { };
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
