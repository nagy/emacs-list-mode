{
  description = "Base major mode for Emacs tables of row objects (Emacs package)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      # One nixpkgs closure, no duplicates.
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      flake-parts,
      nixpkgs,
      treefmt-nix,
      ...
    }:
    let
      # Date of the last commit as YYYY-MM-DD, folded into the version
      # string below.  The flake source info gives e.g. "20261126120000",
      # so slice out the year, month and day.  A plain path source has no
      # date, and the epoch fallback keeps the version parseable.
      lastModifiedDate = inputs.self.lastModifiedDate or "19700101000000";
      commitDate = "${builtins.substring 0 4 lastModifiedDate}-${
        builtins.substring 4 2 lastModifiedDate
      }-${builtins.substring 6 2 lastModifiedDate}";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      # The treefmt module provides the `formatter' output and a
      # `checks.<system>.treefmt' gate for `nix flake check'.
      imports = [ treefmt-nix.flakeModule ];

      # Elisp is arch-independent, so one system covers every consumer.
      systems = [ "x86_64-linux" ];

      perSystem =
        {
          pkgs,
          lib,
          config,
          ...
        }:
        let
          version = "0.1.0-unstable-${commitDate}";

          # The package stays overridable, so a consumer can swap the
          # Emacs, its package set, the build function or the optional
          # evil package:
          #   inputs.list-mode.packages.${system}.default.override {
          #     emacs = pkgs.emacs-nox;
          #   }
          # The flake passes the commit-derived version, because a plain
          # import of the expression cannot know it.
          listMode = lib.makeOverridable (
            {
              # One Emacs package set supplies every dependency, so an
              # override of this argument moves all of them.
              emacs ? pkgs.emacs,
              emacsPackages ? emacs.pkgs,
              melpaBuild ? emacsPackages.melpaBuild,
              version ? "0.1.0",
              # list-mode-evil.el needs evil to compile, but the package
              # must not depend on it.  The load path carries the elisp
              # directory for the build and the check only.
              evil ? emacsPackages.evil,
            }:
            let
              # The build and install phases run `emacs -Q' from PATH, so
              # a wrapper that carries evil puts it on the load path.
              # `packageRequires' never reaches that path.
              buildEmacs = emacsPackages.emacsWithPackages (_: [ evil ]);
            in
            melpaBuild {
              pname = "list-mode";
              preferLocalBuild = true;
              inherit version;

              src = lib.cleanSource ./.;

              # package.el, package-lint and the store path must agree on
              # the version, and the header carries the release number
              # alone.  Rewrite it to the derived string.
              postPatch = ''
                substituteInPlace list-mode.el \
                  --replace-fail ';; Version: 0.1.0' ';; Version: ${version}'
              '';

              preBuild = ''
                export PATH="${buildEmacs}/bin:$PATH"
              '';

              # A consumer that swaps the build Emacs still gets evil on
              # the load path for the optional layer.
              preInstall = ''
                evil_dir=$(find ${evil}/share/emacs/site-lisp/elpa \
                  -mindepth 1 -maxdepth 1 -type d -name 'evil-*' -print -quit)
                export EMACSLOADPATH="$evil_dir:''${EMACSLOADPATH-}"
              '';

              # Byte-compilation warnings fail the build.  Keep it on: it is
              # the cheapest lint the package gets.
              turnCompilationWarningToError = true;

              doCheck = true;
              # The hook gives Emacs a writable HOME for the check alone.
              nativeCheckInputs = [ pkgs.writableTmpDirAsHomeHook ];
              # No file lists here: the phase globs the tree.  The suite
              # lives in test/, which no MELPA `files' spec descends into,
              # so the tarball never carries a test file.
              checkPhase = ''
                runHook preCheck

                evil_load_path=$(find ${evil}/share/emacs/site-lisp/elpa \
                  -mindepth 1 -maxdepth 1 -type d -name 'evil-*' -print -quit)

                echo '=== byte-compile ==='
                for file in *.el test/*.el; do
                  emacs --batch -L . -L test -L "$evil_load_path" \
                    --eval '(setq byte-compile-error-on-warn t)' \
                    -f batch-byte-compile "$file"
                done

                echo '=== ERT tests ==='
                # Glob every test file instead of listing them, so a new
                # test/<unit>-test.el needs no flake edit.  printf repeats
                # "-l %s" once per match.  failglob makes an empty glob a
                # shell error, so the || guard fires even without `set -e';
                # a loop over a zero-match glob would instead load the
                # helper alone and pass with no test.  Restore the default
                # right after: later globs must keep default semantics.
                # The unquoted $test_args is intentional, the words must
                # split back into -l <file> pairs.
                shopt -s failglob
                test_args=$(printf -- '-l %s ' test/*-test.el) \
                  || { echo 'no tests matched test/*-test.el' >&2; exit 1; }
                shopt -u failglob
                emacs --batch -L . -L test -L "$evil_load_path" \
                  -l list-mode-test-helper.el \
                  $test_args \
                  -f ert-run-tests-batch-and-exit

                runHook postCheck
              '';

              meta = {
                description = "Base major mode for Emacs tables of row objects";
                longDescription = ''
                  A base major mode for a read-only Emacs table whose every
                  row is a struct object.  A derived mode hands the buffer a
                  list of rows, and the table renders itself from them
                  through generic functions.

                  A row expands into child rows, to any depth, and the
                  child rows load lazily,
                  so a mode can fetch them in the background while the table
                  shows a placeholder.  Sorting, point keeping across a
                  refresh and column fitting come from tabulated-list-mode
                  and from this package.

                  The package has no runtime dependency beyond Emacs.  An
                  optional evil layer lives in list-mode-evil.el.
                '';
                license = lib.licenses.agpl3Plus;
                homepage = "https://github.com/nagy/emacs-list-mode";
                maintainers = with lib.maintainers; [ nagy ];
                platforms = lib.platforms.unix;
              };
            }
          ) { inherit version; };
        in
        {
          # One canonical formatting config: `nix fmt' runs nixfmt, and
          # `nix flake check' rebuilds the treefmt check.
          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };

          packages.list-mode = listMode;
          packages.default = listMode;

          # `nix flake check' builds the package, so the check phase
          # (byte-compile with warnings as errors, full ERT suite) gates
          # the whole repo rather than only `nix build'.
          checks.package = listMode;

          # Same derivation under the name every other flake exposes, so
          # `nix build .#checks.<system>.default' works here too.
          checks.default = listMode;

          # package-lint: ELPA policy (headers, symbol prefixes,
          # dependency declarations).  The main file supplies the prefix
          # and the dependency list for every file, because the optional
          # evil layer carries no header of its own.
          checks.package-lint =
            pkgs.runCommandLocal "list-mode-package-lint"
              {
                nativeBuildInputs = [
                  (pkgs.emacsPackages.emacsWithPackages (p: [
                    p.package-lint
                  ]))
                  # Emacs writes ~/.emacs.d, so the check needs a writable
                  # home.  The hook owns it, and a shared $TMPDIR never
                  # leaks state into another check.
                  pkgs.writableTmpDirAsHomeHook
                ];
                src = ./.;
              }
              ''
                cp -r "$src"/. .
                emacs --batch -l package-lint \
                  --eval '(setq package-lint-main-file "list-mode.el")' \
                  -f package-lint-batch-and-exit \
                  *.el test/*.el
                touch $out
              '';

          # checkdoc: docstring conventions, which byte-compilation cannot
          # check.  checkdoc exits 0 on findings, so the check gates on
          # non-empty output.
          checks.checkdoc =
            pkgs.runCommandLocal "list-mode-checkdoc"
              {
                nativeBuildInputs = [
                  pkgs.emacs
                  pkgs.writableTmpDirAsHomeHook
                ];
                src = ./.;
              }
              ''
                cp -r "$src"/. .
                lint_log=$(emacs --batch -l checkdoc \
                  --eval '(setq checkdoc-arguments-in-order-flag t)' \
                  --eval "(mapc #'checkdoc-file command-line-args-left)" \
                  *.el test/*.el 2>&1)
                if [ -n "$lint_log" ]; then printf '%s\n' "$lint_log"; exit 1; fi
                touch $out
              '';

          devShells.default = pkgs.mkShell {
            # Mirror what the package needs at runtime: a real Emacs, the
            # optional evil layer and the formatter.  Elisp needs no
            # compiler toolchain beside them.
            packages = [
              (pkgs.emacsPackages.emacsWithPackages (p: [ p.evil ]))
              config.treefmt.build.wrapper
            ];
          };
        };
    };
}
