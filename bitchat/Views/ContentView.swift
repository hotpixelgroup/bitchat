//
// ContentView.swift
// bitchat
//
// This is free and unencumbered software released into the public domain.
// For more information, see <https://unlicense.org>
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import BitFoundation

/// On macOS 14+, disables the default system focus ring on TextFields.
/// On earlier macOS versions and on iOS this is a no-op.
struct FocusEffectDisabledModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 14.0, *) {
            content.focusEffectDisabled()
        } else {
            content
        }
        #else
        content
        #endif
    }
}

struct ContentView: View {
    @EnvironmentObject private var appChromeModel: AppChromeModel
    @EnvironmentObject private var privateConversationModel: PrivateConversationModel
    @EnvironmentObject private var verificationModel: VerificationModel
    @EnvironmentObject private var conversationUIModel: ConversationUIModel
    @EnvironmentObject private var locationChannelsModel: LocationChannelsModel
    @EnvironmentObject private var peerListModel: PeerListModel

    @StateObject private var voiceRecordingVM = VoiceRecordingViewModel()
    @State private var messageText = ""
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.appTheme) private var appTheme
    @State private var showSidebar = false
    @State private var selectedMessageSender: String?
    @State private var selectedMessageSenderID: PeerID?
    @FocusState private var isNicknameFieldFocused: Bool
    @State private var isAtBottomPublic = true
    @State private var isAtBottomPrivate = true
    @State private var autocompleteDebounceTimer: Timer?
    @State private var showVerifySheet = false
    @State private var showLocationNotes = false
    @State private var notesGeohash: String?
    @State private var imagePreviewURL: URL?
    #if os(iOS)
    @State private var showImagePicker = false
    @State private var imagePickerSourceType: UIImagePickerController.SourceType = .camera
    #else
    @State private var showMacImagePicker = false
    #endif
    @ScaledMetric(relativeTo: .body) private var headerHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .subheadline) private var headerPeerIconSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var headerPeerCountFontSize: CGFloat = 12
    @State private var windowCountPublic: Int = 300
    @State private var windowCountPrivate: [PeerID: Int] = [:]
    /// One hint per zero-peer episode: reset when peers come back into range.
    @State private var didShowZeroPeerNotice = false

    @ThemedPalette private var palette

    private var selectedPrivatePeerID: PeerID? {
        privateConversationModel.selectedPeerID
    }

    private var usesGlassLayout: Bool { appTheme.usesGlassChrome }

    var body: some View {
        mainContent
            .onAppear {
                conversationUIModel.setCurrentColorScheme(colorScheme)
                conversationUIModel.setCurrentTheme(appTheme)
                #if os(macOS)
                DispatchQueue.main.async {
                    isNicknameFieldFocused = false
                    isTextFieldFocused = true
                }
                #endif
            }
            .onChange(of: colorScheme) { newValue in
                conversationUIModel.setCurrentColorScheme(newValue)
            }
            .onChange(of: appTheme) { newValue in
                conversationUIModel.setCurrentTheme(newValue)
            }
        .background(ThemedRootBackground())
        .foregroundColor(palette.primary)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 400)
        #endif
        .onChange(of: selectedPrivatePeerID) { newValue in
            if newValue != nil {
                showSidebar = true
            }
        }
        .onChange(of: peerListModel.reachableMeshPeerCount) { count in
            if count > 0 {
                didShowZeroPeerNotice = false
            }
        }
        .onChange(of: conversationUIModel.pendingComposerText) { staged in
            guard let staged else { return }
            conversationUIModel.pendingComposerText = nil
            // Append rather than overwrite: a draft in progress survives an
            // incoming share.
            if messageText.isEmpty {
                messageText = staged
            } else if messageText.hasSuffix(" ") {
                messageText += staged
            } else {
                messageText += " " + staged
            }
            isTextFieldFocused = true
        }
        .sheet(
            isPresented: Binding(
                get: { showSidebar || selectedPrivatePeerID != nil },
                set: { isPresented in
                    if !isPresented {
                        showSidebar = false
                        privateConversationModel.endConversation()
                    }
                }
            )
        ) {
            #if os(iOS)
            ContentPeopleSheetView(
                showSidebar: $showSidebar,
                messageText: $messageText,
                selectedMessageSender: $selectedMessageSender,
                selectedMessageSenderID: $selectedMessageSenderID,
                imagePreviewURL: $imagePreviewURL,
                windowCountPublic: $windowCountPublic,
                windowCountPrivate: $windowCountPrivate,
                isAtBottomPrivate: $isAtBottomPrivate,
                isTextFieldFocused: $isTextFieldFocused,
                voiceRecordingVM: voiceRecordingVM,
                autocompleteDebounceTimer: $autocompleteDebounceTimer,
                headerHeight: headerHeight,
                onSendMessage: sendMessage,
                showImagePicker: $showImagePicker,
                imagePickerSourceType: $imagePickerSourceType
            )
            #else
            ContentPeopleSheetView(
                showSidebar: $showSidebar,
                messageText: $messageText,
                selectedMessageSender: $selectedMessageSender,
                selectedMessageSenderID: $selectedMessageSenderID,
                imagePreviewURL: $imagePreviewURL,
                windowCountPublic: $windowCountPublic,
                windowCountPrivate: $windowCountPrivate,
                isAtBottomPrivate: $isAtBottomPrivate,
                isTextFieldFocused: $isTextFieldFocused,
                voiceRecordingVM: voiceRecordingVM,
                autocompleteDebounceTimer: $autocompleteDebounceTimer,
                headerHeight: headerHeight,
                onSendMessage: sendMessage,
                showMacImagePicker: $showMacImagePicker
            )
            #endif
        }
        .sheet(isPresented: $appChromeModel.isAppInfoPresented) {
            AppInfoView(onPanicWipe: { appChromeModel.panicClearAllData() })
        }
        .sheet(isPresented: Binding(
            get: { appChromeModel.showingFingerprintFor != nil && !showSidebar && selectedPrivatePeerID == nil },
            set: { _ in appChromeModel.clearFingerprint() }
        )) {
            if let peerID = appChromeModel.showingFingerprintFor {
                FingerprintView(peerID: peerID)
                    .environmentObject(verificationModel)
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(
            get: { showImagePicker && !showSidebar && selectedPrivatePeerID == nil },
            set: { newValue in
                if !newValue {
                    showImagePicker = false
                }
            }
        )) {
            ImagePickerView(sourceType: imagePickerSourceType) { image in
                showImagePicker = false
                conversationUIModel.processSelectedImage(image)
            }
            .ignoresSafeArea()
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: Binding(
            get: { showMacImagePicker && !showSidebar && selectedPrivatePeerID == nil },
            set: { newValue in
                if !newValue {
                    showMacImagePicker = false
                }
            }
        )) {
            MacImagePickerView { url in
                showMacImagePicker = false
                conversationUIModel.processSelectedImage(from: url)
            }
        }
        #endif
        .sheet(isPresented: Binding(
            get: { imagePreviewURL != nil },
            set: { presenting in
                if !presenting {
                    imagePreviewURL = nil
                }
            }
        )) {
            if let url = imagePreviewURL {
                ImagePreviewView(url: url)
            }
        }
        .alert("Recording Error", isPresented: $voiceRecordingVM.showAlert, actions: {
            Button("common.ok", role: .cancel) {}
            if voiceRecordingVM.state == .permissionDenied {
                Button("location_channels.action.open_settings") {
                    SystemSettings.microphone.open()
                }
            }
        }, message: {
            Text(voiceRecordingVM.state.alertMessage)
        })
        .alert("content.alert.bluetooth_required.title", isPresented: $appChromeModel.showBluetoothAlert) {
            Button("content.alert.bluetooth_required.settings") {
                SystemSettings.bluetooth.open()
            }
            Button("common.ok", role: .cancel) {}
        } message: {
            Text(appChromeModel.bluetoothAlertMessage)
        }
        .onDisappear {
            autocompleteDebounceTimer?.invalidate()
        }
    }

    /// Matrix: classic opaque bars with dividers. Glass: full-bleed message
    /// list scrolling underneath floating chrome panels (safe-area insets),
    /// so the translucency gains usable space instead of losing it.
    @ViewBuilder
    private var mainContent: some View {
        if usesGlassLayout {
            publicMessageList
                .safeAreaInset(edge: .top, spacing: 0) {
                    headerView
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if selectedPrivatePeerID == nil {
                        composerView
                    }
                }
        } else {
            VStack(spacing: 0) {
                headerView

                Divider()

                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        publicMessageList
                            .background(palette.background)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }

                Divider()

                if selectedPrivatePeerID == nil {
                    composerView
                }
            }
        }
    }

    private var headerView: some View {
        ContentHeaderView(
            showSidebar: $showSidebar,
            showVerifySheet: $showVerifySheet,
            showLocationNotes: $showLocationNotes,
            notesGeohash: $notesGeohash,
            isNicknameFieldFocused: $isNicknameFieldFocused,
            headerHeight: headerHeight,
            headerPeerIconSize: headerPeerIconSize,
            headerPeerCountFontSize: headerPeerCountFontSize
        )
    }

    private var publicMessageList: some View {
        MessageListView(
            privatePeer: nil,
            isAtBottom: $isAtBottomPublic,
            messageText: $messageText,
            selectedMessageSender: $selectedMessageSender,
            selectedMessageSenderID: $selectedMessageSenderID,
            imagePreviewURL: $imagePreviewURL,
            windowCountPublic: $windowCountPublic,
            windowCountPrivate: $windowCountPrivate,
            showSidebar: $showSidebar,
            isTextFieldFocused: $isTextFieldFocused
        )
    }

    private var composerView: some View {
        #if os(iOS)
        ContentComposerView(
            messageText: $messageText,
            isTextFieldFocused: $isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: sendMessage,
            showImagePicker: $showImagePicker,
            imagePickerSourceType: $imagePickerSourceType
        )
        #else
        ContentComposerView(
            messageText: $messageText,
            isTextFieldFocused: $isTextFieldFocused,
            voiceRecordingVM: voiceRecordingVM,
            autocompleteDebounceTimer: $autocompleteDebounceTimer,
            onSendMessage: sendMessage,
            showMacImagePicker: $showMacImagePicker
        )
        #endif
    }

    private func sendMessage() {
        guard let trimmed = messageText.trimmedOrNilIfEmpty else { return }

        messageText = ""

        // A public mesh message sent with nobody in range echoes locally
        // exactly like a delivered one; narrate the silence once so the
        // sender knows why replies aren't coming. Local-only, one hint per
        // zero-peer episode. Only when Bluetooth is actually on — with the
        // radio off the packet never broadcasts and the "will sync" promise
        // would be false (the persistent bluetooth status row explains that
        // case instead).
        let shouldExplainZeroPeers: Bool = {
            guard !didShowZeroPeerNotice,
                  !trimmed.hasPrefix("/"),
                  selectedPrivatePeerID == nil,
                  appChromeModel.bluetoothState == .poweredOn,
                  case .mesh = locationChannelsModel.selectedChannel
            else { return false }
            return peerListModel.reachableMeshPeerCount == 0
        }()

        DispatchQueue.main.async {
            // Sending puts you at the bottom — you want to see your own
            // message. Assert it before the append(s) so the scroll/unseen
            // logic treats this as a self-send even when a system line (e.g.
            // the zero-peer hint) becomes the last row and would otherwise
            // read as an incoming message.
            if selectedPrivatePeerID == nil {
                isAtBottomPublic = true
            } else {
                isAtBottomPrivate = true
            }
            self.conversationUIModel.sendMessage(trimmed)
            if shouldExplainZeroPeers {
                self.didShowZeroPeerNotice = true
                self.conversationUIModel.showLocalNotice(
                    String(localized: "system.mesh.no_peers_hint", comment: "Local system line shown once when sending a mesh message with no peers in Bluetooth range")
                )
            }
        }
    }
}
