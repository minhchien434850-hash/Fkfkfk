import SwiftUI

/// The remote-control screen: live preview + trackpad + keyboard/media controls.
/// Pointer deltas are batched by `InputManager` for a smooth, low-latency cursor.
struct SessionView: View {
    @StateObject private var vm: SessionViewModel
    @State private var lastTranslation: CGSize?
    @State private var typed = ""
    @FocusState private var keyboardFocused: Bool

    init(viewModel: SessionViewModel) { _vm = StateObject(wrappedValue: viewModel) }

    var body: some View {
        VStack(spacing: 10) {
            preview
            trackpad
            speedControl
            clickRow
            controlGrid
        }
        .padding(.horizontal, 12)
        .navigationTitle(vm.device.name)
        .navigationBarTitleDisplayMode(.inline)
        .background(hiddenKeyboardField)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private var preview: some View {
        ZStack {
            if let image = vm.frameImage {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ZStack { Color.black; ProgressView().tint(.white) }
            }
            if vm.isReconnecting {
                Label("Reconnecting…", systemImage: "wifi.exclamationmark")
                    .font(.caption).padding(6).background(.ultraThinMaterial).clipShape(Capsule())
            }
        }
        .frame(height: 170).frame(maxWidth: .infinity)
        .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var trackpad: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemBackground))
            .overlay(Text("SWIPE TO MOVE · TAP = CLICK")
                .font(.caption2.bold()).foregroundStyle(.tertiary))
            .frame(height: 150)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if let last = lastTranslation {
                            vm.input.pan(dx: value.translation.width - last.width,
                                         dy: value.translation.height - last.height)
                        }
                        lastTranslation = value.translation
                    }
                    .onEnded { value in
                        if hypot(value.translation.width, value.translation.height) < 8 { vm.input.tap() }
                        lastTranslation = nil
                    }
            )
    }

    private var speedControl: some View {
        HStack(spacing: 10) {
            Text("Speed").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { vm.sensitivity }, set: { vm.sensitivity = $0 }), in: 1...6, step: 0.5)
            Text(String(format: "%.1fx", vm.sensitivity)).font(.caption.bold()).frame(width: 42)
        }
    }

    private var clickRow: some View {
        HStack(spacing: 10) {
            controlButton("Left Click") { vm.input.tap() }
            controlButton("Right Click") { vm.input.rightClick() }
        }
    }

    private var controlGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            gridButton("backward.end.fill", "Prev") { vm.input.media(.prev) }
            gridButton("playpause.fill", "Play") { vm.input.media(.playpause) }
            gridButton("forward.end.fill", "Next") { vm.input.media(.next) }
            gridButton("speaker.slash.fill", "Mute") { vm.input.media(.mute) }
            gridButton("speaker.wave.1.fill", "Vol -") { vm.input.media(.voldown) }
            gridButton("speaker.wave.3.fill", "Vol +") { vm.input.media(.volup) }
            gridButton("menubar.dock.rectangle", "Desktop") { vm.input.system(.desktop) }
            gridButton("lock.fill", "Lock") { vm.input.system(.lock) }
            gridButton("keyboard", "Keyboard") { keyboardFocused = true }
            gridButton("delete.left.fill", "Backspace") { vm.input.key("backspace") }
            gridButton("space", "Space") { vm.input.key("space") }
            gridButton("return", "Enter") { vm.input.key("enter") }
            gridButton("chevron.up", "Scroll ↑") { vm.input.scroll(-3) }
            gridButton("chevron.down", "Scroll ↓") { vm.input.scroll(3) }
            gridButton("cursorarrow.click.2", "Double") { vm.input.doubleClick() }
            gridButton("escape", "Esc") { vm.input.key("esc") }
        }
    }

    private var hiddenKeyboardField: some View {
        TextField("", text: $typed)
            .focused($keyboardFocused)
            .frame(width: 1, height: 1).opacity(0.01)
            .autocorrectionDisabled().textInputAutocapitalization(.never)
            .onChange(of: typed) { _, newValue in
                guard !newValue.isEmpty else { return }
                vm.input.text(newValue); typed = ""
            }
    }

    private func controlButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.bold()).frame(maxWidth: .infinity).frame(height: 46)
                .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }

    private func gridButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.body).foregroundStyle(.tint)
                Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}
