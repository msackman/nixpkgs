{ tsp, coreutils, erlang, nettools, iproute, netcat, host, callPackage }:

tsp.container ({ global, configuration, containerLib }:
  let
    tsp_bash = callPackage ../tsp-bash-lxc { };
    tsp_home = callPackage ../tsp-home-lxc { };
    tsp_network = callPackage ../tsp-network-lxc { };
  in
    {
      name = "shell-lxc";
      storeMounts = { bash         = tsp_bash;
                      network      = tsp_network;
                      home         = tsp_home;
                      inherit erlang nettools coreutils iproute netcat host; };
      configuration = {
        home.user  = "shell";
        home.uid   = 1000;
        home.group = "shell";
        home.gid   = 1000;
        bash.start = true;
      };
    })
