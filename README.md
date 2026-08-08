# Blinko iOS

Native iOS client for Blinko.

## Requirements

- macOS with Xcode 15 or later
- iOS 17+ deployment target

## Build and test

```bash
./scripts/ci-build.sh    # build for the simulator
./scripts/ci-test.sh     # build + run unit tests
```

These are the same scripts CI runs. See [docs/CI-CD.md](docs/CI-CD.md) for
configuration options and troubleshooting.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [CI/CD](docs/CI-CD.md)
- [Roadmap](ROADMAP.md)
