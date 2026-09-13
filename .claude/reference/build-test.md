## Build/test

```bash
make setup              # install git hooks and verify gitleaks is installed
make fmt-check          # rustfmt check
make lint               # actionlint + clippy examples
make secrets-scan-staged
```

