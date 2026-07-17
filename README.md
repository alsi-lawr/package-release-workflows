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
    secrets: inherit
```
