import CryptoKit
import Foundation
import Security

public enum TranscriptEncryptionError: Error, Equatable {
    case invalidKeyLength
    case invalidEnvelope
    case authenticationFailed
}

/// Authenticated transcript-at-rest envelope. The key is supplied by the host
/// app and is never serialized alongside the ciphertext.
public struct TranscriptCipher: Sendable {
    public static let keyByteCount = 32
    private static let magic = Data("VOXENC1".utf8)

    private let key: SymmetricKey

    public init(keyData: Data) throws {
        guard keyData.count == Self.keyByteCount else {
            throw TranscriptEncryptionError.invalidKeyLength
        }
        key = SymmetricKey(data: keyData)
    }

    public static func isEncryptedEnvelope(_ data: Data) -> Bool {
        data.starts(with: magic)
    }

    public func seal(_ plaintext: Data) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        guard let combined = sealed.combined else {
            throw TranscriptEncryptionError.invalidEnvelope
        }
        return Self.magic + combined
    }

    public func open(_ envelope: Data) throws -> Data {
        guard Self.isEncryptedEnvelope(envelope) else {
            throw TranscriptEncryptionError.invalidEnvelope
        }
        let combined = envelope.dropFirst(Self.magic.count)
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw TranscriptEncryptionError.authenticationFailed
        }
    }
}

public enum TranscriptEncryptionKeyError: Error {
    case randomGenerationFailed(OSStatus)
    case invalidStoredKey
}

public struct TranscriptEncryptionKeyStore: Sendable {
    public static let shared = TranscriptEncryptionKeyStore()

    private let keychain: KeychainStore

    public init(
        keychain: KeychainStore = KeychainStore(account: "transcript-encryption-key-v1")
    ) {
        self.keychain = keychain
    }

    public func loadOrCreate() throws -> Data {
        let encoded = try keychain.readOrCreate {
            var bytes = [UInt8](repeating: 0, count: TranscriptCipher.keyByteCount)
            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard status == errSecSuccess else {
                throw TranscriptEncryptionKeyError.randomGenerationFailed(status)
            }
            return Data(bytes).base64EncodedString()
        }
        guard let data = Data(base64Encoded: encoded),
              data.count == TranscriptCipher.keyByteCount else {
            throw TranscriptEncryptionKeyError.invalidStoredKey
        }
        return data
    }
}
