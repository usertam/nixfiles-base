{ config, lib, pkgs, modulesPath, ... }:

# Dirty mkForce hacks here to substitute https://github.com/NixOS/nixpkgs/pull/236110.
with pkgs.stdenv.hostPlatform;

{
  imports = [ "${modulesPath}/virtualisation/azure-image.nix" ];

  # Bypass isx86 assertion in nixos/modules/virtualisation/azure-agent.nix.
  assertions = lib.mkIf (!isx86) (lib.mkForce []);

  # Generate a GRUB menu ONLY when booting in BIOS.
  boot.loader.grub.device = lib.mkIf (!isx86) (lib.mkForce "nodev");

  # Enable GRUB EFI support if needed.
  boot.loader.grub.efiSupport = lib.mkIf (!isx86) true;
  boot.loader.grub.efiInstallAsRemovable = lib.mkIf (!isx86) true;

  # Mount ESP for EFI support.
  fileSystems."/boot" = lib.mkIf (!isx86) {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };

  # Force override image creation.
  system.build.azureImage = lib.mkForce (import "${modulesPath}/../lib/make-disk-image.nix" {
    name = "azure-image";
    postVM = ''
      ${pkgs.vmTools.qemu}/bin/qemu-img convert -f raw -o subformat=fixed -O vpc $diskImage \
        $out/azure.${pkgs.system}.vhd
      rm $diskImage
    '';
    format = "raw";
    partitionTableType = if (!isx86) then "efi" else "legacy";
    inherit (config.virtualisation.azureImage) diskSize contents;
    inherit config lib pkgs;
  });

  networking.hostName = lib.mkOverride 900 "base";

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMRs9DrnxB9kZIe1ZQXAJrkaiW11dNvANWaxxquXX1x2"
  ];

  # Backport: Mount tmpfs on /tmp during boot.
  boot.tmp.useTmpfs = true;

  # TCP connections will timeout after 4 minutes on Azure.
  boot.kernel.sysctl."net.ipv4.tcp_keepalive_time" = 120;
  boot.kernel.sysctl."net.ipv4.tcp_keepalive_intvl" = 30;
  boot.kernel.sysctl."net.ipv4.tcp_keepalive_probes" = 8;

  # Disable reboot on system upgrades.
  system.autoUpgrade.allowReboot = false;

  # Enable zram swap.
  zramSwap.enable = true;
  zramSwap.memoryPercent = 100;

  # Try harder to grow partitions.
  systemd.services.growpart = {
    startLimitBurst = 5;
    startLimitIntervalSec = 60;
    serviceConfig.Restart = "on-failure";
    serviceConfig.RestartSec = 5;
    serviceConfig.RemainAfterExit = lib.mkForce false;
    onSuccess = [ "systemd-growfs-root.service" ];
  };

  # Let nix daemon use alternative TMPDIR.
  systemd.services.nix-daemon.environment.TMPDIR = "/nix/var/tmp";
  systemd.tmpfiles.rules = [
    "d /nix/var/tmp 0755 root root 1d"
  ];
}
