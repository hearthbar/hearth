import Combine
import SwiftUI

/// Fields for the user's own Google project. Paste, type, or drop the client JSON.
struct CredentialsForm: View {
    @Bindable var model: OnboardingModel
    @State private var dropTargeted = false
    private let clipboardTimer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CredentialField(model: model, field: .projectID,
                            placeholder: "1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d",
                            hint: "A UUID from the Device Access console")
            CredentialField(model: model, field: .clientID,
                            placeholder: "1234-abc.apps.googleusercontent.com",
                            hint: "Ends with .apps.googleusercontent.com")
            CredentialField(model: model, field: .clientSecret, secure: true,
                            placeholder: "GOCSPX-...",
                            hint: "Usually starts with GOCSPX-")

            HStack(spacing: 8) {
                Button {
                    model.pasteFromClipboard()
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                .overlay(alignment: .topTrailing) {
                    if model.clipboardHasNew {
                        Circle().fill(Color.accentColor).frame(width: 8, height: 8).offset(x: 3, y: -3)
                    }
                }
                Button {
                    model.importJSON()
                } label: {
                    Label("Import JSON", systemImage: "square.and.arrow.down")
                }
                Spacer()
                if let notice = model.notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary).transition(.opacity)
                } else {
                    Link("How to get these", destination: Links.setupGuide).font(.caption)
                }
            }
            .controlSize(.small)
            .animation(.snappy, value: model.notice)
        }
        .padding(14)
        .background(Card())
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(Label("Drop client JSON", systemImage: "doc.badge.plus").font(.headline))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.importJSON(at: url) }
            }
            return true
        }
        .onReceive(clipboardTimer) { _ in model.checkClipboard() }
        .task(id: model.notice) {
            guard model.notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            model.notice = nil
        }
    }
}

private struct CredentialField: View {
    @Bindable var model: OnboardingModel
    let field: NestConfig.Field
    var secure = false
    let placeholder: String
    let hint: String

    @State private var reveal = false

    private var text: Binding<String> {
        Binding(get: { model.value(field) }, set: { model.set($0, for: field) })
    }

    private var value: String { model.value(field) }
    private var valid: Bool { model.isValid(field) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.label(field)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !value.isEmpty {
                    Label(valid ? "Looks good" : hint,
                          systemImage: valid ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(valid ? Color.green : Color.orange)
                        .labelStyle(.titleAndIcon)
                        .transition(.opacity)
                }
            }
            HStack(spacing: 6) {
                Group {
                    if secure && !reveal {
                        SecureField(placeholder, text: text)
                    } else {
                        TextField(placeholder, text: text)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit { model.reroute(field) }
                .onChange(of: value) { model.reroute(field) }
                if secure {
                    Button {
                        reveal.toggle()
                    } label: {
                        Image(systemName: reveal ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(reveal ? "Hide" : "Show")
                }
            }
        }
        .animation(.snappy, value: valid)
    }
}
