//
//  IRStreamControllerFactory.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation

class IRStreamControllerFactory {

    static func createStreamController(by request: IRStreamConnectionRequest) -> IRStreamController {
        if let customRequest = request as? IRCustomStreamConnectionRequest {
            return IRStreamController(device: customRequest.device)
        }
        return IRStreamController(rtspURL: request.rtspUrl)
    }
}
