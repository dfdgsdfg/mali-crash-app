# Mali GLES crash reproducer

Minimal Flutter 3.44.8 app for reproducing Flutter issue #190640 on Android
Mali GPUs. The Impeller profile build explicitly selects the OpenGLES backend
from the crash stack. It drives image decode/resize, dark-mode `ColorFilter`, app-like
`Picture.toImage`/RGBA readback, surface rotation, and lifecycle churn.

No Firebase app registration or `google-services.json` is required. Firebase
Test Lab accepts the generated APK directly; only a Google Cloud project with
Test Lab enabled is needed.

## Scope and supported environment

This repository is a standalone reproduction and evidence record for
[Flutter issue #190640](https://github.com/flutter/flutter/issues/190640).
The primary target is a physical Samsung Galaxy S9 (`starlte`) on Android
10/API 29 with a Mali GLES driver. The reproducer is not a general Android
image-decoding benchmark: results from another device, API level, renderer, or
driver should be recorded as a separate control.

The deterministic renderer target is an Impeller profile APK with the
OpenGLES backend explicitly selected. The Skia flavor is the negative renderer
control. Test Lab artifacts and APK/engine binaries are intentionally excluded
from Git; local downloaded evidence remains under `test-results/`, and local
diagnostic builds remain under `build/mali-diagnostics/`.
Console links below are optional evidence and may require access to the
original Test Lab project; a reader can reproduce the run in any project with
Test Lab enabled.

The A/B contract is one frozen app commit, one scenario, and one device matrix.
The only intended variable is the Flutter engine embedded in the APK: stock
Flutter 3.44.8 for baseline versus a `dfdgsdfg/flutter` patched-engine branch
for the candidate fix. App branches are not used to represent the A/B.

For the key crash stack, sanitized GL chronology, and self-contained four-run
comparison, see the [reviewable crash evidence](docs/evidence.md).

## Scenarios

1. Light-mode image decode and resize baseline
2. Dark-mode decode, resize, and `ColorFilter`
3. Scenario 2 plus app-like 32 px GPU resize and RGBA readback
4. Scenario 3 plus repeated orientation/surface changes
5. Higher concurrency plus orientation and background/foreground churn
6. Scenario 3 workload with higher concurrency for external lifecycle control
7. Scenario 6 decode/display workload without GPU pixel readback (A/B control)
8. Production-like lazy 120-item feed with local 16:9 image-provider variants,
   bounded image cache, and automatic scrolling (no dark filter or pixel readback)
9. Scenario 8 plus the production disk-resize cache-miss probe: decode at the
   cache width, apply the `image.width <= maxWidth` discard decision, then let
   the framework decode the same source for display

Normal launches show a manual debug screen. Test Lab Game Loop launches select
the scenario automatically, emit `MaliRepro` logcat heartbeats, and finish with
a small JSON result artifact unless the process aborts first. Scenario 5's
lifecycle churn backgrounds and restores the existing task with
`ActivityManager.moveTaskToFront`; it does not launch a second Test Loop intent.
Cycle requests skip iterations that also rotate the surface, preserving the
6, 18, 30, … cycle cadence. A cycle is counted as complete only after window
focus returns; a three-second restore timeout reports a Test Loop failure. Both
`cycleTaskRequests` and `cycleTaskCompletions` are included in heartbeats and
the result JSON.
Scenarios 1–4 run for three minutes; the maximum-stress scenario 5 runs for ten
minutes. Scenario 6 keeps scenario 3's dark decode/GPU analysis with a batch of
20 and concurrency 8, leaving rotation and task cycling to the external
instrumentation harness; it also runs for ten minutes.
Scenario 7 keeps scenario 6's dark decode/display workload and batch/concurrency
settings but disables `Picture.toImage`/raw-RGBA pixel analysis as a control; it
also runs for ten minutes. The instrumentation harness accepts a `scenario`
argument and defaults to scenario 6. Scenario 8 uses 120 deterministic local
feed items admitted in 30-item pages. Its provider keys include the item and
the orientation-specific cache width (600 portrait, 1024 landscape), so each
orientation creates a distinct cache variant without reusing one `MemoryImage`
key. The 1280x720 source is decoded and displayed lazily in a scrolling list
with fixed keys and `RepaintBoundary`; it never performs GPU picture/readback
analysis. Its 48 MiB image cache cap and scroll/decode counters are included in
`MaliRepro` heartbeats and the final result JSON.
Scenario 9 preserves scenario 8's lazy feed and 48 MiB cache controls, but adds
the production cache-miss double-decode probe. Its
`feedResizeProbeRequests` and `feedResizeProbeCompletions` counters make it
possible to confirm that both phases ran on the device. Scenario 8 remains the
single-decode control.

## Investigation findings (updated 2026-09-02)

### Production path under test

The relevant production image path is:

```text
AppCachedNetworkImage
  -> ResizeImage.resizeIfNeeded(memCacheWidth, memCacheHeight, provider)
  -> AppCachedNetworkImageProvider
  -> AppImageLoader / FileCacheImageResize
  -> ui.instantiateImageCodec(bytes, targetWidth: maxWidth)
  -> getNextFrame()
  -> image.width <= maxWidth: discard the decoded image
  -> framework decodes the same source again for display
```

The `image.width <= maxWidth` check is an important guard in the production
disk-resize cache-miss path: when the requested target width is honored, the
probe output is thrown away and the display path performs a second decode.
This makes scenario 9 production-aligned, but does not by itself prove that
double decode is the engine root cause. The production image widths are 600 px
for mobile portrait and 1024 px for landscape/tablet, and Android's image-cache
cap is 48 MiB.

### Reproducer controls and telemetry

- Scenario 8 is the single-decode control: a lazy 120-item local feed, 30-item
  page admission, orientation-specific provider keys, target-size decode, and
  scrolling display. It has no disk-resize probe, dark filter, or GPU readback.
- Scenario 9 keeps those controls and adds the production cache-miss probe:
  target-size decode, the discard decision above, then the framework display
  decode of the same 1280x720 source.
- `MaliRepro` heartbeats/result JSON record scroll cycles, page admissions,
  provider variants, decoded items, cache maximum bytes, and scenario 9's
  `feedResizeProbeRequests`/`feedResizeProbeCompletions` counters.

### Firebase Test Lab results

All runs below used the physical Samsung Galaxy S9 (`starlte`), Android 10/API
29, portrait, with the Impeller profile APK forced to OpenGLES unless marked
Skia. The matrix IDs link to server-side Test Lab evidence. Downloaded logs
and result files are local-only and intentionally not committed. The [Firebase
Test Lab project](https://console.firebase.google.com/project/us-app-ea67d/testlab)
contains the server-side matrix pages for these historical runs.

| Workload | Matrix | Result | Evidence |
| --- | --- | --- | --- |
| Scenario 8, Impeller | [`matrix-2upg0u4rf50et`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/7340370323073090098) | Pass, 606 s; 120 decoded items | Local-only: `test-results/matrix-2upg0u4rf50et/…` |
| Scenario 9, Impeller | [`matrix-xhjt4741oh8ba`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/5863574393666669055) | Native crash within about ten seconds | Local-only: `test-results/matrix-xhjt4741oh8ba/…` |
| Scenario 9 repeat, Impeller | [`matrix-3b6g9twm1uert`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/9034638518104891031) | Native crash within about ten seconds | Local-only: `test-results/matrix-3b6g9twm1uert/…` |
| Scenario 9, Skia | [`matrix-2jf9z8kppu2qs`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.479c61bab2b69f9e/matrices/8518953339329524335) | Pass, 603 s; 2,148/2,148 probes completed | Local-only: `test-results/matrix-2jf9z8kppu2qs/…` |

### Diagnostic A/B matrix

The following rows use the same physical `starlte`/API 29 target and scenario
9 unless noted. Every row through `threadsafe=true` is a confirmed crash; the
force-rebind row records four passing Test Lab runs. Add each repeat as a new
row rather than replacing an earlier matrix.

| Variant | Matrix / status | Observation |
| --- | --- | --- |
| Baseline Impeller | [`matrix-xhjt4741oh8ba`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/5863574393666669055) | Crash in `blit_pass_gles.cc(88)` within about ten seconds; `GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT` |
| Diagnostic v1 | [`matrix-4q90hbw7tstwa`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/6687540892501608226) | Crash reproduced with EGL/FBO diagnostics; no observed `eglMakeCurrent` failure |
| Diagnostic v2 | [`matrix-1tuglrgj6zgl3`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/4683634709996739103) | `GL_INVALID_OPERATION`, FBO valid, current EGL handles present, `texture_handle_is_texture=false` |
| `threadsafe=true` texture A/B | [`matrix-22ye7y2uvt1a7`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/6601825473377377354) | Same crash and identity result; changing the decoder texture to tracked/thread-safe did not resolve it |
| force-rebind A/B (4/4) | `matrix-1npe6ectnfvy9`, `matrix-1q0hpbn2mdc09`, `matrix-2k3zkbmzzq420`, `matrix-3cd8a1yoldmf1`; verify-3 [`9163761808229023214`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/9163761808229023214) | All passed, 606 s each; 33,860/33,397/33,338/33,436 iterations and 2,148/2,148/2,149/2,148 probes; zero `GL_INVALID_OPERATION`, `ConfigureFBO failure`, `FATAL/SIGABRT`, and upload/attach `is_texture=false` observations |

The v2 and `threadsafe=true` observations narrow the failure to an invalid or
unusable texture name at the FBO attachment point, but do not distinguish a
share-group/context mismatch from texture deletion/reuse or a Mali driver
failure in texture allocation/upload. The diagnostics themselves add
failure-path GL queries and error consumption, so they are observational and
may alter timing; they are not a production fix.

### Baseline versus patched-engine A/B

Freeze the app repository at one commit (record its hash in the run notes),
then build and upload both APKs with the same Scenario 9 command. Baseline is
the stock Flutter 3.44.8/default engine and is expected to reproduce the crash.
Patched is the candidate engine from the `dfdgsdfg/flutter` fix branch/local
engine and is expected to complete; one passing matrix is evidence for the
candidate, not proof that the engine fix is generally safe.

| Variant | App commit | Engine identity | APK identity | Scenario 9 result |
| --- | --- | --- | --- | --- |
| Baseline | Same frozen app commit | Stock Flutter 3.44.8/default engine; record `engine.version` | Record APK SHA256 and ELF Build ID before upload | Expected crash; original baseline matrix is [`matrix-xhjt4741oh8ba`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/5863574393666669055) |
| Patched candidate (force-rebind) | Same frozen app commit | `dfdgsdfg/flutter` local fix branch; lib SHA256 `01d28ad2fddb687500635dfd41afc6a434d74bea81dfc246fb28d4868e39d5c0`, Build ID `c8f84ab6a8f6c69b36cce4c06fc697fef9fcd79e` | APK SHA256 `1706bb2fef328c6f31d4217de6e84b20fa8900bdc15759ce116e8afc0a745fe1` | 4/4 passed: `matrix-1npe6ectnfvy9`, `matrix-1q0hpbn2mdc09`, `matrix-2k3zkbmzzq420`, `matrix-3cd8a1yoldmf1`; verify-3 [`9163761808229023214`](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/9163761808229023214); 606 s each |

The baseline APK hash was not captured in the original evidence record; it
must be measured from the exact uploaded APK in any repeat. Do not compare
engine Build IDs alone: verify the embedded `lib/arm64-v8a/libflutter.so` hash
matches the intended engine output for both variants.

### Root-cause chronology

1. Scenario 8 (single display decode) passed on Impeller, while scenario 9
   (production-like probe decode followed by framework display decode) crashed
   twice on the same Mali target. The identical scenario passed on Skia.
2. The repeat scenario crashed without pause/resume, focus loss, or an external
   Activity. It did show same-size `SurfaceView`/EGL surface recreation shortly
   before the decoder errors, so lifecycle remains a possible amplifier rather
   than a required trigger.
3. Diagnostic v2 recorded `GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT` and a
   pending `GL_INVALID_OPERATION`. The FBO name was valid, but
   `texture_handle_is_texture=false`, the color attachment was `GL_NONE`, and
   EGL display/context/surfaces were present at the failure.
4. The `threadsafe=true` decoder A/B produced the same result. This lowers the
   likelihood that only an untracked decoder texture lifetime is responsible.
5. The force-rebind A/B clears the texture target binding immediately before
   upload, then binds the generated texture again. All four recorded runs
   passed; a production fix still requires review and broader device coverage.

Current conclusion: the double decode is a reliable trigger for this
reproducer, but the engine-level cause is not proven. Candidate causes remain
an EGL share-group/context mismatch, texture deletion/name reuse, failed
allocation/upload, or a Mali driver error/no-op during attachment.

Both Impeller scenario 9 crashes have the same fatal signature on the `1.io`
thread:

```text
GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT
[FATAL:flutter/impeller/renderer/backend/gles/blit_pass_gles.cc(88)]
Check failed: result. Must be able to encode GL commands without error.
Fatal signal 6 (SIGABRT)
```

The native stack reaches `ImageDecoderImpeller::UnsafeUploadTextureToPrivate`
through `ReactorGLES` and `BlitPassGLES`, matching the production crash stack
reported in Flutter issue [#190640](https://github.com/flutter/flutter/issues/190640).
The Skia run completed the same workload, so a generic image-memory or source
image failure is less likely.

### Lifecycle caveat and current hypothesis

The first failing run had a hotword enrollment Activity that caused the app to
pause and lose focus before the fatal error. The logs do not establish a
subsequent restore as part of the causal sequence. The repeat did not pause,
lose focus, or launch an external Activity. It did, however, show the same-size
`SurfaceView`/EGL surface recreation; decoder errors began roughly 50 ms after
that recreation. This makes lifecycle a possible trigger or amplifier, not a
required condition for the current scenario 9 failure.

The leading hypothesis is a concurrent target-size Impeller GLES upload/FBO
resource ordering or lifetime defect on Android 10 Mali. The strongest controls
are: scenario 8's single decode passes, scenario 9's double-decode workload
crashes twice on Impeller, and scenario 9 passes on Skia. The double decode is
therefore a demonstrated trigger for this reproducer, not yet proof of the
underlying engine defect.

### PR #190655 assessment

[PR #190655](https://github.com/flutter/flutter/pull/190655) is valid
hardening for an `eglMakeCurrent` failure being incorrectly treated as success,
but it addresses a different failure path in this deterministic repro. The
observed `eglMakeCurrent` calls succeed and the logs do not show
`EGL_BAD_ACCESS` or `EGL_BAD_SURFACE`; the repeat also fails without lifecycle
churn. The failing work is on the offscreen/IO context while the observed
surface recreation is onscreen. PR #190655 has not been directly tested in this
matrix and does not supersede the current FBO/texture diagnosis.

The PR is relevant only if an engine A/B run demonstrates that context failure
first. A useful acceptance check is: the unpatched engine fails 2/2; the exact
PR commit cherry-picked onto the same Flutter engine revision must complete
3–5 identical 10-minute scenario 9 runs, with no FBO fatal and with the IO
thread's `eglMakeCurrent` result recorded.

[Flutter PR #192158](https://github.com/flutter/flutter/pull/192158) is the
latest-master fix reference. The physical A/B above uses the Flutter 3.44.8
diagnostic engine; the latest-master PR result is host-validated only.
Do not interpret the diagnostic or force-rebind A/B as an implementation of
that PR; both are separate experiments.

### Previous instrumentation result

Earlier scenario 8 instrumentation failures were harness failures, not target
crashes. `UiDevice.executeShellCommand("am start -W ...")` stayed blocked until
the Test Lab timeout; the app continued emitting scenario 8 heartbeats, after
which `UiAutomation` teardown produced secondary errors. The harness now
relaunches through the instrumentation target context instead of waiting on
that blocking shell command.

### Recommended next steps

1. Preserve the four force-rebind results above and repeat on additional Mali
   models/API levels before treating the candidate as a general fix.
2. Run the exact PR #190655 engine A/B matrix using scenario 9, keeping the
   same `starlte`/API 29 device and 3–5 repeats.
3. Build a diagnostic engine and log, on the `1.io` thread, the source and
   destination FBO/texture names, `glIsTexture`, `glCheckFramebufferStatus`,
   `glGetError`, `eglGetCurrentContext`, draw surface, `eglMakeCurrent` result
   and EGL error, thread ID, and resource create/delete ordering.
4. Bisect the trigger independently: single decode vs probe+display decode,
   PNG vs JPEG/WebP, concurrency level, same-size surface recreation, and
   lifecycle pause/restore. Do not label the production double decode as the
   root cause until those controls separate the trigger from the engine bug.
5. Attach the locally downloaded scenario 8 log, both scenario 9 tombstones/logs,
   and the Skia control result when updating Flutter issue #190640. These files
   are deliberately ignored and are not links in the public repository.

## Build

For the checked-in app using a published Flutter SDK, run:

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --profile --flavor impeller
flutter build apk --profile --flavor skia
flutter build apk --release --flavor impeller
flutter build apk --release --flavor skia
```

For an engine experiment, set `FLUTTER_ROOT` to the desired Flutter checkout
and use the engine output names explicitly so the APK cannot silently fall
back to a cached engine. The force-rebind A/B used this command from the app
root:

```sh
export FLUTTER_ROOT=/path/to/dfdgsdfg/flutter
"$FLUTTER_ROOT/bin/flutter" build apk \
  --profile --flavor impeller \
  --local-engine android_profile_arm64_mali_diag \
  --local-engine-host host_profile_arm64_mali_diag \
  --local-engine-src-path "$FLUTTER_ROOT/engine/src"
```

The expected APK package is
`dev.flutter.repro.mali_crash_app.impeller`; verify its embedded
`lib/arm64-v8a/libflutter.so` hash and ELF Build ID against the engine output
before uploading it to Test Lab. Diagnostic APKs are preserved locally under
`build/mali-diagnostics/` and are not source-controlled.

Artifacts:

- `build/app/outputs/flutter-apk/app-impeller-profile.apk` — forced OpenGLES
- `build/app/outputs/flutter-apk/app-skia-profile.apk` — Skia profile control
- `build/app/outputs/flutter-apk/app-impeller-release.apk`
- `build/app/outputs/flutter-apk/app-skia-release.apk`

Flutter 3.44.8 only honors an explicitly requested Impeller backend in debug or
profile mode. Release mode auto-selects the backend, so the profile APK is the
deterministic GLES reproducer while the Impeller release APK remains the
production-mode control.

## Firebase Test Lab

The affected-device target is the physical Samsung Galaxy S9 (`starlte`),
Android 10/API 29. Start with scenario 3, then scenario 5. Use scenario 6 with
the external lifecycle instrumentation harness below. The Skia flavor is a
negative renderer control. Change `--timeout` to `12m` for scenarios 5, 6, 7,
8, or 9. Scenario 8 or 9 can be selected with
`--environment-variables=scenario=8` (or `scenario=9`) when using the
instrumentation APK below.

```sh
GCP_PROJECT=YOUR_GCP_PROJECT_ID
gcloud firebase test android run \
  --project="$GCP_PROJECT" \
  --type=game-loop \
  --app=build/app/outputs/flutter-apk/app-impeller-profile.apk \
  --device=model=starlte,version=29,locale=ko_KR,orientation=portrait \
  --scenario-numbers=3 \
  --timeout=5m \
  --record-video \
  --performance-metrics \
  --client-details=matrixLabel=impeller-gles-mali-3.44.8
```

The exact scenario 9 command is:

```sh
GCP_PROJECT=YOUR_GCP_PROJECT_ID
gcloud firebase test android run \
  --project="$GCP_PROJECT" \
  --type=game-loop \
  --app=build/app/outputs/flutter-apk/app-impeller-profile.apk \
  --device=model=starlte,version=29,locale=ko_KR,orientation=portrait \
  --scenario-numbers=9 \
  --timeout=12m \
  --record-video \
  --performance-metrics \
  --client-details=matrixLabel=impeller-gles-mali-3.44.8-scenario-9
```

For the external lifecycle instrumentation APK, add
`--test-targets="class dev.flutter.repro.mali_crash_app.MaliStressInstrumentationTest"`
and pass `--environment-variables=scenario=6` (or `scenario=9`) as required by
the harness. Do not use the instrumentation harness to claim a pure scenario 9
result unless its lifecycle cycles and the app's Test Loop result are both
recorded.

Physical-device tests consume Test Lab quota and may incur billing. Repeat the
same command with the Impeller release and Skia release APKs for control runs.

## Local lifecycle instrumentation

The profile test APK contains an external lifecycle harness. It starts scenario
6 (or the supplied `scenario` argument) through the existing `TEST_LOOP` action,
detects the target flavor package automatically, then uses UiAutomator to
alternate left/natural rotation, press Home, relaunch `MainActivity` through
the instrumentation target context, and verify the app package is foreground.
It performs 30 cycles and fails if the app publishes a Test Loop result during
the run; the captured JSON is included in the failure. It does not call the
app's internal `cycleTask` channel.

Build the test APK (a connected device is not required):

```sh
./android/gradlew -p android :app:assembleImpellerProfileAndroidTest
```

Run it only with an explicitly connected Android device or emulator:

```sh
./android/gradlew -p android :app:connectedImpellerProfileAndroidTest
```
