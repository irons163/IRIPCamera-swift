//
//  IRStreamConnector.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation
import UIKit

protocol IRStreamConnectorDelegate: AnyObject {
    func connectFail(byType type: ConnectorErrorType, errorDesc: String?)
    func startStreaming(with response: IRStreamConnectionResponse?)
}

class IRStreamConnector: NSObject {

    // MARK: - Properties
    var videoRetry: Int = 0
    var response: IRStreamConnectionResponse?
    weak var delegate: IRStreamConnectorDelegate?
    var rtspURL: String?
    var isStopForever: Bool = false

    // MARK: - Methods
    func startStreamConnection() {
        response = IRStreamConnectionResponse()
        response?.rtspURL = rtspURL
        videoRetry = 0

        if let response = response {
            delegate?.startStreaming(with: response)
        }
    }

    func stopStreaming(_ stopForever: Bool) {
        // Placeholder for additional stop streaming logic if needed.
    }

    func changeStream(_ stream: Int) {
        // Placeholder for stream change logic if needed.
    }
}
