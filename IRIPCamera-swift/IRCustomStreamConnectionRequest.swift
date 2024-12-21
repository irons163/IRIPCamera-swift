//
//  IRCustomStreamConnectionRequest.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation

class IRCustomStreamConnectionRequest: IRStreamConnectionRequest {
    var device: DeviceClass

    init(device: DeviceClass) {
        self.device = device
    }
}
