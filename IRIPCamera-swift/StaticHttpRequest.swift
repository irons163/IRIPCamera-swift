//
//  StaticHttpRequest.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import Foundation
import Alamofire

enum DeviceType {
    case ipcam
    case router
}

protocol StaticHttpRequestDelegate: AnyObject {
    func didFinishStaticRequestJSON(response: Any, callbackID: DeviceConnectorCommandStatus)
    func failToStaticRequest(errorCode code: Int, description: String, callbackID: DeviceConnectorCommandStatus)
    func updateProgress(totalBytesRead: Int64, totalBytesExpectedToRead: Int64)
}

extension StaticHttpRequestDelegate {
    func updateProgress(totalBytesRead: Int64, totalBytesExpectedToRead: Int64) { }
}

class StaticHttpRequest {

    // MARK: - Properties
    static let shared = StaticHttpRequest()
    private var targetDictionary: [String: StaticHttpRequestDelegate] = [:]
    private var manager: Session
    private var requestQueue: OperationQueue
    private var downloadQueue: OperationQueue
    private var downloading = false

    private init() {
        self.manager = Session()
        self.requestQueue = OperationQueue()
        self.downloadQueue = OperationQueue()
        self.downloadQueue.maxConcurrentOperationCount = 20
    }

    // MARK: - Methods
    func destroySharedInstance() {
        targetDictionary.removeAll()
        requestQueue.cancelAllOperations()
        downloadQueue.cancelAllOperations()
        downloading = false
    }

    func cleanCamCheck() {
        requestQueue.operations
            .compactMap { $0 as? BlockOperation }
            .forEach { $0.cancel() }
    }

    func cleanRouterCheck() {
        downloadQueue.operations
            .compactMap { $0 as? BlockOperation }
            .forEach { $0.cancel() }
    }

    func doJsonRequest(
        token: String?,
        externalLink: String?,
        url: String,
        method: HTTPMethod,
        postData: Data?,
        callbackID: DeviceConnectorCommandStatus,
        target: StaticHttpRequestDelegate
    ) {
        var urlString = url
        if url.hasPrefix("://") {
            urlString = "https\(url)"
        }

        guard let url = URL(string: urlString) else {
            print("Invalid URL")
            return
        }

        let scheme = url.scheme == "http" ? "http" : "https"
        doJsonHttpRequest(
            token: token,
            externalLink: externalLink,
            url: url,
            method: method,
            postData: postData,
            callbackID: callbackID,
            scheme: scheme,
            target: target
        )
    }

    private func doJsonHttpRequest(
        token: String?,
        externalLink: String?,
        url: URL,
        method: HTTPMethod,
        postData: Data?,
        callbackID: DeviceConnectorCommandStatus,
        scheme: String,
        target: StaticHttpRequestDelegate
    ) {
        var request = URLRequest(url: changeURL(url: url, withScheme: scheme))
        request.httpMethod = method.rawValue
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = token {
            request.setValue(token, forHTTPHeaderField: "Token")
        }

        if let externalLink = externalLink {
            request.setValue(externalLink, forHTTPHeaderField: "EXTERNAL_LINK")
        } else {
            request.setValue(url.host, forHTTPHeaderField: "EXTERNAL_LINK")
        }

        if let postData = postData, method == .post {
            request.httpBody = postData
        }

        let key = "\(url)-\(callbackID)"
        targetDictionary[key] = target

        AF.request(request)
            .validate()
            .responseJSON { [weak self] response in
                guard let self = self else { return }
                self.handleResponse(response: response, key: key, callbackID: callbackID, target: target)
            }
    }

    private func handleResponse(
        response: AFDataResponse<Any>,
        key: String,
        callbackID: DeviceConnectorCommandStatus,
        target: StaticHttpRequestDelegate
    ) {
        switch response.result {
        case .success(let json):
            target.didFinishStaticRequestJSON(response: json, callbackID: callbackID)
        case .failure(let error):
            target.failToStaticRequest(errorCode: error.responseCode ?? -1,
                                       description: error.localizedDescription,
                                       callbackID: callbackID)
        }
        targetDictionary.removeValue(forKey: key)
    }

    func doDownload(
        toPath path: String,
        url: String,
        callbackID: DeviceConnectorCommandStatus,
        target: StaticHttpRequestDelegate
    ) {
        guard let requestURL = URL(string: url) else {
            print("Invalid URL")
            return
        }

        let key = "\(requestURL)-\(callbackID)"
        targetDictionary[key] = target

        AF.download(requestURL, to: { _, _ in
            (URL(fileURLWithPath: path), [.removePreviousFile, .createIntermediateDirectories])
        }).downloadProgress { progress in
            target.updateProgress(
                totalBytesRead: progress.completedUnitCount,
                totalBytesExpectedToRead: progress.totalUnitCount
            )
        }.response { [weak self] response in
            guard let self = self else { return }
            self.handleDownloadResponse(response: response, key: key, callbackID: callbackID, target: target)
        }
    }

    private func handleDownloadResponse(
        response: AFDownloadResponse<URL?>,
        key: String,
        callbackID: DeviceConnectorCommandStatus,
        target: StaticHttpRequestDelegate
    ) {
        switch response.result {
        case .success(let destinationURL):
            print("Download completed: \(String(describing: destinationURL))")
            target.didFinishStaticRequestJSON(response: destinationURL as Any, callbackID: callbackID)
        case .failure(let error):
            target.failToStaticRequest(errorCode: error.responseCode ?? -1,
                                       description: error.localizedDescription,
                                       callbackID: callbackID
            )
        }
        targetDictionary.removeValue(forKey: key)
    }

    func stopDownload() {
        downloading = false
        downloadQueue.cancelAllOperations()
    }

    private func changeURL(url: URL, withScheme scheme: String) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        return components?.url ?? url
    }

    func getScheme(fromLoginResult loginResult: [String: Any]) -> String {
        return "http"
    }
}
