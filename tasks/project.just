import 'core.just'

# 📦 Install what is needed (not implemented yet)
install sync_args="--all-groups":
    @header "$(doc project install)"
    @warn "This task is not implemented yet."


# 🚀 Prepare a release, update CHANGELOG file and bump versions
release add_tag="no" dry="no" unreleased="yes" length="-1":
    #! ./.shell-wrapper.sh
    header "$(doc project release)"
    if [ ! command -v git-cliff ]; then
        @error "git-cliff is not installed. Please install it first."
        exit 1
    fi
    new_tag=$(git-cliff --bumped-version)
    new_version="${new_tag#v}"  # Remove 'v' prefix

    if is_true "{{dry}}"; then
        # Handle unreleased flag
        if is_true "{{unreleased}}"; then
            info "Show only 'unreleased' changes"
        else
            if [ "{{length}}" -gt 0 ]; then
                info "Show {{length}} lines of changelog"
            else
                info "Show full changelog"
            fi
        fi

        header "Changelog start"

        # Build git-cliff command
        cmd="git-cliff --bump"
        if is_true "{{unreleased}}"; then
            cmd="$cmd --unreleased"
        fi

        # Get changelog
        cl=$(eval "$cmd")

        # Output appropriate portion of changelog
        if is_true "{{unreleased}}" || [ "{{length}}" -le 0 ]; then
            echo "$cl"
        else
            echo "$cl" | head -n "{{length}}"
            echo "..."
        fi

        header "Changelog end"
    else
        # Update CHANGELOG.md and bump version
        git-cliff --bump -u --prepend CHANGELOG.md
        # TODO add a bump version tool which works in general

        if [ -n "$new_tag" ]; then
            success "Bumped to version '$new_version' (tag '$new_tag')."
            info "Please check the entries in 'CHANGELOG.md' and update it accordingly."

            if is_true "{{add_tag}}"; then
                git tag -f "$new_tag"
                git push origin "$new_tag"
            fi
            warn "Did not update to new version tag."
        fi
    fi


# 🔢 Print current or next project version
version next="no":
    #! ./.shell-wrapper.sh
    version_file="{{justfile_dir()}}/.version"

    # Read version from pyproject.toml
    if [ -f "$version_file" ]; then
        # Try to get version from project.version first
        version=$(cat "$version_file")
        if [ -z "$version" ]; then
            error "Version file is empty, add version (e.g. 0.0.1)."
            version="unknown"
        fi
    else
        error "Version file does not exist, create '$version_file' with the version (e.g. 0.0.1)."
        version="unknown"
    fi

    if is_true "{{next}}"; then
        new_version=$(git-cliff --bumped-version | tr -d 'v')
        if [ "$new_version" = "$version" ]; then
            warn "No newer version available"
        fi
        echo "$new_version"
    else
        echo "$version"
        if [ "$version" = "unknown" ]; then
            exit 1
        fi
    fi

# ❓ Show help
[private]
[default]
help task="":
    @just-help project {{task}}
