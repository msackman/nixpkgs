{ cabal, regexBase, regexTdfa }:

cabal.mkDerivation (self: {
  pname = "regex-compat-tdfa";
  version = "0.95.1.4";
  sha256 = "1p90fn90yhp7fvljjdqjp41cszidcfz4pw7fwvzyx4739b98x8sg";
  buildDepends = [ regexBase regexTdfa ];
  meta = {
    homepage = "http://hub.darcs.net/shelarcy/regex-compat-tdfa";
    description = "Unicode Support version of Text.Regex, using regex-tdfa";
    license = self.stdenv.lib.licenses.bsd3;
    platforms = self.ghc.meta.platforms;
  };
})
