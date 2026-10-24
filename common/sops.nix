{ ... }:

{
  # Host age key is derived from the SSH host key (no extra key distribution).
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.age.generateKey = false;

  # Uncomment once secrets/common.yaml exists:
  # sops.defaultSopsFile = ../secrets/common.yaml;
  # sops.secrets.example = { };   # -> config.sops.secrets.example.path
}
