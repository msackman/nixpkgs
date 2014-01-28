{ stdenv, fetchurl, fetchhg, erlang, python, coreutils, libxml2, libxslt, xmlto
, docbook_xml_dtd_45, docbook_xsl, zip, unzip, gnupatch, makeWrapper }:

stdenv.mkDerivation rec {
  origname = "rabbitmq-server-${version}";
  name = "tsp-${origname}";

  version = "3.2.2";

  rabbitmq = fetchurl {
    url = "http://www.rabbitmq.com/releases/rabbitmq-server/v${version}/${origname}.tar.gz";
    sha256 = "c6f985d2bf69de60fa543ebfff190f233d2ab8faee78a10cfb065b4e4d1406ba";
  };

  clusterer = fetchhg {
    name = "rabbitmq-clusterer";
    url = "http://rabbit-hg-private.lon.pivotallabs.com/rabbitmq-clusterer";
    sha256 = "1dvps982i0ixyswjy13vlskxjv5gjm93shg6bzyfw7a8c691sz38";
  };

  srcs = [ rabbitmq clusterer ];
  sourceRoot = ".";
  patchMakefile = ./Makefile.patch.in;
  patchPackage = ./package.mk.patch.in;

  buildInputs =
    [ erlang python libxml2 libxslt xmlto docbook_xml_dtd_45 docbook_xsl zip unzip ];

  postUnpack =
    ''
      cp -a ${clusterer.name} ${origname}/plugins-src/${clusterer.name}-${clusterer.outputHash}
    '';
  postPatch =
    ''
      cat ${patchMakefile} | \
        sed -e 's|@rabbitmq-clusterer@|${clusterer.name}-${clusterer.outputHash}|g' \
            -e 's|@rabbitmq@|${origname}|g' | \
        patch -p0
      cat ${patchPackage} | \
        sed -e 's|@rabbitmq-clusterer@|${clusterer.name}-${clusterer.outputHash}|g' \
            -e 's|@rabbitmq@|${origname}|g' | \
        patch -p0
      cat ${origname}/plugins-src/${clusterer.name}-${clusterer.outputHash}/rabbitmq-server.patch | \
        sed -e 's|rabbitmq_clusterer-0.0.0|rabbitmq_clusterer-${version}|g' | \
        patch ${origname}/scripts/rabbitmq-server
    '';
  preBuild =
    ''
      cd ${origname}
      # Fix the "/usr/bin/env" in "calculate-relative".
      patchShebangs .
    '';

  installFlags = "TARGET_DIR=$(out)/libexec/rabbitmq SBIN_DIR=$(out)/sbin MAN_DIR=$(out)/share/man DOC_INSTALL_DIR=$(out)/share/doc";

  preInstall =
    ''
      sed -i \
        -e 's|SYS_PREFIX=|SYS_PREFIX=''${SYS_PREFIX-''${HOME}/.rabbitmq/${version}}|' \
        -e 's|CONF_ENV_FILE=''${SYS_PREFIX}\(.*\)|CONF_ENV_FILE=\1|' \
        scripts/rabbitmq-defaults
    '';

  postInstall =
    ''
      echo 'PATH=${erlang}/bin:${PATH:+:}$PATH' >> $out/sbin/rabbitmq-env
      for f in $out/sbin/*; do
        wrapProgram $f --suffix PATH : ${coreutils}/bin
      done
    ''; # */

  meta = {
    homepage = http://www.rabbitmq.com/;
    description = "An implementation of the AMQP messaging protocol";
    platforms = stdenv.lib.platforms.linux;
  };
}
