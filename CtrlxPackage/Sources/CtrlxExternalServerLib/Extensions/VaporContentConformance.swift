import CtrlxNetworking
import Vapor

// MARK: - Vapor Content Conformance

// Extend CtrlxCommon types to work with Vapor's Content protocol.
// This keeps CtrlxCommon free of Vapor dependencies while allowing
// these types to be used as HTTP request/response bodies.

extension PairingResponse: Content { }
extension PairingStatus: Content { }
extension PairingRegistration: Content { }
extension PairingCompletion: Content { }
extension LicenseStatus: Content { }
