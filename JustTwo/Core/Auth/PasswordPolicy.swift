import Foundation

enum PasswordPolicy {
    static func isValid(_ value: String) -> Bool {
        let hasLetter = value.rangeOfCharacter(from: .letters) != nil
        let hasDigit = value.rangeOfCharacter(from: .decimalDigits) != nil
        return value.count >= 8 && hasLetter && hasDigit
    }
}
