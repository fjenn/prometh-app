# M9: QA, licenses, credits

## What landed

- `Docs/progress/M9/parity.md` lists the 30 prompts. Every score is PENDING MAC VERIFICATION. None were filled in from this host.
- `Docs/LICENSES-PROMETH.md` and `NOTICE-PROMETH.md` record the §10 components. `LICENSE` is still Nativ's MIT text.
- Settings › Privacy & data has a Credits button. The sheet is closed unless that button is pressed. Its first line is "Built on Nativ", with the upstream SHA `6ef4ba92a9a0dc72b1a2e9e4a1e0dca8e7d048e3`. The settings walk that checks hidden labels does not open this sheet.
- ffmpeg is not bundled. The media mock uses an ffmpeg that is already on the machine.

## Linux

`swiftc` is not installed. `PromethCreditsTests` was not executed. `make verify` and `xcodebuild` were not run. No model weights were downloaded for a scored chat.

## Performance checklist (test Mac)

Record the chip and RAM. All three timings are PENDING.

- Cold launch to an interactive window in under 2 seconds.
- First Safe token in under 2 seconds after a warm load.
- Search answer in under 25 seconds.

Also PENDING: Light, Dark, and Reduce Motion / Reduce Transparency screenshots of every screen, and a VoiceOver pass through onboarding and sending a message.

```
scripts/prometh/build.sh
make verify
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethTests
xcodebuild test -project Nativ.xcodeproj -scheme Prometh \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/NativDevelopmentDerivedData \
  NATIV_PRODUCT_NAME=Prometh CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO \
  -only-testing:PromethUITests
```

## Upstream merge dry run

```
git fetch https://github.com/Blaizzy/nativ.git main
git merge --no-commit --no-ff FETCH_HEAD
git diff --name-only --diff-filter=U
git merge --abort
```

Upstream `main` was `8547cd4e1fe6b5e7bb90d937ddf2dedaa94a0571`. The merge stopped before a commit and reported no unmerged paths. The abort left `prometh` unchanged.

A real merge would bring these upstream edits, which merged cleanly and are not seam files:

- `.github/workflows/dev-build.yml`
- `PythonDistribution/Scripts/generate_model_capabilities_manifest.py`
- `Sources/Nativ/Features/Models/LocalModelDiscovery.swift`
- `Sources/Nativ/Features/Models/ModelPrimaryTaskResolver.swift`
- `Sources/Nativ/Features/Models/ModelsView.swift`
- `Sources/Nativ/NativModel.swift`
- `Sources/NativServerKit/NativModelTypeRegistry.swift`
- `Tests/NativTests/LocalModelDiscoveryTests.swift`
- `Tests/NativTests/ModelPrimaryTaskResolverTests.swift`
- `scripts/tests/test_model_capabilities.py`

`xcodebuild` after a merge was not run.
