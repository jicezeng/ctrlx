/// Identifies a selected remote session by host and session name
struct RemoteSessionSelection: Equatable, Hashable {
    let hostId: String
    let hostName: String
    let sessionName: String
}
