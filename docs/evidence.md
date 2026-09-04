# Reviewable crash evidence

This page is a self-contained summary of the evidence for [Flutter issue
#190640](https://github.com/flutter/flutter/issues/190640). It was transcribed
from the ignored Test Lab downloads for the matrix labels shown below. Raw
logcat, tombstones, result JSON, videos, APKs, and engine binaries are not
published.

Firebase Console links are supplemental and may require access to the original
project. The excerpts and tables on this page are the evidence that can be
reviewed without that access. The logical texture handles and GL names are
kept; process IDs, thread IDs, EGL pointers, package-install paths, and other
device/project identifiers are redacted.

## Failing native signature

Source: `matrix-35ssuhjaua920`, Scenario 9, Impeller/OpenGLES, `starlte` API 29.
The tombstone's `libflutter.so` frames were not symbolized beyond the abort
frame; its Build ID matches the diagnostic engine recorded in the README.

```text
signal 6 (SIGABRT), code -1 (SI_QUEUE), fault addr --------
Abort message: '[FATAL:flutter/impeller/renderer/backend/gles/blit_pass_gles.cc(88)] Check failed: result. Must be able to encode GL commands without error.
backtrace:
      #00 pc <redacted> libc.so (abort+176)
      #01 pc <redacted> libflutter.so (BuildId: 70da53eae777f09ee57b5e0d7c47172d2703503b)
      #02 pc <redacted> libflutter.so (BuildId: 70da53eae777f09ee57b5e0d7c47172d2703503b)
```

The preceding diagnostic line is also explicit:

```text
Break on 'ImpellerValidationBreak' to inspect point of failure: Could not create a complete framebuffer: GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT
[FATAL:flutter/impeller/renderer/backend/gles/blit_pass_gles.cc(88)] Check failed: result. Must be able to encode GL commands without error.
Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE)
```

## Failing GL chronology

The following is a short exact excerpt, with only the log prefix, raw thread
or EGL identity, and process metadata replaced by `<redacted>`. It follows
the same GL name (`7`) across the old texture, deletion, regeneration, upload,
and attachment. The old initialization and deletion occur on distinct
rendering contexts in the source trace; their raw identities are intentionally
not published.

```text
TextureTrace stage=initialize.bind logical_handle=209 gl_name=7 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=initialize.tex_image_2d logical_handle=209 gl_name=7 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=attachment.framebuffer_texture_2d.after logical_handle=209 gl_name=7 target=36009 textarget=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=texture.delete.before logical_handle=209 gl_name=7 thread=<redacted> raw_error_group=pre_delete raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=texture.delete.after logical_handle=209 gl_name=7 thread=<redacted> raw_error_group=delete raw_error=GL_NO_ERROR(0) is_texture=false raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=texture.generated logical_handle=unassigned gl_name=7 thread=<redacted> note=glIsTexture_may_be_false_before_first_bind
TextureTrace stage=upload.tex_sub_image_2d logical_handle=215 gl_name=7 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=false raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=attachment.framebuffer_texture_2d.after logical_handle=215 gl_name=7 target=36008 textarget=3553 thread=<redacted> raw_error_group=operation raw_error=GL_INVALID_OPERATION(1282) is_texture=false raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
ConfigureFBO failure role=read/source target=36008 reason=framebuffer incomplete fbo=1 texture_handle=7 type=texture wrapped=false descriptor=1280x720 descriptor.type=Texture2D descriptor.textarget=3553 format=R8G8B8A8UNormInt usage={ ShaderRead }
ConfigureFBO role=read/source fbo=1 status=GL_FRAMEBUFFER_INCOMPLETE_MISSING_ATTACHMENT
ConfigureFBO role=read/source fbo=1 texture_handle_is_texture=false
ConfigureFBO role=read/source fbo=1 color_attachment_type=none name=0
```

Thus the upload itself reports `GL_NO_ERROR`, but the post-operation identity
query is false; the subsequent `FramebufferTexture2D` reports
`GL_INVALID_OPERATION`, leaving the read FBO with no color attachment. This is
consistent with a texture-name/context lifetime or driver failure, but does
not by itself prove which layer is at fault.

## Passing force-rebind comparison

Source: `matrix-1npe6ectnfvy9`, the first force-rebind A/B pass. The generated
name is observed before its first bind (`glIsTexture` may be false), then the
force-rebind path makes the upload and attachment valid. These are exact trace
fields with thread/EGL metadata redacted.

```text
TextureTrace stage=texture.generated logical_handle=unassigned gl_name=2 thread=<redacted> note=glIsTexture_may_be_false_before_first_bind
TextureTrace stage=initialize.bind logical_handle=76 gl_name=2 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=initialize.tex_image_2d logical_handle=76 gl_name=2 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=attachment.framebuffer_texture_2d_multisample.after logical_handle=76 gl_name=2 target=36160 textarget=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
```

The same pass also records the production-like upload successfully:

```text
TextureTrace stage=texture.generated logical_handle=unassigned gl_name=1 thread=<redacted> note=glIsTexture_may_be_false_before_first_bind
TextureTrace stage=upload.tex_sub_image_2d logical_handle=5 gl_name=1 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
```

## Four-run result summary

All four force-rebind runs used Scenario 9 on the same `starlte` API 29 target,
ran for 606 seconds, and completed successfully. “Probes” is
`feedResizeProbeRequests/feedResizeProbeCompletions` from each local result
JSON. The error columns are counts from the corresponding diagnostic logs.

| Matrix label | Duration | Iterations | Probes | GL_INVALID_OPERATION | ConfigureFBO failure | FATAL/SIGABRT | upload/attach `is_texture=false` |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `matrix-1npe6ectnfvy9` | 606 s | 33,860 | 2,148/2,148 | 0 | 0 | 0 | 0 |
| `matrix-1q0hpbn2mdc09` | 606 s | 33,397 | 2,148/2,148 | 0 | 0 | 0 | 0 |
| `matrix-2k3zkbmzzq420` | 606 s | 33,338 | 2,149/2,149 | 0 | 0 | 0 | 0 |
| `matrix-3cd8a1yoldmf1` | 606 s | 33,436 | 2,148/2,148 | 0 | 0 | 0 | 0 |

The candidate APK used for these runs had SHA-256
`1706bb2fef328c6f31d4217de6e84b20fa8900bdc15759ce116e8afc0a745fe1` and
embedded `libflutter.so` SHA-256
`01d28ad2fddb687500635dfd41afc6a434d74bea81dfc246fb28d4868e39d5c0`, with
Build ID `c8f84ab6a8f6c69b36cce4c06fc697fef9fcd79e`.

## Reviewer cleanup-only A/B result

Source: `matrix-3j7vwwd2v8nhk`, Scenario 9, same `starlte` API 29 target. This
conditional run was stopped after the first result: 0/1, with the crash at
about 5.13 seconds around iteration 70. No additional runs were scheduled.

| Variant | APK / engine identity | Result |
| --- | --- | --- |
| reviewer cleanup-only | APK `4c88b3079ab14b63648d6e7bacec4dacff5ea4c9d5344ef13af651648bed93b7`; embedded `libflutter.so` `25e5b07e49f13e3d7b8ae2c1332d604a3de4607ef3ea381e6651d4f81761d242`; Build ID `39203d181598b9f4f39e41dedc270110eaeba276` | 0/1; SIGABRT in `blit_pass_gles.cc(88)` |

This variant intentionally has no pre-bind mitigation. Its only cleanup is a
post-use `BindTexture(target, 0)` scoped cleanup in
`BlitCopyBufferToTextureCommandGLES::Encode` and
`TextureGLES::OnSetContents`.

The sanitized excerpt below preserves the logical handles, GL name, error
values, and source stages. Thread/process/EGL metadata is replaced with
`<redacted>`.

```text
TextureTrace stage=initialize.bind logical_handle=311 gl_name=8 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=initialize.tex_image_2d logical_handle=311 gl_name=8 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=attachment.framebuffer_texture_2d.after logical_handle=311 gl_name=8 target=36009 textarget=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=texture.delete.before logical_handle=311 gl_name=8 thread=<redacted> raw_error_group=pre_delete raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=texture.delete.after logical_handle=311 gl_name=8 thread=<redacted> raw_error_group=delete raw_error=GL_NO_ERROR(0) is_texture=false raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=texture.generated logical_handle=unassigned gl_name=8 thread=<redacted> note=glIsTexture_may_be_false_before_first_bind
TextureTrace stage=upload.tex_sub_image_2d logical_handle=315 gl_name=8 target=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=false raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
TextureTrace stage=attachment.framebuffer_texture_2d.before logical_handle=315 gl_name=8 target=36008 textarget=3553 thread=<redacted> raw_error_group=pre_operation raw_error=GL_INVALID_OPERATION(1282)
TextureTrace stage=attachment.framebuffer_texture_2d.after logical_handle=315 gl_name=8 target=36008 textarget=3553 thread=<redacted> raw_error_group=operation raw_error=GL_NO_ERROR(0) is_texture=true raw_error_group=is_texture_query raw_error=GL_NO_ERROR(0)
ConfigureFBO failure role=read/source target=36008 reason=framebuffer incomplete fbo=1 texture_handle=8 type=texture wrapped=false descriptor=1280x720 descriptor.type=Texture2D descriptor.textarget=3553 format=R8G8B8A8UNormInt usage={ ShaderRead }
ConfigureFBO role=read/source fbo=1 status=GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT
ConfigureFBO role=read/source fbo=1 texture_handle_is_texture=true
ConfigureFBO role=read/source fbo=1 color_attachment_type=texture name=8
```

The `logical_handle=311` initialization path predates and bypasses both
cleanup sites. After that texture is deleted on a shared context, the same GL
name is regenerated for logical handle 315. The new upload reports
`GL_NO_ERROR` while its identity query is false; the pending error is then
observed before the next attachment call, which fails framebuffer completeness.
The post-use cleanup runs after that upload/materialization attempt and cannot
repair the already-invalid attachment. The exact Mali driver/context mechanism
remains an inference, not a proven internal cause.

This single failure contrasts with the current force-rebind result of 4/4
runs passing for 606 seconds each. Both results are diagnostic experiments on
one device/driver/API combination; instrumentation can affect timing, and the
cleanup-only result is not evidence of a general regression rate.

## Interpretation and limits

The evidence supports this narrow statement: on this Mali target, the
production-like probe-plus-display double decode reliably exposes an
Impeller/OpenGLES texture identity failure at framebuffer attachment, while
the force-rebind candidate passed four repeated runs. It does not distinguish
an EGL share-group/context mismatch, deletion/name reuse, failed allocation or
upload, or a Mali driver defect. The diagnostic queries themselves can affect
timing, and the result is from one device/driver/API combination. Broader
device coverage and an engine A/B with the proposed Flutter fix are still
required.

The server-side matrix page for verify-3 is available at [Firebase Test Lab
matrix 9163761808229023214](https://console.firebase.google.com/project/us-app-ea67d/testlab/histories/bh.d17e9c8f630d19e0/matrices/9163761808229023214),
subject to project permissions. The physical A/B engine details and the
reproduction/build commands are maintained in the [main README](../README.md).
