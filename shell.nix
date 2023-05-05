{ pkgs ? import <nixpkgs> {} }:

with pkgs;

let
  inherit (lib) optional optionals;

  # elixir = elixir_1_11;
  postgresql = postgresql_14;

  startDb = pkgs.writeScriptBin "startDb" ''
    echo "Initializing db"
    initdb -D $PGDATA

    echo "Starting DB ...."
     pg_ctl                                                  \
      -D $PGDATA                                            \
      -l $PGDATA/postgres.log                               \
      -o "-c unix_socket_directories='$PGDATA'"             \
      -o "-c listen_addresses='*'"                          \
      -o "-c log_destination='stderr'"                      \
      -o "-c logging_collector=on"                          \
      -o "-c log_directory='log'"                           \
      -o "-c log_filename='postgresql-%Y-%m-%d_%H%M%S.log'" \
      -o "-c log_min_messages=info"                         \
      -o "-c log_min_error_statement=info"                  \
      -o "-c log_connections=on"                            \
      start

    echo "initializing postgres db"
    createdb postgres --host $PGDATA

    echo "create postgres user"
    createuser postgres -s --host $PGDATA
    
  '';

  setupPhoenix = pkgs.writeScriptBin "setupPhoenix" ''
    mix local.hex --force && \
    mix local.rebar --force && \
    mix archive.install hex phx_new
  '';

  mainRebase = pkgs.writeScriptBin "mainRebase" ''
    git fetch --all && git rebase origin/main
  '';
  
  elixir = beam.packages.erlangR25.elixir.override {
    version = "1.14.4";
    sha256 = "sha256-mV40pSpLrYKT43b8KXiQsaIB+ap+B4cS2QUxUoylm7c=";
  };
in

mkShell {
    buildInputs = [ elixir git postgresql startDb nodejs setupPhoenix mainRebase]
        ++ optional stdenv.isLinux inotify-tools # For file_system on Linux.
        ++ optionals stdenv.isDarwin (with darwin.apple_sdk.frameworks; [
        # For file_system on macOS.
        CoreFoundation
        CoreServices
    ]);

    # Put the PostgreSQL databases in the project diretory.
    shellHook = ''
    mkdir -p .nix-shell
    export NIX_SHELL_DIR=$PWD/.nix-shell
    export MIX_HOME="$NIX_SHELL_DIR/.mix"
    export MIX_ARCHIVES="$MIX_HOME/archives"

    # Put the PostgreSQL databases in the project diretory.
    mkdir -p .db
    export PGDATA=$PWD/.db

    ####################################################################
    # Clean up after exiting the Nix shell using `trap`.
    # ------------------------------------------------------------------
    # Idea taken from
    # https://unix.stackexchange.com/questions/464106/killing-background-processes-started-in-nix-shell
    # and the answer provides a way more sophisticated solution.
    #
    # The main syntax is `trap ARG SIGNAL` where ARG are the commands to
    # be executed when SIGNAL crops up. See `trap --help` for more.
    ####################################################################
    trap \
      "
        ######################################################
        # Stop PostgreSQL
        ######################################################
        pg_ctl -D $PGDATA stop
      " \
      EXIT
  '';

    ####################################################################
  # Without  this, almost  everything  fails with  locale issues  when
  # using `nix-shell --pure` (at least on NixOS).
  # See
  # + https://github.com/NixOS/nix/issues/318#issuecomment-52986702
  # + http://lists.linuxfromscratch.org/pipermail/lfs-support/2004-June/023900.html
  ####################################################################

  LOCALE_ARCHIVE = if pkgs.stdenv.isLinux then "${pkgs.glibcLocales}/lib/locale/locale-archive" else "";
}
