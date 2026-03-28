//
//  RequestQueue.swift
//  ImmersiveRPCKit
//
//  Created by kanakanho on 2026/03/25.
//

import Foundation

/// A single queued request with retry tracking
@available(visionOS 26.0, *)
struct QueuedRequest {
    let request: RequestSchema
    var timestamp: Date
    var retryCount: Int
    let maxRetries: Int
    
    var shouldRetry: Bool {
        return retryCount < maxRetries
    }
}

/// Thread-safe queue for managing pending RPC requests with retry logic
@available(visionOS 26.0, *)
@Observable
@MainActor
class RequestQueue {
    /// Dictionary of pending requests keyed by request ID
    private var pendingRequests: [UUID: QueuedRequest] = [:]
    
    /// Timeout duration for requests
    private let timeout: TimeInterval
    
    /// Maximum retry attempts
    private let maxRetries: Int
    
    /// Timer for periodic retry checks
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    
    /// Callback for retrying requests
    var onRetry: ((RequestSchema) -> Void)?
    
    init(timeout: TimeInterval = 1.0, maxRetries: Int = 3) {
        self.timeout = timeout
        self.maxRetries = maxRetries
        startRetryLoop()
    }
    
    private func startRetryLoop() {
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(for: .seconds(self.timeout))
                self.checkForRetries()
            }
        }
    }
    
    deinit {
        retryTask?.cancel()
    }
    
    /// Add a request to the queue
    func enqueue(_ request: RequestSchema) {
        let queuedRequest = QueuedRequest(
            request: request,
            timestamp: Date(),
            retryCount: 0,
            maxRetries: maxRetries
        )
        pendingRequests[request.id] = queuedRequest
    }
    
    /// Remove a request from the queue (called when ack is received)
    func dequeue(_ requestId: UUID) {
        pendingRequests.removeValue(forKey: requestId)
    }
    
    /// Check if a request is in the queue
    func contains(_ requestId: UUID) -> Bool {
        return pendingRequests[requestId] != nil
    }
    
    /// Get the number of pending requests
    var count: Int {
        return pendingRequests.count
    }
    
    /// Check for requests that need to be retried
    private func checkForRetries() {
        guard !pendingRequests.isEmpty else { return }
        let now = Date()
        var requestsToRetry: [UUID] = []
        var requestsToRemove: [UUID] = []
        
        for (id, queuedRequest) in pendingRequests {
            let elapsed = now.timeIntervalSince(queuedRequest.timestamp)
            
            if elapsed >= timeout {
                if queuedRequest.shouldRetry {
                    requestsToRetry.append(id)
                } else {
                    // Max retries reached, remove from queue
                    requestsToRemove.append(id)
                }
            }
        }
        
        // Remove requests that have exceeded max retries
        for id in requestsToRemove {
            pendingRequests.removeValue(forKey: id)
        }
        
        // Retry requests that have timed out
        for id in requestsToRetry {
            if var queuedRequest = pendingRequests[id] {
                queuedRequest.retryCount += 1
                queuedRequest.timestamp = now
                pendingRequests[id] = queuedRequest
                onRetry?(queuedRequest.request)
            }
        }
    }
    
    /// Clear all pending requests
    func clear() {
        pendingRequests.removeAll()
    }
}
