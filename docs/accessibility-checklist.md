# Accessibility Checklist

## Required behaviors

- Keyboard navigation for visible controls where practical.
- No keyboard traps.
- Visible focus state.
- Screen-reader labels where platform APIs support them.
- Tooltips or labels for icon-like controls.
- Sufficient text contrast.
- High contrast theme in later phase.
- Text remains readable at larger font sizes.
- Selected and active panel states are visible.
- Errors use icons plus text; never color alone.
- Comfortable Mode uses large enough click targets.
- Reduce motion option if animations are added.

## macOS prototype accessibility strategy

- Use native `NSButton`, `NSTextField`, `NSTextView`, `NSScrollView`, `NSMenu`, `NSOpenPanel`, and `NSSavePanel` for the first vertical slice.
- Prefer native text editing initially to inherit selection, keyboard editing, accessibility roles, and IME behavior.
- Add explicit accessibility labels for custom sidebar/status controls when they become custom views.

## Review questions

1. Can the app be used without a mouse for common actions?
2. Can the user see focus?
3. Can the user increase font size and still read/edit?
4. Are destructive actions confirmed?
5. Are errors understandable without color?
6. Does the current screen identify where the user is?
