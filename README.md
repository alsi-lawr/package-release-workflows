# Package Release Workflows

Reusable GitHub workflows for release packaging and publishing.

- `package-dotnet.yml`: wrapper workflow for .NET projects (run this in callers).
- `package-release.yml`: build-agnostic core release pipeline.
- `package.yml`: shared .NET build/versioning steps used by `package-dotnet.yml`.

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

Secrets belong to the calling repository. GitHub does not expose ordinary secrets from the repository that stores a reusable workflow to its callers.
