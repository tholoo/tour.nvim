{ pkgs, src }:
{
  plugin = pkgs.vimUtils.buildVimPlugin {
    pname = "tour.nvim";
    version = "0.1.0";
    inherit src;
    meta = {
      description = "Durable guided code walkthroughs for Neovim 0.13";
      license = pkgs.lib.licenses.mit;
    };
  };

  # Dereference the shared schema/example links so the installed skill is
  # self-contained, without maintaining another copy in the source repository.
  skill = pkgs.runCommand "tour-skill" { } ''
    cp -RL ${src}/skills/tour "$out"
  '';
}
