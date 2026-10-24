{ ... }:

{
  users.users.root.openssh.authorizedKeys.keys = [
    # Deployment key
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOHh+5N+vJpAqRtETZx5u9F8Dd2vaDjH5c4BwCkZayqB deploy-rs"
  ];

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
    };
  };

  nix.settings.trusted-users = [ "root" ];
  security.sudo.wheelNeedsPassword = true;
}
