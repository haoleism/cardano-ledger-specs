{
  extras = hackage:
    {
      packages = {
        "sequence" = (((hackage.sequence)."0.9.8").revisions).default;
        "tasty-hedgehog" = (((hackage.tasty-hedgehog)."0.2.0.0").revisions).default;
        "tasty-hedgehog-coverage" = (((hackage.tasty-hedgehog-coverage)."0.1.0.0").revisions).default;
        "base58-bytestring" = (((hackage.base58-bytestring)."0.1.0").revisions).default;
        "half" = (((hackage.half)."0.2.2.3").revisions).default;
        "micro-recursion-schemes" = (((hackage.micro-recursion-schemes)."5.0.2.2").revisions).default;
        "streaming-binary" = (((hackage.streaming-binary)."0.3.0.1").revisions).default;
        "pretty-show" = (((hackage.pretty-show)."1.8.2").revisions).default;
        } // {
        delegation = ./delegation.nix;
        cs-blockchain = ./cs-blockchain.nix;
        cs-ledger = ./cs-ledger.nix;
        small-steps = ./small-steps.nix;
        non-integer = ./non-integer.nix;
        cborg = ./cborg.nix;
        cardano-crypto = ./cardano-crypto.nix;
        hedgehog = ./hedgehog.nix;
        canonical-json = ./canonical-json.nix;
        };
      compiler.version = "8.6.3";
      compiler.nix-name = "ghc863";
      };
  resolver = "lts-13.4";
  compiler = "ghc-8.6.3";
  }
