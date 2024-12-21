//
//  IRRTSPPlayerViewController.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import UIKit
import IRPlayerSwift

class IRRTSPPlayerViewController: UIViewController, IRRTSPSettingsViewControllerDelegate {

    // MARK: - Properties
    var intDisplayMode: Int = 1
    var intCurrentCh: Int = 0
    var aryVideoView: [UIView] = []
    var aryDevices: [IRStreamConnectionRequest] = []

    @IBOutlet weak var firstViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var secondViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var thirdViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var fourthViewConstraint: NSLayoutConstraint!
    @IBOutlet weak var firstView: UIView!
    @IBOutlet weak var secondView: UIView!
    @IBOutlet weak var thirdView: UIView!
    @IBOutlet weak var fourthView: UIView!
//    @IBOutlet weak var LoadingActivity: UIActivityIndicatorView!
    @IBOutlet weak var infoLabel: UILabel!

    var player: IRPlayerImp!
    var player2: IRPlayerImp!
    var player3: IRPlayerImp!
    var player4: IRPlayerImp!

    var firstVideoView: IRRTSPMediaView!
    var secondVideoView: IRRTSPMediaView!
    var thirdVideoView: IRRTSPMediaView!
    var fourthVideoView: IRRTSPMediaView!

    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()

        aryDevices = IRStreamConnectionRequestFactory.createStreamConnectionRequest()

        setupPlayers()
        initVideoView()
        startStreamConnection(byDeviceIndex: 0)
    }

    deinit {
        stopAllStreams(fromGoBack: true)
    }

    // MARK: - Player Setup
    func setupPlayers() {
        player = IRPlayerImp.player()
        configure(player: player)

        player2 = IRPlayerImp.player()
        configure(player: player2)

        player3 = IRPlayerImp.player()
        configure(player: player3)

        player4 = IRPlayerImp.player()
        configure(player: player4)
    }

    func configure(player: IRPlayerImp) {
        player.registerPlayerNotification(target: self,
                                          stateAction: #selector(stateAction(_:)),
                                          progressAction: #selector(progressAction(_:)),
                                          playableAction: #selector(playableAction(_:)),
                                          errorAction: #selector(errorAction(_:)))
        player.viewTapAction = { _, _ in
            print("Player display view did click!")
        }
        player.decoder = IRPlayerDecoder.FFmpegDecoder()
//        let input = IRFFVideoInput()
//        player.replaceVideoWithInput(videoInput: input, videoType: .normal)
    }

    // MARK: - Video Views
    func initVideoView() {
        addVideoViewToBlock()

        aryVideoView = [firstView, secondView, thirdView, fourthView]

        setBlockShowOrHide(fromViewDidLoad: false)
        resizeViewBlock()
    }

    func addVideoViewToBlock() {
        for i in 0..<4 {
            addVideoViewToBlock(byCh: i)
        }
    }

    func addVideoViewToBlock(byCh ch: Int) {
        let videoView = IRRTSPMediaView()
        videoView.doubleTapEnable = true

        switch ch {
        case 0:
            firstVideoView = videoView
            firstVideoView.player = player
            firstView.addSubview(firstVideoView)
            addConstraints(to: firstVideoView, in: firstView)
        case 1:
            secondVideoView = videoView
            secondVideoView.player = player2
            secondView.addSubview(secondVideoView)
            addConstraints(to: secondVideoView, in: secondView)
        case 2:
            thirdVideoView = videoView
            thirdVideoView.player = player3
            thirdView.addSubview(thirdVideoView)
            addConstraints(to: thirdVideoView, in: thirdView)
        case 3:
            fourthVideoView = videoView
            fourthVideoView.player = player4
            fourthView.addSubview(fourthVideoView)
            addConstraints(to: fourthVideoView, in: fourthView)
        default:
            break
        }
    }

    func addConstraints(to videoView: IRRTSPMediaView, in containerView: UIView) {
        videoView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            videoView.topAnchor.constraint(equalTo: containerView.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor)
        ])
    }

    func setBlockShowOrHide(fromViewDidLoad: Bool) {
        for (index, view) in aryVideoView.enumerated() {
            view.isHidden = (intDisplayMode == 1 && index != intCurrentCh)
        }
    }

    func resizeViewBlock() {
        if intDisplayMode == 1 {
            switch intCurrentCh {
            case 0: firstViewConstraint = firstViewConstraint.updateMultiplier(1.0)
            case 1: secondViewConstraint = secondViewConstraint.updateMultiplier(1.0)
            case 2: thirdViewConstraint = thirdViewConstraint.updateMultiplier(1.0)
            case 3: fourthViewConstraint = fourthViewConstraint.updateMultiplier(1.0)
            default: break
            }
        } else {
            firstViewConstraint = firstViewConstraint.updateMultiplier(0.5)
            secondViewConstraint = secondViewConstraint.updateMultiplier(0.5)
            thirdViewConstraint = thirdViewConstraint.updateMultiplier(0.5)
            fourthViewConstraint = fourthViewConstraint.updateMultiplier(0.5)
        }
    }

    // MARK: - Stream Control
    func startStreamConnection(byDeviceIndex index: Int) {
        guard index < aryVideoView.count, index < aryDevices.count else { return }
        let tmpView = aryVideoView[index]
        if let tmpVideo = tmpView.subviews.first as? IRRTSPMediaView {
            tmpVideo.startStreamConnection(with: aryDevices[index])
        }
    }

    func stopAllStreams(fromGoBack: Bool) {
        for index in 0..<4 {
            stopStream(byChannel: index, fromGoBack: fromGoBack)
        }
    }

    func stopStream(byChannel channel: Int, fromGoBack: Bool) {
        guard channel < aryVideoView.count else { return }
        let tmpView = aryVideoView[channel]
        if let tmpVideo = tmpView.subviews.first as? IRRTSPMediaView {
            tmpVideo.stopStreaming(stopForever: true)
            tmpVideo.removeFromSuperview()
        }
    }

    // MARK: - Notification Handlers
    @objc func stateAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let state = IRState.state(fromUserInfo: userInfo)
        switch state.current {
        case .none: infoLabel.text = "None"
        case .buffering: infoLabel.text = "Buffering..."
        case .readyToPlay:
            infoLabel.text = "Prepare"
            player.play()
        case .playing: infoLabel.text = "Playing"
        case .suspend: infoLabel.text = "Suspend"
        case .finished: infoLabel.text = "Finished"
        case .failed: infoLabel.text = "Error"
        }
    }

    @objc func progressAction(_ notification: Notification) {}

    @objc func playableAction(_ notification: Notification) {
//        guard let playable = IRPlayable.playable(fromUserInfo: notification.userInfo) else { return }
//        print("Playable time: \(playable.current)")
    }

    @objc func errorAction(_ notification: Notification) {
//        guard let error = IRError.error(fromUserInfo: notification.userInfo) else { return }
//        print("Player did error: \(error.error ?? "Unknown error")")
    }

    // MARK: - Utility
    func timeString(fromSeconds seconds: CGFloat) -> String {
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: - IRRTSPSettingsViewControllerDelegate
    func updatedSettings(_ device: DeviceClass) {
        aryDevices = IRStreamConnectionRequestFactory.createStreamConnectionRequest()
        startStreamConnection(byDeviceIndex: 0)
    }
}

private extension NSLayoutConstraint {

    func updateMultiplier(_ multiplier: CGFloat) -> NSLayoutConstraint {
        // Deactivate the current constraint
        NSLayoutConstraint.deactivate([self])

        // Create a new constraint with the updated multiplier
        let newConstraint = NSLayoutConstraint(
            item: firstItem!,
            attribute: firstAttribute,
            relatedBy: relation,
            toItem: secondItem,
            attribute: secondAttribute,
            multiplier: multiplier,
            constant: constant
        )

        // Copy properties from the old constraint to the new one
        newConstraint.priority = priority
        newConstraint.shouldBeArchived = shouldBeArchived
        newConstraint.identifier = identifier
        newConstraint.isActive = true

        // Activate the new constraint
        NSLayoutConstraint.activate([newConstraint])

        return newConstraint
    }
}
