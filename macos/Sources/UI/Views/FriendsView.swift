import SwiftUI

struct FriendsView: View {
    @EnvironmentObject var engine: ScrobbleEngine
    @State private var friends: [FriendInfo] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(Loc.t("NavFriends")).font(.headline)
                Spacer()
                Button(Loc.t("BtnRefresh")) { load() }
                    .buttonStyle(.bordered)
                    .disabled(loading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text(err).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if friends.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No friends found").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(friends) { friend in
                    FriendRow(friend: friend)
                }
                .listStyle(.inset)
            }
        }
        .onAppear { load() }
    }

    private func load() {
        loading = true
        error = nil
        Task {
            do {
                friends = try await engine.getFriends()
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
}

struct FriendRow: View {
    let friend: FriendInfo

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: URL(string: friend.avatarUrl)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 40, height: 40)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(friend.username).font(.callout.weight(.semibold))
                    if friend.isNowPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }
                if let track = friend.nowPlayingTrack {
                    Text(track)
                        .font(.caption)
                        .foregroundStyle(friend.isNowPlaying ? .green : .secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 10) {
                    if friend.playcount > 0 {
                        statBadge(icon: "headphones", text: formatCount(friend.playcount))
                    }
                    if !friend.country.isEmpty && friend.country != "None" {
                        statBadge(icon: "globe", text: friend.country)
                    }
                    if friend.memberSince > 0 {
                        statBadge(icon: "calendar", text: "Since \(memberYear)")
                    }
                }
            }

            Spacer()

            Button {
                if let url = URL(string: "https://www.last.fm/user/\(friend.username)") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func statBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10))
        }
        .foregroundStyle(.secondary)
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
    }

    private var memberYear: String {
        let date = Date(timeIntervalSince1970: TimeInterval(friend.memberSince))
        return Calendar.current.component(.year, from: date).description
    }
}
