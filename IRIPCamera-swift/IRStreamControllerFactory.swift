//
//  IRStreamControllerFactory.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation

class IRStreamControllerFactory {
    static func createStreamController(by request: IRStreamConnectionRequest) -> IRStreamController {
        var streamController: IRStreamController?

        if let customRequest = request as? IRCustomStreamConnectionRequest {
            streamController = IRStreamController(device: customRequest.device)
        } else {
            streamController = IRStreamController(rtspURL: request.rtspUrl)
        }

        return streamController!
    }
}
