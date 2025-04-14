@MainActor private var lastKnownNativeFocusedWindowId: UInt32? = nil

/// The data should flow (from nativeFocused to focused) and
///                      (from nativeFocused to lastKnownNativeFocusedWindowId)
/// Alternative names: takeFocusFromMacOs, syncFocusFromMacOs
@MainActor func updateFocusCache(_ nativeFocused: Window?) {
    print("""
    updateFocusCache() called with:
    - nativeFocused: \(nativeFocused.debugDescription)
    - lastKnownNativeFocusedWindowId: \(lastKnownNativeFocusedWindowId ?? 0)
    """)

    if nativeFocused?.windowId != lastKnownNativeFocusedWindowId {
        print("updateFocusCache() window focus changed - attempting to focus window \(nativeFocused?.windowId ?? 0)")
        let result = nativeFocused?.focusWindow() ?? false
        print("updateFocusCache() focus result: \(result)")
        lastKnownNativeFocusedWindowId = nativeFocused?.windowId
        print("updateFocusCache() updated lastKnownNativeFocusedWindowId to \(lastKnownNativeFocusedWindowId ?? 0)")
    } else {
        print("updateFocusCache() no focus change needed (window IDs match)")
    }
}
