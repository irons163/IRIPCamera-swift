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

class DeviceClass: NSObject, NSCopying, StaticHttpRequestDelegate {

    // MARK: - Properties
    var connector: DeviceConnector?
    var currentState: ConnectorState = .loginConnector
    var prefType: PrefType = .unknown
    var deviceId: Int = 0
    var httpPort: MultiPort = MultiPort.initial()
    var streamNO: Int = -1
    var isSelected: Bool = false
    var isOnline: Int = 0
    var ipRatio: Int = 60

    var deviceName: String = ""
    var deviceAddress: String = "" // IP or URL
    var userName: String = ""
    var password: String = ""
    var streamInfo: String? = ""
    var macAddress: String = ""

    weak var delegate: DeviceClassDelegate?
    var httpCMDAddress: String = ""
    var httpCMDPort: MultiPort = MultiPort.initial()

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
        macAddress = ""
        deviceId = 0
        streamNO = -1
        httpPort = MultiPort.initial()
        httpCMDAddress = ""
        httpCMDPort = MultiPort.initial()
        isSelected = false
        isOnline = 0
        prefType = .unknown
        ipRatio = 60
    }

    // MARK: - Copying
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = DeviceClass()
        copy.deviceId = deviceId
        copy.httpPort = httpPort
        copy.httpCMDPort = httpCMDPort
        copy.streamNO = streamNO

        copy.deviceName = deviceName
        copy.deviceAddress = deviceAddress
        copy.userName = userName
        copy.password = password
        copy.streamInfo = streamInfo
        copy.macAddress = macAddress

        copy.isSelected = isSelected
        copy.isOnline = isOnline
        copy.prefType = prefType
        copy.httpCMDAddress = httpCMDAddress

        return copy
    }

    // MARK: - Methods
    func stopConnectionAction() {
        connector?.stopConnectionAction()
        connector?.delegate = nil
        connector = nil
    }

    func getWideDegreeValue() -> Float {
        return 0
    }

    // MARK: - StaticHttpRequestDelegate
    func didFinishStaticRequestJSON(response: Any, callbackID: DeviceConnectorCommandStatus) {
        delegate?.didDeviceStatusFinish(self)
    }

    func failToStaticRequest(errorCode code: Int, description: String, callbackID: DeviceConnectorCommandStatus) {
        isOnline = 0
        delegate?.didDeviceStatusFinish(self)
    }

    // MARK: - deviceConnectorDelegate
    func didFinishLoginAction(
        byResultType resultCode: Int,
        deviceInfo: [String: Any],
        errorDesc: String,
        address: String,
        port: MultiPort
    ) {
        print("\(address):\(port.httpPort), result=\(resultCode), errorDesc=\(errorDesc)")
        delegate?.didDeviceStatusFinish(self)
    }
}
