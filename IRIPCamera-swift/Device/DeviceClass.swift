//
//  DeviceClass.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation
import CoreLocation

protocol DeviceClassDelegate: AnyObject {
    func didDeviceStatusFinish(_ device: DeviceClass)
}

class DeviceClass: NSObject, NSCopying {

    // MARK: - Properties
    var connector: DeviceConnector?
    var httpPort: MultiPort = MultiPort.initial()

    var deviceName: String = ""
    var deviceAddress: String = "" // IP or URL
    var userName: String = ""
    var password: String = ""
    var streamInfo: String? = ""

    weak var delegate: DeviceClassDelegate?

    // MARK: - Initializers
    override init() {
        super.init()
        initializeDefaults()
    }

    init(delegate: DeviceClassDelegate) {
        super.init()
        self.delegate = delegate
        initializeDefaults()
    }

    private func initializeDefaults() {
        deviceName = ""
        deviceAddress = ""
        userName = ""
        password = ""
        streamInfo = ""
        httpPort = MultiPort.initial()
    }

    // MARK: - Copying
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = DeviceClass()
        copy.httpPort = httpPort
        copy.deviceName = deviceName
        copy.deviceAddress = deviceAddress
        copy.userName = userName
        copy.password = password
        copy.streamInfo = streamInfo
        return copy
    }
}

// MARK: - Methods
extension DeviceClass {

    func stopConnectionAction() {
        connector?.stopConnectionAction()
        connector?.delegate = nil
        connector = nil
    }

    func getWideDegreeValue() -> Float {
        return 0
    }
}

// MARK: - HttpRequestDelegate
extension DeviceClass: HttpRequestDelegate {

    func didFinishStaticRequestJSON(response: Any, callbackID: DeviceConnectorCommandStatus) {
        delegate?.didDeviceStatusFinish(self)
    }

    func failToStaticRequest(errorCode code: Int, description: String, callbackID: DeviceConnectorCommandStatus) {
        delegate?.didDeviceStatusFinish(self)
    }
}
