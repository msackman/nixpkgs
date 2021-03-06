{ cabal, bifunctors, utf8String }:

cabal.mkDerivation (self: {
  pname = "multiarg";
  version = "0.26.0.0";
  sha256 = "0fjzjr66yan62911kfndnr7xmy3waidh4cqazabk6yr1cznpsx8m";
  buildDepends = [ bifunctors utf8String ];
  meta = {
    homepage = "https://github.com/massysett/multiarg";
    description = "Combinators to build command line parsers";
    license = self.stdenv.lib.licenses.bsd3;
    platforms = self.ghc.meta.platforms;
    maintainers = [ self.stdenv.lib.maintainers.andres ];
  };
})
