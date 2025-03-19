//
//  HttpRequest.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation
import Alamofire

protocol HttpRequestDelegate: AnyObject {
    func didFinishStaticRequestJSON(response: Any, callbackID: DeviceConnectorCommandStatus)
    func failToStaticRequest(errorCode code: Int, description: String, callbackID: DeviceConnectorCommandStatus)
    func updateProgress(totalBytesRead: Int64, totalBytesExpectedToRead: Int64)
}

extension HttpRequestDelegate {
    func updateProgress(totalBytesRead: Int64, totalBytesExpectedToRead: Int64) { }
}

class HttpRequest {

    // MARK: - Properties
    static let shared = HttpRequest()
    private var targetDictionary: [String: HttpRequestDelegate] = [:]
    private var manager: Session
    private var requestQueue: OperationQueue

    private init() {
        self.manager = Session()
        self.requestQueue = OperationQueue()
    }

    // MARK: - Methods
    func destroySharedInstance() {
        targetDictionary.removeAll()
        requestQueue.cancelAllOperations()
    }

    func cleanCamCheck() {
        requestQueue.operations
            .compactMap { $0 as? BlockOperation }
            .forEach { $0.cancel() }
    }

    func doJsonRequest(
        token: String?,
        url: String,
        method: HTTPMethod,
        callbackID: DeviceConnectorCommandStatus,
        target: HttpRequestDelegate
    ) {
        guard let url = URL(string: url) else {
            print("Invalid URL")
            return
        }

        let scheme = url.scheme == "http" ? "http" : "https"
        doJsonHttpRequest(
            token: token,
            url: url,
            method: method,
            callbackID: callbackID,
            scheme: scheme,
            target: target
        )
    }

    private func doJsonHttpRequest(
        token: String?,
        url: URL,
        method: HTTPMethod,
        callbackID: DeviceConnectorCommandStatus,
        scheme: String,
        target: HttpRequestDelegate
    ) {
        let request = URLRequest(url: changeURL(url: url, withScheme: scheme))

        AF.request(request)
            .validate()
            .responseJSON { [weak self] response in
                guard let self = self else { return }
                self.handleResponse(response: response, callbackID: callbackID, target: target)
            }
    }

    private func handleResponse(
        response: AFDataResponse<Any>,
        callbackID: DeviceConnectorCommandStatus,
        target: HttpRequestDelegate
    ) {
        switch response.result {
        case .success(let json):
            target.didFinishStaticRequestJSON(response: json, callbackID: callbackID)
        case .failure(let error):
            target.failToStaticRequest(errorCode: error.responseCode ?? -1,
                                       description: error.localizedDescription,
                                       callbackID: callbackID)
        }
    }

    private func changeURL(url: URL, withScheme scheme: String) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components?.url ?? url
    }
}
