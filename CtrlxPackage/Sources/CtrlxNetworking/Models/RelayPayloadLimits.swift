/// Wire-size limits shared by Relay clients and the Relay server.
public enum RelayPayloadLimits {
    /// Maximum WebSocket frame accepted by the Relay.
    public static let maxWebSocketFrameBytes = 1 << 20

    /// Maximum raw bytes in one dropped-files command.
    ///
    /// File bytes are Base64-encoded inside the command, then the complete
    /// command is encrypted and Base64-encoded again. 512 KiB keeps the final
    /// encrypted JSON frame safely below the 1 MiB transport limit.
    public static let maxDroppedFilesRawBytes = 512 * 1_024
}
