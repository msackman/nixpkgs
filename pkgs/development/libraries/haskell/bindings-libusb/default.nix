{ cabal, bindingsDSL, libusb }:

cabal.mkDerivation (self: {
  pname = "bindings-libusb";
  version = "1.4.4.1";
  sha256 = "1cip5a0n8svjkzawpx3wi9z7nywmn9bl3k2w559b3awy0wixybrx";
  buildDepends = [ bindingsDSL ];
  pkgconfigDepends = [ libusb ];
  meta = {
    homepage = "https://github.com/basvandijk/bindings-libusb";
    description = "Low level bindings to libusb";
    license = self.stdenv.lib.licenses.bsd3;
    platforms = self.ghc.meta.platforms;
  };
})
