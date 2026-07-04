import CoreBluetooth
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentHeaderView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appTheme) private var theme
    @ThemedPalette private var palette

    @Binding var showSidebar: Bool
    @Binding var showVerifySheet: Bool
    @Binding var showLocationNotes: Bool
    @Binding var notesGeohash: String?
    var isNicknameFieldFocused: FocusState<Bool>.Binding

    // Panic-wipe arming: the first triple-tap arms (red "tap again to wipe"
    // for a short window), the next tap executes. Keeps the duress feature
    // fast while making an accidental triple-tap recoverable.
    @State private var panicArmed = false
    @State private var showWipedNotice = false
    @State private var panicStateResetTask: Task<Void, Never>?

    let headerHeight: CGFloat
    let headerPeerIconSize: CGFloat
    let headerPeerCountFontSize: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            headerRow

            if showsBluetoothStatusRow {
                bluetoothStatusRow
            }
        }
        .sheet(isPresented: $appChromeModel.isLocationChannelsSheetPresented) {
            LocationChannelsSheet(isPresented: $appChromeModel.isLocationChannelsSheetPresented)
                .environmentObject(locationChannelsModel)
                .environmentObject(peerListModel)
        }
        .sheet(isPresented: $showLocationNotes, onDismiss: {
            notesGeohash = nil
        }) {
            locationNotesSheetContent
        }
        .onAppear {
            locationChannelsModel.refreshMeshChannelsIfNeeded()
        }
        .onChange(of: locationChannelsModel.selectedChannel) { _ in
            locationChannelsModel.refreshMeshChannelsIfNeeded()
        }
        .onChange(of: locationChannelsModel.permissionState) { _ in
            locationChannelsModel.refreshMeshChannelsIfNeeded()
        }
        .alert("content.alert.screenshot.title", isPresented: $appChromeModel.showScreenshotPrivacyWarning) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("content.alert.screenshot.message")
        }
        .themedChromePanel(edge: .top)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Text(verbatim: logoTitle)
                    .bitchatFont(size: 18, weight: .medium)
                    .lineLimit(1)
                    .foregroundColor(panicArmed || showWipedNotice ? palette.alertRed : palette.primary)

                // Visible cue that the logo is tappable — it is the only
                // entry to the help sheet, and a bare wordmark reads as
                // static branding.
                if !panicArmed && !showWipedNotice {
                    Image(systemName: "info.circle")
                        .font(.bitchatSystem(size: 11))
                        .foregroundColor(palette.secondary.opacity(0.7))
                        .accessibilityHidden(true)
                }
            }
                .contentShape(Rectangle())
                .onTapGesture(count: 3) {
                    handlePanicGesture()
                }
                .onTapGesture(count: 1) {
                    if panicArmed {
                        executePanicWipe()
                    } else {
                        appChromeModel.presentAppInfo()
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(logoAccessibilityLabel)
                .accessibilityAction(named: Text("content.accessibility.panic_wipe", comment: "Name of the accessibility action that arms and executes the panic wipe")) {
                    handlePanicGesture()
                }
                .onDisappear {
                    // Disarm rather than latch: if a cover (image picker, sheet)
                    // hides the header mid-window, the cancelled reset task must
                    // not leave the armed state waiting for a stray tap.
                    panicStateResetTask?.cancel()
                    panicStateResetTask = nil
                    panicArmed = false
                    showWipedNotice = false
                }

            HStack(spacing: 0) {
                Text(verbatim: "@")
                    .bitchatFont(size: 14)
                    .foregroundColor(palette.secondary)

                TextField(
                    "content.input.nickname_placeholder",
                    text: Binding(
                        get: { appChromeModel.nickname },
                        set: { appChromeModel.setNickname($0) }
                    )
                )
                .textFieldStyle(.plain)
                .bitchatFont(size: 14)
                .frame(maxWidth: 80)
                .foregroundColor(palette.primary)
                .focused(isNicknameFieldFocused)
                .autocorrectionDisabled(true)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .modifier(FocusEffectDisabledModifier())
                .onChange(of: isNicknameFieldFocused.wrappedValue) { isFocused in
                    if !isFocused {
                        appChromeModel.validateAndSaveNickname()
                    }
                }
                .onSubmit {
                    appChromeModel.validateAndSaveNickname()
                }
            }

            Spacer()

            let countAndColor = channelPeopleCountAndColor()
            let headerCountColor = countAndColor.1
            let headerOtherPeersCount: Int = {
                if case .location = locationChannelsModel.selectedChannel {
                    return peerListModel.visibleGeohashPeerCount
                }
                return countAndColor.0
            }()

            HStack(spacing: 2) {
                if appChromeModel.hasUnreadPrivateMessages {
                    Button(action: { appChromeModel.openMostRelevantPrivateChat() }) {
                        Image(systemName: "envelope.fill")
                            .font(.bitchatSystem(size: 12))
                            .foregroundColor(Color.orange)
                            .headerTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "content.accessibility.open_unread_private_chat", comment: "Accessibility label for the unread private chat button")
                    )
                }

                if case .mesh = locationChannelsModel.selectedChannel,
                   locationChannelsModel.permissionState == .authorized {
                    Button(action: {
                        locationChannelsModel.enableAndRefresh()
                        notesGeohash = locationChannelsModel.currentBuildingGeohash
                        showLocationNotes = true
                    }) {
                        Image(systemName: "note.text")
                            .font(.bitchatSystem(size: 12))
                            .foregroundColor(Color.orange.opacity(0.8))
                            .headerTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "content.accessibility.location_notes", comment: "Accessibility label for location notes button")
                    )
                }

                if case .location(let channel) = locationChannelsModel.selectedChannel {
                    Button(action: { locationChannelsModel.toggleBookmark(channel.geohash) }) {
                        Image(systemName: locationChannelsModel.isBookmarked(channel.geohash) ? "bookmark.fill" : "bookmark")
                            .font(.bitchatSystem(size: 12))
                            .headerTapTarget()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(
                            format: String(localized: "content.accessibility.toggle_bookmark", comment: "Accessibility label for toggling a geohash bookmark"),
                            locale: .current,
                            channel.geohash
                        )
                    )
                }

                Button(action: { appChromeModel.isLocationChannelsSheetPresented = true }) {
                    let badgeText: String = {
                        switch locationChannelsModel.selectedChannel {
                        case .mesh: return "#mesh"
                        case .location(let channel): return "#\(channel.geohash)"
                        }
                    }()
                    let badgeColor: Color = {
                        switch locationChannelsModel.selectedChannel {
                        case .mesh:
                            return Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
                        case .location:
                            return palette.locationAccent
                        }
                    }()

                    Text(badgeText)
                        .bitchatFont(size: 14)
                        .foregroundColor(badgeColor)
                        .lineLimit(headerLineLimit)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                        .padding(.horizontal, 6)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .accessibilityLabel(
                            String(localized: "content.accessibility.location_channels", comment: "Accessibility label for the location channels button")
                        )
                }
                .buttonStyle(.plain)

                Button(action: {
                    withAnimation(.easeInOut(duration: TransportConfig.uiAnimationMediumSeconds)) {
                        showSidebar.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: headerPeerIconSize, weight: .regular))
                        Text("\(headerOtherPeersCount)")
                            .font(.system(size: headerPeerCountFontSize, weight: .regular, design: theme.bodyFontDesign))
                            .accessibilityHidden(true)
                    }
                    .foregroundColor(headerCountColor)
                    .lineLimit(headerLineLimit)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.leading, 6)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    String(
                        format: String(localized: "content.accessibility.people_count", comment: "Accessibility label announcing number of people in header"),
                        locale: .current,
                        headerOtherPeersCount
                    )
                )
            }
            .layoutPriority(3)
            .sheet(isPresented: $showVerifySheet) {
                VerificationSheetView(isPresented: $showVerifySheet)
                    .environmentObject(verificationModel)
            }
        }
        .frame(height: headerHeight)
        .padding(.horizontal, 12)
    }

    private var locationNotesSheetContent: some View {
        Group {
            if let geohash = notesGeohash ?? locationChannelsModel.currentBuildingGeohash {
                LocationNotesView(
                    geohash: geohash,
                    senderNickname: appChromeModel.nickname
                )
                .environmentObject(locationChannelsModel)
            } else {
                ContentLocationNotesUnavailableView(
                    showLocationNotes: $showLocationNotes,
                    headerHeight: headerHeight
                )
                .environmentObject(locationChannelsModel)
            }
        }
        .onAppear {
            locationChannelsModel.enableLocationChannels()
            locationChannelsModel.beginLiveRefresh()
        }
        .onDisappear {
            locationChannelsModel.endLiveRefresh()
        }
        .onChange(of: locationChannelsModel.availableChannels) { channels in
            if let current = channels.first(where: { $0.level == .building })?.geohash,
               notesGeohash != current {
                notesGeohash = current
                #if os(iOS)
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.prepare()
                generator.impactOccurred()
                #endif
            }
        }
    }
}

private extension View {
    /// Expands a small header icon to a comfortably tappable, full-bar-height
    /// hit area without changing its visual size.
    func headerTapTarget() -> some View {
        frame(minWidth: 30, maxHeight: .infinity)
            .contentShape(Rectangle())
    }
}

private extension ContentHeaderView {
    var headerLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? 2 : 1
    }

    /// Persistent "mesh is down" indicator: shown while #mesh is selected
    /// and Bluetooth is in a lasting bad state. The one-shot alert stays as
    /// the recovery prompt; this row is the durable trace it leaves behind.
    var showsBluetoothStatusRow: Bool {
        guard case .mesh = locationChannelsModel.selectedChannel else { return false }
        switch appChromeModel.bluetoothState {
        case .poweredOff, .unauthorized, .unsupported:
            return true
        default:
            // .unknown/.resetting are transient startup states; flagging
            // them would flash a false "offline" on every launch.
            return false
        }
    }

    var bluetoothStatusText: String {
        switch appChromeModel.bluetoothState {
        case .unauthorized:
            return String(localized: "content.status.bluetooth_unauthorized", comment: "Persistent header status row shown while Bluetooth permission is denied")
        case .unsupported:
            return String(localized: "content.status.bluetooth_unsupported", comment: "Persistent header status row shown when the device has no Bluetooth support")
        default:
            return String(localized: "content.status.bluetooth_off", comment: "Persistent header status row shown while Bluetooth is turned off")
        }
    }

    var bluetoothStatusRow: some View {
        Button(action: { SystemSettings.bluetooth.open() }) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.bitchatSystem(size: 11))
                Text(verbatim: bluetoothStatusText)
                    .bitchatFont(size: 12)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .foregroundColor(palette.alertRed)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.alertRed.opacity(0.12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(bluetoothStatusText)
    }

    var logoTitle: String {
        if panicArmed {
            return String(localized: "content.header.panic_armed", comment: "Header text shown while the panic wipe is armed and awaiting a confirming tap")
        }
        if showWipedNotice {
            return String(localized: "content.header.panic_wiped", comment: "Transient header text confirming the panic wipe completed")
        }
        return "bitchat/"
    }

    var logoAccessibilityLabel: String {
        if panicArmed {
            return String(localized: "content.accessibility.panic_confirm", comment: "Accessibility label for the header logo while a panic wipe is armed")
        }
        if showWipedNotice {
            return String(localized: "content.accessibility.panic_wiped", comment: "Accessibility label for the header logo right after a panic wipe completed")
        }
        return String(localized: "content.accessibility.app_info", comment: "Accessibility label for the header logo that opens app info")
    }

    func handlePanicGesture() {
        if panicArmed {
            executePanicWipe()
        } else {
            armPanicWipe()
        }
    }

    func armPanicWipe() {
        panicStateResetTask?.cancel()
        showWipedNotice = false
        panicArmed = true
        announceForAccessibility(
            String(localized: "content.accessibility.panic_confirm", comment: "Accessibility label for the header logo while a panic wipe is armed")
        )
        panicStateResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            panicArmed = false
        }
    }

    func executePanicWipe() {
        panicStateResetTask?.cancel()
        panicArmed = false
        appChromeModel.panicClearAllData()
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
        announceForAccessibility(
            String(localized: "content.accessibility.panic_wiped", comment: "Accessibility label for the header logo right after a panic wipe completed")
        )
        // Transient on purpose: a persistent "wiped" line would itself be
        // evidence of the wipe if the device is inspected afterwards.
        showWipedNotice = true
        panicStateResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            showWipedNotice = false
        }
    }

    func announceForAccessibility(_ message: String) {
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    func channelPeopleCountAndColor() -> (Int, Color) {
        switch locationChannelsModel.selectedChannel {
        case .location:
            let count = peerListModel.visibleGeohashPeerCount
            return (count, count > 0 ? palette.locationAccent : Color.secondary)
        case .mesh:
            let meshBlue = Color(hue: 0.60, saturation: 0.85, brightness: 0.82)
            let color: Color = peerListModel.connectedMeshPeerCount > 0 ? meshBlue : Color.secondary
            return (peerListModel.reachableMeshPeerCount, color)
        }
    }
}

private struct ContentLocationNotesUnavailableView: View {
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @ThemedPalette private var palette

    @Binding var showLocationNotes: Bool

    let headerHeight: CGFloat

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("content.notes.title")
                    .bitchatFont(size: 16, weight: .bold)
                Spacer()
                Button(action: { showLocationNotes = false }) {
                    Image(systemName: "xmark")
                        .bitchatFont(size: 13, weight: .semibold)
                        .foregroundColor(palette.primary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "common.close", comment: "Accessibility label for close buttons"))
            }
            .frame(height: headerHeight)
            .padding(.horizontal, 12)
            .themedChromePanel(edge: .top)
            Text("content.notes.location_unavailable")
                .bitchatFont(size: 14)
                .foregroundColor(palette.secondary)
            Button("content.location.enable") {
                locationChannelsModel.enableAndRefresh()
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .themedSheetBackground()
        .foregroundColor(palette.primary)
    }
}
