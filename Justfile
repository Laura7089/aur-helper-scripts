#!/bin/env -S just --justfile

NVCHECKER_CONFIG := `mktemp -u -p. .nvcheckerXXXXXXX.temp.toml`

REPRO_CACHE := justfile_directory() / ".repro-cache"
REPRO_BUILD := invocation_directory() / "repro-build"

# build the package
[no-cd]
[no-exit-message]
[group('build & test (invoke next to PKGBUILD)')]
build *args="--syncdeps":
    makepkg {{args}}

# build the package in a clean chroot with aurutils
[no-cd]
[no-exit-message]
[group('build & test (invoke next to PKGBUILD)')]
build-chroot *args="--update":
    aur chroot --temp --build {{ args }}

[no-cd]
[private]
latest:
    find . -maxdepth 1 -type f -name "*.pkg.*" | tail -1

# build and install the package
[no-cd]
[no-exit-message]
[group('build & test (invoke next to PKGBUILD)')]
install *args="": (build "-si" args)

# check the package with namcap
[no-cd]
[group('build & test (invoke next to PKGBUILD)')]
check *args="": (build "--force")
    namcap {{args}} PKGBUILD
    namcap {{args}} "$(just latest)"

# generate the .SRCINFO file
[no-cd]
[no-exit-message]
[group('utilities (invoke next to PKGBUILD)')]
srcinfo:
    makepkg --printsrcinfo > .SRCINFO

# fetch sources and update checksums
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
[no-exit-message]
checksums: clean
    -makepkg --nobuild --force
    @echo '{{BLUE+BOLD}}INFO{{NORMAL}}: downloaded clean sources, checksum errors are expected'
    updpkgsums
    @echo '{{BLUE+BOLD}}INFO{{NORMAL}}: re-downloading sources, checksum errors should not occur'
    makepkg --nobuild --force
alias sums := checksums

# create a basic gitignore file
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
[no-exit-message]
gitignore:
    @[ ! -f .gitignore ] || (echo 'existing gitignore found, exiting with failure' && exit 1)
    printf "pkg\nsrc\n*.pkg.*\n*.tar.gz\n*.log\n*.part" > .gitignore

# initialise the AUR git repo for a package
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
gitinit repo=file_stem(invocation_dir()):
    @if [[ -e .git ]]; then \
        echo "existing git repo found, exiting"; \
        exit 1; \
    fi
    git init --initial-branch=master
    just gitignore
    @if git ls-remote -h "https://aur.archlinux.org/{{repo}}.git" >/dev/null ; then \
         echo "$(tput bold)$(tput setaf 3)WARNING: an upstream AUR package already exists under this name$(tput sgr0)"; \
    fi
    git remote add origin \
        "https://aur.archlinux.org/{{repo}}.git"
    git config push.autoSetupRemote true

# create a new package
new name type="normal":
    mkdir -p "{{name}}"
    cp \
        /usr/share/pacman/PKGBUILD{{ if type != "normal" { "-" + type } else { "" } }}.proto \
        "{{name}}/PKGBUILD"
    cd "{{name}}" && just gitinit
    @echo "Don't forget to add nvchecker configuration for {{name}}!"

# clean a package directory
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
clean: && cleangitignore
    @[ -f PKGBUILD ] || (echo "no PKGBUILD found, exiting for safety" && exit 1)
    rm -rfv pkg src
    rm -fv *.pkg.*

[private]
[no-cd]
cleangitignore:
    #!/bin/sh
    set -eux

    if [[ -e .gitignore ]]; then
        globs="$(grep '^[^!#]' .gitignore | grep -v .gitignore)"
        for glob in $globs; do
            sh -c "rm -rfv $glob"
        done
    fi

# clean all packages in the entire root repo
[no-exit-message]
cleanall method="ok":
    find \
        -maxdepth 1 -mindepth 1 \
        -type d \
        -not -name legacy -not -name ".*" \
        "-{{ method }}" sh -c '(cd {} && just clean)' \;

# bump a pkg version (naive)
[group('utilities (invoke next to PKGBUILD)')]
[no-cd]
bump version: && checksums
    sed -i 's/^pkgver=.*$/pkgver={{ version }}/' PKGBUILD

[private]
makenvcconfig:
    [ -f .nvchecker_keys.toml ] || echo '[keys]' > .nvchecker_keys.toml
    cp nvchecker_config.toml "{{ NVCHECKER_CONFIG }}"
    find -name nvchecker.toml -exec cat {} + >> "{{ NVCHECKER_CONFIG }}"

[no-exit-message]
[private]
removenvcconfig:
    rm "{{ NVCHECKER_CONFIG }}"

# check for new versions of configured packages
[no-exit-message]
[group('version management')]
updates *args="": makenvcconfig && removenvcconfig
    -nvchecker -c "{{ NVCHECKER_CONFIG }}" {{ args }}

# mark packages as having been updated
[no-exit-message]
[group('version management')]
markupdated *names="": makenvcconfig && removenvcconfig
    nvtake -c "{{ NVCHECKER_CONFIG }}" {{ \
        if names == "" { \
            trim_end_match(file_stem(invocation_dir()), "-bin") \
        } else { \
            names \
        } \
    }}

# open the upstream in a browser
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
openurl:
    {{env("BROWSER", "xdg-open")}} "$(just get_var url)"

# run repro on a package
[no-cd]
[no-exit-message]
[group('build & test (invoke next to PKGBUILD)')]
repro dir="./repro-build" *args="-d": (build "--force")
    CACHEDIR="{{ REPRO_CACHE }}" \
        repro \
        -o "{{ REPRO_BUILD }}" \
        {{ args }} \
         "$(just latest)"

# print the pkgver of a package
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
version: (get_var "pkgver")

# print the value of a variable from PKGBUILD
[no-cd]
[no-exit-message]
[group('utilities (invoke next to PKGBUILD)')]
get_var var:
    bash -c 'source PKGBUILD && echo "${{var}}"'
