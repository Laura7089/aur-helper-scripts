#!/bin/env -S just --justfile

NVCHECKER_CONFIG := `mktemp -u -p. .nvcheckerXXXXXXX.temp.toml`

PKG_NAME := file_stem(invocation_dir())
PKG_NAME_NOBIN := trim_end_match(PKG_NAME, "-bin")

REPRO_CACHE := justfile_directory() / ".repro-cache"
REPRO_BUILD := invocation_directory() / "repro-build"

[private]
log colour tag +text:
    @echo "{{colour+BOLD+tag+NORMAL+BOLD}}: {{text}}{{NORMAL}}"
[private]
info +text: (log BLUE "info" text)
[private]
warn +text: (log YELLOW "warn" text)
[private]
[no-exit-message]
err +text: (log RED "error" text)
    @exit 1

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
    aur chroot --temp --build {{args}}

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
    -find-libprovides "$(just latest)"

# generate the .SRCINFO file
[no-cd]
[no-exit-message]
[group('utilities (invoke next to PKGBUILD)')]
srcinfo:
    makepkg --printsrcinfo > .SRCINFO

# fetch sources
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
[no-exit-message]
fetch *args="": clean
    makepkg --noprepare --nobuild --force {{args}}

# update checksums
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
[no-exit-message]
checksums: (fetch "--skipinteg")
    updpkgsums
    @just info 're-downloading sources, checksum errors should not occur'
    just clean ""
    makepkg --verifysource
alias sums := checksums

# create a basic gitignore file
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
[no-exit-message]
gitignore:
    @[ ! -f .gitignore ] || just err 'existing gitignore found'
    printf "pkg\nsrc\n*.pkg.*\n*.tar.gz\n*.log\n*.part" > .gitignore

# initialise the AUR git repo for a package
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
gitinit repo=PKG_NAME: && gitignore
    @[[ ! -e .git ]] || just err 'existing git repo found'
    git init --initial-branch=master
    git remote add origin \
        "https://aur.archlinux.org/{{repo}}.git"
    git config push.autoSetupRemote true

# create a new package
new name type="normal": && (info "don't forget to add nvchecker configuration for" name)
    mkdir -p "{{name}}"
    cp \
        /usr/share/pacman/PKGBUILD{{ if type != "normal" { "-" + type } else { "" } }}.proto \
        "{{name}}/PKGBUILD"
    cd "{{name}}" && just gitinit

# clean a package directory
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
clean *rmargs="-v": && cleangitignore
    @[ -f PKGBUILD ] || just err 'no PKGBUILD found, exiting for safety'
    rm -rf {{rmargs}} pkg src
    rm -f {{rmargs}} *.pkg.*

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
        "-{{method}}" sh -c '(cd {} && just clean)' \;

# bump a pkg version (naive)
[group('utilities (invoke next to PKGBUILD)')]
[no-cd]
bump version: && checksums srcinfo check markupdated
    @if grep '^pkgver={{version}}' PKGBUILD; then \
        just err 'PKGBUILD already contains this version'; \
    fi
    sed -i 's/^pkgver=.*$/pkgver={{version}}/' PKGBUILD
    sed -i 's/^pkgrel=.*$/pkgrel=1/' PKGBUILD

[private]
makenvcconfig:
    [ -f .nvchecker_keys.toml ] || echo '[keys]' > .nvchecker_keys.toml
    cp nvchecker_config.toml "{{NVCHECKER_CONFIG}}"
    find -name nvchecker.toml -exec cat {} + >> "{{NVCHECKER_CONFIG}}"

[no-exit-message]
[private]
removenvcconfig:
    rm "{{NVCHECKER_CONFIG}}"

# check for new versions of configured packages
[no-exit-message]
[group('version management')]
updates *args="": makenvcconfig && removenvcconfig
    -nvchecker -c "{{NVCHECKER_CONFIG}}" {{args}}

# mark packages as having been updated
[no-exit-message]
[group('version management')]
markupdated *names=PKG_NAME_NOBIN: makenvcconfig && removenvcconfig
    nvtake -c "{{NVCHECKER_CONFIG}}" {{names}}

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
    CACHEDIR="{{REPRO_CACHE}}" \
        repro \
        -o "{{REPRO_BUILD}}" \
        {{args}} \
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
