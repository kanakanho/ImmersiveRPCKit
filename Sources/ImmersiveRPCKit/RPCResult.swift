//
//  RPCResult.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/27.
//

import Foundation

// MARK: - RPCError

/// RPC の失敗を表すエラー型
struct RPCError: Error, LocalizedError, Equatable {
    /// エラーメッセージ
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

// MARK: - RPCResult

/// RPC の実行結果型
///
/// Swift 標準の `Result<Void, RPCError>` の typealias です。
/// `map` / `flatMap` / `get()` などの標準 API がそのまま使えます。
///
/// ```swift
/// // 成功
/// return .success(())
///
/// // 失敗
/// return .failure(RPCError("エラーメッセージ"))
///
/// // パターンマッチ
/// if case .failure(let e) = result {
///     print(e.message)
/// }
///
/// // throws API
/// try result.get()
/// ```
typealias RPCResult = Result<Void, RPCError>

extension Result where Success == Void, Failure == RPCError {
    /// 成功を表す RPCResult を生成する（省略形）
    ///
    /// ```swift
    /// return RPCResult()
    /// ```
    init() { self = .success(()) }

    /// エラーメッセージを持つ失敗を表す RPCResult を生成する（省略形）
    ///
    /// ```swift
    /// return RPCResult("エラーメッセージ")
    /// ```
    init(_ message: String) { self = .failure(RPCError(message)) }

    /// 成功かどうか
    ///
    /// テストや条件分岐での利用を想定したプロパティです。
    /// プロダクションコードでは `if case .success = result { }` パターンを推奨します。
    var success: Bool {
        if case .success = self { return true }
        return false
    }

    /// エラーメッセージ（成功時は空文字）
    var errorMessage: String {
        if case .failure(let e) = self { return e.message }
        return ""
    }
}
