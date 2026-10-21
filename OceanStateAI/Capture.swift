import SwiftUI
import UIKit

struct CameraCapture: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController(); controller.sourceType = .camera
        controller.delegate = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCapture
        init(_ parent: CameraCapture) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) { parent.onImage(data) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct VoiceConversationView: View {
    @EnvironmentObject var store: OceanStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                Image(systemName: store.recording ? "waveform" : "water.waves")
                    .font(.system(size: 80, weight: .ultraLight)).foregroundStyle(.cyan)
                    .symbolEffect(.pulse, options: .repeating, isActive: store.recording || store.sending || store.playing)
                Text(store.recording ? "Listening" : store.sending ? "Thinking on your PC" : store.playing ? "Speaking" : store.busy ? "Transcribing" : "Ready when you are")
                    .font(.title2.weight(.medium))
                Text("Voice conversations use your PC’s transcription and speech services. Tap when you finish speaking. After each reply, the next recording begins while this screen is open.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 30)
                if store.recording {
                    Button("Finish speaking", systemImage: "arrow.up.circle.fill") { Task { await store.toggleRecording() } }.buttonStyle(.borderedProminent)
                } else if store.playing {
                    Button("Interrupt & speak", systemImage: "mic") { store.stopAudio(); Task { await store.toggleRecording() } }.buttonStyle(.borderedProminent)
                } else if !store.sending && !store.busy {
                    Button("Start speaking", systemImage: "mic.fill") { store.voiceConversation = true; Task { await store.toggleRecording() } }.buttonStyle(.borderedProminent)
                }
                if store.sending { Button("Stop response") { Task { await store.stop() } } }
                Spacer()
                Button("End voice conversation", role: .destructive) { store.endVoiceConversation(); dismiss() }.padding(.bottom, 25)
            }.frame(maxWidth: .infinity).navigationTitle("Voice").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { store.endVoiceConversation(); dismiss() } }
        }.onDisappear { store.endVoiceConversation() }
    }
}
