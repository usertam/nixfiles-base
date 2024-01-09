{ lib, pkgs, ... }:

{
  nix = {
    # Use unstable version of nix.
    package = pkgs.nixVersions.unstable;

    # Lock nixpkgs in registry.
    registry.nixpkgs = {
      from = {
        type = "indirect";
        id = "nixpkgs";
      };
      to = let
        lock = lib.importJSON ../flake.lock;
      in {
        inherit (lock.nodes.nixpkgs.locked) rev;
        type = "github";
        owner = "nixos";
        repo = "nixpkgs";
      };
    };

    # Enable automatic garbage collection.
    gc.automatic = lib.mkDefault true;

    # Everyone loves experimental features!
    settings = {
      experimental-features = [
        "nix-command" "flakes"
        "auto-allocate-uids" "ca-derivations" "fetch-closure" "recursive-nix" "repl-flake"
      ] ++ lib.optional pkgs.stdenv.isLinux "cgroups";
      auto-allocate-uids = true;
    } // lib.optionalAttrs pkgs.stdenv.isLinux {
      use-cgroups = true;
    };
  };

  # Let nix daemon use alternative TMPDIR.
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/var/tmp";
  systemd.tmpfiles.rules = [
    "d /nix/var/tmp 0755 root root 1d"
  ];
}
