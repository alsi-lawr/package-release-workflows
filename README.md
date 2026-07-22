# Package Release Workflows

Reusable GitHub workflows for .NET release packaging and publishing. The caller is
the product authority; this repository owns the packaging graph.

- `package-dotnet.yml`: the one-call .NET release entry point for callers.
- `package.yml`: validates the tagged version across .NET, Nix, and JReleaser;
  publishes the five supported RIDs; assembles archives and metadata; checks
  SHA-256 checksums; and produces release-asset attestations.
- `package-release.yml`: validates credentials and package lifecycles, creates or
  verifies the GitHub release without overwriting it, publishes package metadata
  and images, then promotes versioned outputs to `latest` only after success.
- `release-package-tests.yml` and `validation.yml`: reusable archive and package
  lifecycle validation stages used by the release graph.

The release graph includes Homebrew, Scoop, Chocolatey, WinGet, Nixpkgs, Docker
Hub bot/site multi-architecture images, and Nix-built GHCR bot/site
multi-architecture images. `package.yml` requires the release matrix to contain
exactly `linux-x64`, `linux-arm64`, `osx-arm64`, `win-x64`, and `win-arm64`;
Linux archives are `.tar.gz` and macOS/Windows archives are `.zip`.

Tagged releases prepare and push the exact versioned WinGet and nixpkgs fork
branches, but never open upstream pull requests. Callers use the separate
submit-upstream-prs.yml reusable workflow from a thin workflow_dispatch caller
to submit either prepared branch after it verifies a matching non-draft GitHub
release and that the expected fork branch is ahead of the upstream default
branch. The manual workflow reports an existing open PR for the same fork branch
instead of creating a duplicate; it neither rebuilds or republishes artifacts nor
rewrites fork branches.

Usage:

```yaml
jobs:
  release:
    uses: OWNER/package-release-workflows/.github/workflows/package-dotnet.yml@main
    with: <workflow inputs>
    permissions:
      attestations: write
      contents: write
      id-token: write
      packages: write
    secrets:
      CHOCOLATEY_API_KEY: ${{ secrets.CHOCOLATEY_API_KEY }}
      DOCKERHUB_TOKEN: ${{ secrets.DOCKERHUB_TOKEN }}
      DOCKERHUB_USERNAME: ${{ secrets.DOCKERHUB_USERNAME }}
      PACKAGE_REPOSITORY_TOKEN: ${{ secrets.PACKAGE_REPOSITORY_TOKEN }}
```

Nested shared workflows use fully qualified `@main` references rather than
relative paths: GitHub resolves a relative reusable-workflow reference from the
caller commit, not from this repository. The shared repository must therefore be
accessible to every caller in the chain.

Secrets belong to the calling repository and must be forwarded explicitly as in
the example. GitHub does not expose ordinary secrets from the repository that
stores a reusable workflow to its callers. Callers also provide the product
paths, JReleaser configuration, Nix/Docker metadata, package repository forks,
and runners. A publishing caller needs `contents`, `packages`, `attestations`,
and `id-token` write permissions and the required credentials for every enabled
external channel.
