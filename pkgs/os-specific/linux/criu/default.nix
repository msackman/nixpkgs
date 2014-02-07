{ stdenv, fetchurl, protobufc, utillinux, asciidoc }:
stdenv.mkDerivation rec {
  version = "1.1";
  name = "criu-${version}";
  src = fetchurl {
    url = "http://download.openvz.org/criu/${name}.tar.bz2";
    sha256 = "0zbz2gnngk0hql8vv890k5x68kznazpavd2rqmgcl7szwpih0xzz";
  };

  buildInputs = [ protobufc utillinux asciidoc ];

  config = builtins.toFile "config" ''
    #ifndef __CR_CONFIG_H__
    #define __CR_CONFIG_H__
    #define CONFIG_HAS_PRLIMIT
    #define CONFIG_HAS_TCP_REPAIR
    #define CONFIG_HAS_STRLCAT
    #endif /* __CR_CONFIG_H__ */
  '';

  preBuild = ''
    cat ${config} > include/config.h
  '';

  buildFlags = "all";
}
