#!/bin/env -S just --justfile

PKG_GLOB := "*.pkg.*"
BROWSER := env_var_or_default("BROWSER", "xdg-open")
NVCHECKER_CONFIG := `mktemp -u -p. .nvcheckerXXXXXXX.temp.toml`

# build the package
[no-cd]
[no-exit-message]
[group('build & test (invoke next to PKGBUILD)')]
build *args="--force --syncdeps": && check
    makepkg {{args}}

[no-cd]
[private]
latest:
    ls -1 {{PKG_GLOB}} | grep -v '\.sig$' | tail -1

# build and install the package
[no-cd]
[no-exit-message]
[group('build & test (invoke next to PKGBUILD)')]
install *args="--force":
    makepkg -si {{args}}

# check the package with namcap
[no-cd]
[group('build & test (invoke next to PKGBUILD)')]
check *args="":
    namcap {{args}} PKGBUILD
    namcap {{args}} "$(just latest)"

# generate the .SRCINFO file
[no-cd]
[no-exit-message]
[group('utilities (invoke next to PKGBUILD)')]
srcinfo:
    makepkg --printsrcinfo > .SRCINFO

# initialise the AUR git repo for a package
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
gitinit:
    #!/bin/bash
    set -euxo pipefail

    if [[ -e .git ]]; then
        echo "existing git repo found, exiting"
        exit 1
    fi
    git init --initial-branch=master
    echo "pkg" >> .gitignore
    echo "src" >> .gitignore
    echo '{{PKG_GLOB}}' >> .gitignore
    if git ls-remote -h "https://aur.archlinux.org/$(basename "$PWD").git" >/dev/null ; then echo "$(tput bold)WARNING: an upstream AUR package already exists under this name$(tput sgr0)"; fi
    git remote add origin \
        "ssh://aur@aur.archlinux.org/$(basename "$PWD").git"
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
    rm -fv {{PKG_GLOB}}

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
cleanall:
    find -maxdepth 1 -mindepth 1 -type d -not -name legacy \
        -ok sh -c '(cd {} && just clean)' \;

[private]
makenvcconfig:
    cp nvchecker_config.toml "{{ NVCHECKER_CONFIG }}"
    find -name nvchecker.toml -exec cat {} + >> "{{ NVCHECKER_CONFIG }}"

[no-exit-message]
[private]
removenvcconfig:
    rm "{{ NVCHECKER_CONFIG }}"

# check for new versions of configured packages
[no-exit-message]
[group('version management')]
updates: makenvcconfig && removenvcconfig
    -nvchecker -c "{{ NVCHECKER_CONFIG }}"

# mark packages as having been updated
[no-exit-message]
[group('version management')]
markupdated *names="": makenvcconfig && removenvcconfig
    nvtake -c "{{ NVCHECKER_CONFIG }}" {{ \
        if names == "" { \
            replace_regex(file_stem(invocation_directory()), "-bin$", "") \
        } else { \
            names \
        } \
    }}

# open the upstream in a browser
[no-cd]
[group('utilities (invoke next to PKGBUILD)')]
openurl:
    {{BROWSER}} "$(just get_var url)"

# run repro on a package
[no-cd]
[no-exit-message]
[group('build & test (invoke next to PKGBUILD)')]
repro *args="": (build)
    repro -f {{ args }} "$(just latest)"

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
