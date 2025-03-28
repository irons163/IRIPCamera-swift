//
//  IRRTSPMediaView.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import UIKit
import IRPlayerSwift
import CoreMotion

class IRRTSPMediaView: UIView, IRStreamControllerDelegate {

    // MARK: - Properties
    @IBOutlet weak var titleBackground: UIView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var loadingActivity: UIActivityIndicatorView!
    @IBOutlet weak var infoLabel: UILabel!

    private let delayedTask = DelayedTask()

    var player: IRPlayerImp! {
        didSet {
            guard let playerView = player.view else {
                return
            }
            imageView = UIImageView(frame: playerView.frame)
            imageView.backgroundColor = .systemGroupedBackground
            imageView.contentMode = .scaleAspectFit
            playerView.addSubview(imageView)
            videoView.insertSubview(playerView, at: 0)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: playerView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: playerView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: playerView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: playerView.trailingAnchor),
            ])

            setupConstraints(for: imageView, in: videoView)
            setupConstraints(for: playerView, in: videoView)
        }
    }
    var doubleTapEnable: Bool = false

    private var imageView: UIImageView!
    private var streamController: IRStreamController?
    private var modes: [IRGLRenderMode]?
    private var parameter: IRMediaParameter?
    private var isStopStreaming: Bool = false

    // MARK: - Initializers
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit(frame: self.frame)
    }

    private func commonInit(frame: CGRect) {
        if modes == nil {
            if parameter == nil {
                parameter = IRFisheyeParameter(width: 1440, height: 1024, up: false, rx: 510, ry: 510, cx: 680, cy: 524, latmax: 75)
            }
            modes = createFisheyeModes(with: parameter)
        }

        if let nibObjects = Bundle.main.loadNibNamed("IRRTSPMediaView", owner: self, options: nil),
           let loadedView = nibObjects.first as? UIView {
            loadedView.frame = frame
            addSubview(loadedView)
            loadingActivity.color = UIColor(red: 56.0 / 255.0, green: 100.0 / 255.0, blue: 0.0, alpha: 1.0)
        }
    }

    deinit {
        stopStreaming(stopForever: true)
    }

    // MARK: - Player Setup
    private func setupConstraints(for view: UIView, in container: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
    }

    // MARK: - Stream Connection
    func startStreamConnection(with request: IRStreamConnectionRequest) {
        streamController?.stopStreaming(stopForever: true)
        streamController = IRStreamControllerFactory.createStreamController(by: request)
        streamController?.eventDelegate = self
        startStreamConnection()
    }

    func startStreamConnection(with device: DeviceClass) {
        streamController?.stopStreaming(stopForever: true)
        streamController = IRStreamController(device: device)
        streamController?.eventDelegate = self
        startStreamConnection()
    }

    private func startStreamConnection() {
        streamController?.videoView = player
        streamController?.startStreamConnection()
    }

    func stopStreaming(stopForever: Bool) {
        streamController?.stopStreaming(stopForever: stopForever)
    }

    // MARK: - IRStreamControllerDelegate
    func streamControllerStatusChanged(_ status: IRStreamControllerStatus) {
        switch status {
        case .buffering:
            delayedTask.schedule(after: 2.0) { [weak self] in
                guard let self else { return }
                loadingActivity.startAnimating()
            }
        case .preparingToPlay:
            loadingActivity.startAnimating()
            imageView.image = UIImage(named: "webcam")
            imageView.isHidden = false
            infoLabel.isHidden = true
        case .playing:
            delayedTask.cancel()
            loadingActivity.stopAnimating()
        default:
            break
        }
    }

    func connectResult(_ videoView: Any, connection: Bool, micSupport: Bool, speakerSupport: Bool) {
        loadingActivity.stopAnimating()

        if !connection {
            imageView.image = UIImage(named: "webcam_off.png")
            imageView.isHidden = false
            return
        }

        imageView.image = UIImage(named: "webcam.png")
        imageView.isHidden = true

        if player.renderModes?.isEmpty != false {
            player.renderModes = modes ?? []
            if let firstMode = modes?.first {
                player.selectRenderMode(renderMode: firstMode)
            }
        }
    }

    func showErrorMessage(_ message: String) {
        DispatchQueue.main.async {
            self.infoLabel.text = message
            self.infoLabel.isHidden = false
        }
    }

    // MARK: - Utility Methods
    private func createFisheyeModes(with parameter: IRMediaParameter?) -> [IRGLRenderMode] {
        let normal = IRGLRenderMode2D()
        let fisheye2Pano = IRGLRenderMode2DFisheye2Pano()
        let fisheye = IRGLRenderMode3DFisheye()
        let fisheye4P = IRGLRenderModeMulti4P()

        normal.shiftController.enabled = false

        fisheye2Pano.contentMode = .scaleAspectFill
        fisheye2Pano.wideDegreeX = 360
        fisheye2Pano.wideDegreeY = 20

        fisheye4P.parameter = fisheye.parameter ?? IRFisheyeParameter(width: 0, height: 0, up: false, rx: 0, ry: 0, cx: 0, cy: 0, latmax: 80)
        fisheye.aspect = 16.0 / 9.0
        fisheye4P.aspect = fisheye.aspect

        normal.name = "Rawdata"
        fisheye2Pano.name = "Panorama"
        fisheye.name = "Onelen"
        fisheye4P.name = "Fourlens"

        return [fisheye2Pano, fisheye, fisheye4P, normal]
    }
}
