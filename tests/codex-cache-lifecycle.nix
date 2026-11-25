{ self ? builtins.getFlake ("path:" + toString ../.)
, inputs ? self.inputs
, pkgs ? inputs.nixpkgs.legacyPackages.x86_64-linux
, root ? "/codex-cache-fixture"
, sandbox ? false
}:
let
  mkHome = name:
    let
      config = (inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ self.homeManagerModules.default {
          home.username = "tester";
          home.homeDirectory = "${root}/${name}";
          home.stateVersion = "26.05";
          programs.codexBase.enable = true;
          programs.codexBase.writableRoots = [ ];
        } ];
      }).config;
      rules = config.systemd.user.tmpfiles.rules;
    in
    assert builtins.length rules == 1;
    assert pkgs.lib.hasPrefix "d " (builtins.head rules);
    assert pkgs.lib.hasSuffix " 0700 - - - -" (builtins.head rules);
    assert builtins.hasAttr "systemd/user/basic.target.wants/systemd-tmpfiles-setup.service" config.xdg.configFile;
    {
      home = config.home.homeDirectory;
      cache = "${config.xdg.cacheHome}/codex-shell";
      activation = config.home.activation.codex-base-config.data;
      tmpfiles = config.xdg.configFile."user-tmpfiles.d/home-manager.conf".text;
    };
  fixture = {
    homes = map mkHome [ "home one%" "home two%" ];
    hmShell = "${inputs.home-manager}/lib/bash/home-manager.sh";
    tmpfiles = "${pkgs.systemd}/bin/systemd-tmpfiles";
  } // pkgs.lib.optionalAttrs sandbox {
    bash = "${pkgs.bash}/bin/bash";
    codex = "${self.packages.x86_64-linux.codex}/bin/codex";
    nix = "${pkgs.nix}/bin/nix";
    sandboxPath = pkgs.lib.makeBinPath [ pkgs.coreutils ];
    tar = "${pkgs.gnutar}/bin/tar";
  };
  context = builtins.getContext (builtins.toJSON fixture);
in
fixture // pkgs.lib.optionalAttrs sandbox {
  # Realize the exact tools and managed inputs referenced in the evaluated fixture.
  dependencies = builtins.concatMap (path:
    map (output: "${path}^${output}") (context.${path}.outputs or [ ])
  ) (builtins.attrNames context);
}
