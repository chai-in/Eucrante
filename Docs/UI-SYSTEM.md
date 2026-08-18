# UI system

## Experience direction

The interface should feel like a focused macOS utility: calm, compact, and immediately legible. It uses platform materials and controls with a restrained cobalt-blue accent, not a visual clone of the website.

## Information architecture

```text
Main window
├── Save
│   ├── Source URL
│   ├── Music: Best / Efficient
│   ├── Video: Best / Efficient
│   ├── Custom mode: Auto / Audio / Mute
│   └── Save action
├── Queue
│   ├── Active
│   └── Completed this session
└── History (Phase 1)

Settings window
├── General
├── Video
├── Audio
├── Metadata
├── Processing
└── Privacy
```

The main window opens at roughly 820 x 560 points and supports resizing down to 680 x 460. A sidebar is appropriate once queue/history are persistent; the current scaffold uses a compact split view without forcing empty navigation.

## Save screen wireframe

```text
┌──────────────────────────────────────────────────────────────────┐
│  Eucrante                                         [Queue 2] [⚙] │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│             Save something you love                              │
│             Public links only. Your files stay on this Mac.      │
│                                                                  │
│   ┌──────────────────────────────────────────────────────────┐   │
│   │ https://…                                           [×]  │   │
│   └──────────────────────────────────────────────────────────┘   │
│                                                                  │
│   Music       [ Best ] [ Efficient ]                             │
│   Video       [ Best ] [ Efficient ]                             │
│                                                                  │
│   [ Custom options… ]                                            │
│                                                                  │
│   Choosing a preset starts the save when the URL is valid.       │
│                                                                  │
│   Destination  Downloads/Eucrante                 [Choose…]     │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

When a URL is submitted, the central card remains in place and communicates `Resolving`, `Downloading`, or `Processing`. Starting another save clears the field after the job has been accepted, not before. The queue remains available without stealing focus.

Each preset button includes a short secondary label: `Original/ALAC`, `AAC 256`, `Preserve/HEVC`, or `Smaller HEVC`. Advanced controls are disclosed behind **Custom options**. Changing one relabels the selection as **Custom** so the interface never claims that a modified job still follows a named preset.

Completed Music jobs show **Import to Music** only after output verification. Import does not run automatically and its first use explains the macOS Automation permission before triggering the system prompt.

## Queue wireframe

```text
┌──────────────────────────────────────────────────────────────────┐
│ Queue                                                 [Clear]     │
├──────────────────────────────────────────────────────────────────┤
│ [▶] Video title.mp4       Downloading  62%        [Cancel]       │
│     example.com · 18.4 MB of 29.7 MB                            │
├──────────────────────────────────────────────────────────────────┤
│ [✓] Track title.mp3       Saved                  [Show in Finder] │
│     Downloads/Eucrante · just now                               │
├──────────────────────────────────────────────────────────────────┤
│ [!] Another item           API rate limit        [Retry]         │
│     Try again in 38 seconds                                      │
└──────────────────────────────────────────────────────────────────┘
```

Rows expose only relevant actions. Errors state what happened and what the user can do. Destructive removal is secondary and never conflated with cancel.

## Gallery picker

Use a resizable sheet with a thumbnail grid, selection count, Select All, and `Save Selected`. Keyboard focus moves through items in reading order; Space toggles selection. Broken thumbnails retain the media type and sequence number.

## Visual tokens

### Color

- Accent: semantic `Color.accentColor`, default cobalt blue approximately `#2962D9` in light mode and a brighter accessible variant in dark mode.
- Surfaces: macOS window and material backgrounds; avoid opaque card stacks.
- Success, warning, and error: system semantic colors, always paired with icon/text.
- Never use color as the sole status signal.

### Type

- System font throughout.
- Large title: 28 pt semibold.
- Section title: 17 pt semibold.
- Body: platform body style.
- Metadata: platform subheadline/secondary.
- Monospaced digits for byte counts, rates, and durations only.

### Shape and spacing

- 8 pt base spacing grid.
- 12 pt control/card radius; capsule only for status or mode selector.
- Content margins: 24 pt compact, 32 pt regular.
- Minimum interactive target: 28 x 28 pt on macOS; primary actions use at least 36 pt height.

### Motion

- Short opacity/position transitions under 200 ms.
- Indeterminate progress uses the system control.
- Respect Reduce Motion and Reduce Transparency; never animate decorative backgrounds.

## Native behaviors

- `Command-V` pastes into the URL field; the app never reads the clipboard preemptively.
- `Command-Return` submits a valid URL.
- `Command-,` opens Settings.
- `Command-1/2/3` selects Save/Queue/History when all sections exist.
- Dragged URL text is accepted; dragged files are reserved for Remux in Phase 2.
- Completed rows support Space for Quick Look and `Command-R` to reveal in Finder when focused.
- Main commands are mirrored in the menu bar and expose keyboard shortcuts to VoiceOver.

## Accessibility checklist

- Logical focus order and a visible focus ring.
- Every icon-only action has a label and help text.
- Progress announces coarse milestones, not every percentage change.
- Dynamic text accommodates accessibility sizes without clipping settings rows.
- Thumbnails have media-type descriptions; decorative art is hidden.
- Error summaries receive focus once and do not trap it.
- High-contrast and Increase Contrast modes retain boundaries.

## Empty and error states

- Unconfigured endpoint: show a single `Open Processing Settings` action and explain why an instance is required.
- Empty queue: friendly one-line message; no illustration dependency.
- Offline: preserve the URL and offer Retry.
- Authentication required: link directly to the API-key Settings field.
- Rate-limited: show countdown when headers provide a reset time.
- Unsupported URL: name the unsupported host without echoing sensitive path/query data.

## Copy voice

Use short, specific sentences. Prefer “Couldn’t reach your Cobalt instance” over “Unknown network error.” Avoid jokes during failure and avoid claiming a download is complete until the final move succeeds.
