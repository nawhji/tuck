import SwiftUI

/// The room selector opens the shared My rooms page, rather than a dropdown menu.
struct HomeHeader: View {
    let initial: String
    let onAvatarTap: () -> Void
    var roomName: String = "My rooms"
    var onRoomsTap: (() -> Void)? = nil
    var roomsEnabled = true

    var body: some View {
        HStack(spacing: 12) {
            Image("TuckLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 88, height: 35)
                .accessibilityLabel("Tuck")
            Button { onRoomsTap?() } label: {
                HStack(spacing: 6) {
                    Text(roomName)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color("TuckBrown"))
                .frame(minHeight: 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!roomsEnabled)
            .accessibilityLabel("My rooms. \(roomName)")
            .accessibilityHint("Opens your saved rooms")
            .layoutPriority(1)
            Spacer(minLength: 0)
            Button(action: onAvatarTap) {
                Text(initial)
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 35, height: 35)
                    .background(Color("TuckBrown"), in: .circle)
            }
            .accessibilityLabel("Profile")
        }
        .padding(.horizontal, 19)
    }
}

#Preview {
    HomeHeader(initial: "H", onAvatarTap: {}, roomName: "Room 1", onRoomsTap: {})
}
