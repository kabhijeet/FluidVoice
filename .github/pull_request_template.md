## Description
Adds a new text insertion mode setting near Copy to Clipboard and makes Reliable Paste the default for more dependable dictation insertion across browsers and desktop apps. This keeps an Experimental Direct Typing option for users who want to try to avoid clipboard changes.

## Type of Change
- [x] 🐞 Bug fix (non-breaking change which fixes an issue)
- [x] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📝 Documentation update

## Related Issues
- Closes #174
- Closes #125
- Related to #74

## Testing
- [ ] Tested on Intel Mac
- [x] Tested on Apple Silicon Mac
- [x] Tested on macOS 15.x
- [x] Ran linter locally: `swiftlint --strict --config .swiftlint.yml Sources`
- [x] Ran formatter locally: `swiftformat --config .swiftformat Sources`
- [x] Built locally: `sh build_incremental.sh`

## Notes
- `Reliable Paste` is now the default because it worked more consistently in real app testing.
- `Experimental Direct Typing` remains available for users who want to try to avoid clipboard changes, but it may still behave inconsistently in some apps.

## Screenshots / Video 
Add screenshots or Video recording of the app after you have made your changes 
