{ fetchurl, stdenv, pkgconfig, gnome3, json_glib, libcroco, intltool, libsecret
, python, libsoup, polkit, clutter, networkmanager, docbook_xsl, docbook_xsl_ns
, libstartup_notification, telepathy_glib, telepathy_logger, libXtst, p11_kit
, pulseaudio, libical, libtool, nss, gobjectIntrospection, gstreamer, makeWrapper
, accountservice, gdk_pixbuf, gdm, upower, ibus, networkmanagerapplet }:


stdenv.mkDerivation rec {
  name = "gnome-shell-3.10.2.1";

  src = fetchurl {
    url = "mirror://gnome/sources/gnome-shell/3.10/${name}.tar.xz";
    sha256 = "0k642y6h878v6mczx4z1zj4pjl7z4bvq02raxxwxkjyvyz2fv36j";
  };

  buildInputs = with gnome3;
    [ gsettings_desktop_schemas gnome_keyring gnome-menus glib gcr json_glib accountservice
      libcroco intltool libsecret pkgconfig python libsoup polkit libcanberra gdk_pixbuf
      clutter networkmanager libstartup_notification telepathy_glib docbook_xsl docbook_xsl_ns
      libXtst p11_kit networkmanagerapplet gjs mutter pulseaudio caribou evolution_data_server
      libical libtool nss gobjectIntrospection gtk gstreamer makeWrapper gdm
      at_spi2_core upower ibus gnome_session gnome_desktop telepathy_logger ];

  configureFlags = "--disable-static";

  preBuild = ''
    patchShebangs src/data-to-c.pl
  '';

  postInstall = with gnome3; ''
    wrapProgram "$out/bin/gnome-shell" \
      --prefix GI_TYPELIB_PATH : "$GI_TYPELIB_PATH" \
      --prefix LD_LIBRARY_PATH : "${accountservice}/lib:${ibus}/lib:${gdm}/lib" \
      --prefix XDG_DATA_DIRS : "${gnome-menus}:/share:${ibus}/share:${gnome_settings_daemon}/share:${gdm}/share:${glib}/share:${gnome_themes_standard}/share:${mutter}/share:${gnome_icon_theme}/share:${gsettings_desktop_schemas}/share:${gtk}/share:$out/share"
    wrapProgram "$out/libexec/gnome-shell-calendar-server" \
      --prefix XDG_DATA_DIRS : "${evolution_data_server}/share:$out/share"
  '';

  meta = with stdenv.lib; {
    platforms = platforms.linux;
  };

}
