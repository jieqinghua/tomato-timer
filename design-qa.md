# Tomato Timer v2.0 Design QA

## Source

- Layout reference: `resources/IMG_20260702_210409.jpg`
- Product specification: `docs/v2.0-product-plan.md`
- Rendered viewport: 320 x 500 pt macOS menu bar popover

## Checks

- `专注 / 统计 / 设置` use one stable three-segment tab control.
- The focus tab presents only the prompt, three supplied tomato mood assets, selected duration, and timer controls without overlap.
- The default `还可以 / 15 分钟` state is visually emphasized and can start in one action.
- The selected mood image renders at 125% of the unselected images; only its `专注 xx 分钟` label is visible.
- The primary button text fits at the target width and its height matches the two icon controls.
- Removing duration controls leaves balanced vertical space between readiness and timer actions.
- Start confirmation and phase transitions do not resize the control area.
- Paused and rest states use supportive, non-judgmental language.
- Main controls expose explicit VoiceOver labels, values, and hints.
- Keyboard shortcuts cover tabs, mood selection, timer control, reset, and skip.
- The stats tab preserves the three v1 metrics without adding dashboard clutter.
- The settings tab contains break duration, automatic next-focus control, notification, recording preferences, and all recording status feedback; recording directories remain accessible when recording is disabled.
- `退出番茄时钟` stays outside the tab content in a fixed footer.
- Light-mode offscreen snapshots render the focus, running focus, stats, settings, and running settings states through `testTabsRenderForVisualQA`.
- A dark-mode focus snapshot verifies text, selection, action, card, and footer contrast.

## Remaining Notes

- Native segmented controls are layer-backed, so intermediate offscreen tab captures may omit unchanged native layers; the test separately asserts that the control contains all three segments.
- A live menu bar capture was unavailable because terminal accessibility permission is disabled. Functional builds and app-scoped offscreen renders passed.

final result: passed
