# Parlo — on-device AI speaking partner (iOS). See TOOLS.md for details.

set shell := ["bash", "-euo", "pipefail", "-c"]

app := "Parlo"

# List available recipes
default:
    @just --list

# Generate the Xcode project (xcodegen) and resolve SPM dependencies
bootstrap:
    @if [ ! -f project.yml ]; then \
        echo "ERROR: project.yml not found — this repo is still a docs-only scaffold."; \
        echo "Create project.yml (XcodeGen spec: '{{app}}' app target + local SPM packages under Packages/),"; \
        echo "then re-run 'just bootstrap'. Expected layout: DESIGN.md > Milestones > M0."; \
        exit 1; \
    fi
    xcodegen generate
    xcodebuild -resolvePackageDependencies -project {{app}}.xcodeproj -scheme {{app}} | tail -5

# Build the SPM packages, plus the app for the iOS Simulator when bootstrapped
build:
    swift build
    @if [ ! -d {{app}}.xcodeproj ]; then \
        echo "NOTICE: {{app}}.xcodeproj missing — SPM build done; run 'just bootstrap' for the app shell."; \
    else \
        sim="$(just _sim-name)"; \
        if [ -z "$sim" ]; then \
            echo "NOTICE: no iPhone simulator runtime available — skipping app build."; \
        else \
            echo "Building {{app}} for simulator: $sim"; \
            xcodebuild build -project {{app}}.xcodeproj -scheme {{app}} \
                -destination "platform=iOS Simulator,name=$sim" -quiet | tail -20; \
        fi; \
    fi

# Run package tests (swift test) plus app tests on a simulator when available
test:
    swift test
    @if [ ! -d {{app}}.xcodeproj ]; then \
        echo "NOTICE: {{app}}.xcodeproj missing — package tests done; run 'just bootstrap' for app tests."; \
    else \
        sim="$(just _sim-name)"; \
        if [ -z "$sim" ]; then \
            echo "NOTICE: no iPhone simulator runtime available — skipping app tests."; \
        else \
            echo "Testing {{app}} on simulator: $sim"; \
            xcodebuild test -project {{app}}.xcodeproj -scheme {{app}} \
                -destination "platform=iOS Simulator,name=$sim" -quiet | tail -40; \
        fi; \
    fi

# Lint Swift sources with swiftlint (skips gracefully when not installed)
lint:
    @if command -v swiftlint >/dev/null 2>&1; then \
        swiftlint; \
    else \
        echo "NOTICE: swiftlint not installed — skipping lint (brew install swiftlint to enable)."; \
    fi

# Format Swift sources with swiftformat
format:
    @command -v swiftformat >/dev/null 2>&1 || { echo "ERROR: swiftformat not installed (brew install swiftformat)."; exit 1; }
    swiftformat .

# verify formatting (swiftformat --lint); CI gate
format-check:
    @command -v swiftformat >/dev/null 2>&1 || { echo "ERROR: swiftformat not installed (brew install swiftformat)."; exit 1; }
    swiftformat --lint .

# Full pipeline: lint + build + test (what CI runs)
ci: lint build test format-check

# (internal) First available iPhone simulator, preferring iPhone 16
[private]
_sim-name:
    @names="$(xcrun simctl list devices available 2>/dev/null | sed -n 's/^ *\(iPhone[^(]*\)(.*/\1/p' | sed 's/ *$//')"; \
    if echo "$names" | grep -qx "iPhone 16"; then \
        echo "iPhone 16"; \
    else \
        echo "$names" | head -1; \
    fi
