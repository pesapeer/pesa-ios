# Security

## Report a vulnerability

Email **security@pesa.co**. Do not open a public issue. We acknowledge
reports within two business days.

## Supported versions

Only the latest minor release gets fixes. Upgrade to get them.

## What this SDK does with card data

The README section "How the SDK keeps card data safe" describes it.

## Verify a release

Each release is a `v*` tag on a commit signed by a maintainer. GitHub
Actions builds and publishes it. The workflow refuses a tag whose commit
is not signed by a key in `.github/allowed_signers`. Verify a release
before you depend on it.
