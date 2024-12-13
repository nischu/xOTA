// Based on https://github.com/hendrickson-tyler/swift-pkce
/*
 MIT License

 Copyright (c) 2022 Tyler Hendrickson

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

#if canImport(Security)
import Security
#endif
import Foundation
import Crypto

let bitsInChar = 6
let bitsInOctet = 8
let minCodeVerifierLength = 43
let maxCodeVerifierLength = 128

/// Errors that can occur when generating values for PKCE.
public enum PKCEError: Error {
    /// Requested an invalid code verifier. The requested code verifier length is not within the range of 43 to 128.
    case invalidCodeVerifierLength
    /// An error occured when trying to generate the random octets for the code verifier.
    case failedToGenerateRandomOctets
    /// An error occured when trying to genereate the code challenge for a given code verifier.
    case failedToCreateCodeChallengeChallenge
}
    
/// Generates a new, random code verifier.
/// - Parameter length: The number of characters for the code verifier. The code verifier must have a minimum of 43 characters and a maximum of 128 characters. If omitted, it will be defaulted to the maximum length of `128`.
/// - Returns: The generated code verifier.
public func generateCodeVerifier(length: Int = 128) throws -> String {
    if length < minCodeVerifierLength || length > maxCodeVerifierLength {
        throw PKCEError.invalidCodeVerifierLength
    }
    let octetCount = length * bitsInChar / bitsInOctet
    let octets = try generateRandomOctets(octetCount: octetCount)
    return encodeBase64URLString(octets: octets)
}

/// Generates a code challenge for a given code verifier.
/// - Parameter codeVerifier: The code verifier for which to generate a code challenge.
/// - Returns: The generated code challenge.
public func generateCodeChallenge(for codeVerifier: String) throws -> String {
    let challenge = codeVerifier
        .data(using: .ascii)
        .map { SHA256.hash(data: $0) }
        .map { encodeBase64URLString(octets: $0) }
    guard let challenge = challenge else {
        throw PKCEError.failedToCreateCodeChallengeChallenge
    }
    return challenge
}

/// Generates a specified number of random octets.
/// - Parameter octetCount: The number of octets to generate.
/// - Returns: The randomly generated octets.
private func generateRandomOctets(octetCount: Int) throws -> [UInt8] {
    var octets = [UInt8](repeating: 0, count: octetCount)
    #if canImport(Security)
    let status = SecRandomCopyBytes(kSecRandomDefault, octets.count, &octets)
    if status != errSecSuccess {
        throw PKCEError.failedToGenerateRandomOctets
    }
    #else
    var generator = SystemRandomNumberGenerator()
    for i in 0..<octets.count {
        octets[i] = generator.next()
    }
    #endif
    return octets
}

/// Encodes a sequence of octets as a Base64 URL string.
/// - Parameter octets: The octets to be encoded.
/// - Returns: The Base64 URL-encoded string.
private func encodeBase64URLString<S>(octets: S) -> String where S: Sequence, UInt8 == S.Element {
    let data = Data(octets)
        return data
            .base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: .whitespaces)
}
