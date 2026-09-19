//  FormURLEncoding.swift
//  escape_plan — S8.3 auth
//
//  `POST /auth/login` is the ONE endpoint in this project that is not JSON.
//
//  It takes FastAPI's `OAuth2PasswordRequestForm` (backend/app/api_auth.py), which means
//  `application/x-www-form-urlencoded` — and the email field is named **`username`**, because
//  that is what the OAuth2 password flow calls it. Send JSON, or send `email=`, and the server
//  answers 422 with a validation body that says nothing about the real mistake.
//
//  Encoding it by hand rather than with URLComponents is deliberate: `URLComponents.query`
//  does not escape "+", and a "+" in a password decodes server-side as a space. That is a
//  login that fails for one user in a hundred and is essentially undebuggable from the app.

import Foundation

enum FormURLEncoding {

    /// RFC 3986 unreserved. Everything else is percent-encoded, including "+" and "/".
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Percent-encode one field name or value.
    ///
    /// Spaces become `%20`, not `+`. Both are legal and Python's `parse_qsl` (what Starlette
    /// uses) decodes either, but `%20` is unambiguous — with `+`-as-space you must then escape
    /// a literal "+", and getting only half of that rule right is the classic form-encoding bug.
    static func escape(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// Build a form body from ordered pairs. Ordered, not a dictionary, so the bytes are
    /// deterministic and a test can assert on them.
    static func body(_ fields: [(name: String, value: String)]) -> Data {
        Data(fields.map { "\(escape($0.name))=\(escape($0.value))" }
                   .joined(separator: "&").utf8)
    }

    static let contentType = "application/x-www-form-urlencoded"
}
