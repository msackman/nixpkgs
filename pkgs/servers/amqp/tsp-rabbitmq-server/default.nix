{ stdenv, fetchurl, fetchhg, erlang, python, libxml2, libxslt, xmlto
, docbook_xml_dtd_45, docbook_xsl, zip, unzip }:

stdenv.mkDerivation rec {
  origname = "rabbitmq-server-${version}";
  name = "tsp-${name}";

  version = "3.2.2";

  rabbit = fetchurl {
    url = "http://www.rabbitmq.com/releases/rabbitmq-server/v${version}/${origname}.tar.gz";
    sha256 = "c6f985d2bf69de60fa543ebfff190f233d2ab8faee78a10cfb065b4e4d1406ba";
  };

  clusterer = fetchhg {
    url = "http://rabbit-hg-private.lon.pivotallabs.com/rabbitmq-clusterer";
    sha256 = "1dvps982i0ixyswjy13vlskxjv5gjm93shg6bzyfw7a8c691sz38";
  };

  srcs = [ rabbit clusterer ];
  sourceRoot = origname;

  buildInputs =
    [ erlang python libxml2 libxslt xmlto docbook_xml_dtd_45 docbook_xsl zip unzip ];

  preBuild =
    ''
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
    ''; # */

  meta = {
    homepage = http://www.rabbitmq.com/;
    description = "An implementation of the AMQP messaging protocol";
    platforms = stdenv.lib.platforms.linux;
  };
}
