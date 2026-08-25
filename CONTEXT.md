# SSSubtitle

SSSubtitle helps a person find, inspect, and acquire an external subtitle that belongs with a video they possess, without uploading the video itself.

## Language

**Video Profile**:
The local identity and descriptive metadata of the video for which a subtitle is wanted. It may contain a content identifier, a suggested search name, size, and duration.
_Avoid_: Video record, media item

**Suggested Search Name**:
The editable name derived from the video's filename and proposed as the initial subtitle query.
_Avoid_: Keyword, parsed title

**Subtitle Candidate**:
A normalized subtitle option returned by a Subtitle Provider and not yet acquired by the user.
_Avoid_: Result, item, remote subtitle

**Match Score**:
The comparable measure of how likely a Subtitle Candidate belongs to the current Video Profile, accompanied by human-readable Match Reasons.
_Avoid_: Quality, confidence

**Subtitle Preview**:
A decoded, paginated view of a Subtitle Candidate's textual content before acquisition.
_Avoid_: Snippet, sample

**Subtitle Artifact**:
Validated subtitle content ready to be saved, exported, shared, or downloaded on the current platform.
_Avoid_: File, download

**Subtitle Provider**:
An external service that supplies Subtitle Candidates and their content.
_Avoid_: API, source, plugin

**Acquisition**:
The user-confirmed act of obtaining a Subtitle Artifact and handing it to the current platform's save or export flow.
_Avoid_: Install, sync
