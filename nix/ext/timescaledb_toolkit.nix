{
  lib,
  pkgs,
  callPackages,
  fetchFromGitHub,
  postgresql,
  rust-bin,
  latestOnly ? false,
}:

let
  pname = "timescaledb_toolkit";

  build =
    version: hash: cargoHash: rustVersion: pgrxVersion:
    let
      cargo = rust-bin.stable.${rustVersion}.default;
      mkPgrxExtension = callPackages ../cargo-pgrx/mkPgrxExtension.nix {
        inherit rustVersion pgrxVersion rust-bin;
      };
    in
    mkPgrxExtension rec {
      inherit pname version postgresql cargoHash;

      src = fetchFromGitHub {
        owner = "timescale";
        repo = "timescaledb-toolkit";
        rev = version;
        inherit hash;
      };

      nativeBuildInputs = [ cargo ];
      CARGO = "${cargo}/bin/cargo";

      # Tests take a long time according to nixpkgs
      doCheck = false;

      postInstall = ''
        cargo run --manifest-path ./tools/post-install/Cargo.toml -- --dir "$out"
      '';

      meta = {
        description = "Extension for more hyperfunctions, fully compatible with TimescaleDB and PostgreSQL";
        homepage = "https://github.com/timescale/timescaledb-toolkit";
        license = lib.licenses.tsl;
      };
    };

  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  versionsToUse =
    if latestOnly then
      { "${latestVersion}" = supportedVersions.${latestVersion}; }
    else
      supportedVersions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash value.cargoHash value.rust value.pgrx) versionsToUse
  );
  versionsBuilt = if latestOnly then [ latestVersion ] else versions;
  numberOfVersionsBuilt = builtins.length versionsBuilt;
in
pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];

  passthru = {
    perVersion = lib.mapAttrs (name: value: build name value.hash value.cargoHash value.rust value.pgrx) versionsToUse;
    versions = versionsBuilt;
    numberOfVersions = numberOfVersionsBuilt;
    inherit pname latestOnly;
    version =
      if latestOnly then
        latestVersion
      else
        "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
