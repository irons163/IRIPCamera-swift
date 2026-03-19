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
    var intDisplayMode: Int = 4
    var intCurrentCh: Int = 0
    private var aryVideoView: [UIView] = []
    private var aryDevices: [IRStreamConnectionRequest] = []

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

    private var players: [IRPlayerImp] = []
    private var videoViews: [IRRTSPMediaView] = []
    private var previousDisplayMode: Int = 4

    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()

        aryDevices = IRStreamConnectionRequestFactory.createStreamConnectionRequest()
        loadDisplayModeFromDefaults()

        setupPlayers()
        initVideoView()
        startStreamsForCurrentMode()
    }

    deinit {
        stopAllStreams(fromGoBack: true)
    }

    // MARK: - Player Setup
    func setupPlayers() {
        players = (0..<4).map { _ in
            let player = IRPlayerImp.player()
            configure(player: player)
            return player
        }
    }

    func configure(player: IRPlayerImp) {
        player.playableBufferInterval = 0
        player.registerPlayerNotification(target: self,
                                          stateAction: #selector(stateAction(_:)),
                                          progressAction: #selector(progressAction(_:)),
                                          playableAction: #selector(playableAction(_:)),
                                          errorAction: #selector(errorAction(_:)))
        player.viewTapAction = { _, _ in
            print("Player display view did click!")
        }
        player.decoder = IRPlayerDecoder.FFmpegDecoder()
    }

    // MARK: - Video Views
    func initVideoView() {
        addVideoViewToBlock()

        aryVideoView = [firstView, secondView, thirdView, fourthView]

        setBlockShowOrHide(fromViewDidLoad: false)
        resizeViewBlock()
    }

    func addVideoViewToBlock() {
        videoViews = (0..<4).map { _ in IRRTSPMediaView() }
        for index in 0..<4 {
            addVideoViewToBlock(byCh: index)
        }
    }

    func addVideoViewToBlock(byCh ch: Int) {
        guard ch < videoViews.count, ch < players.count else { return }
        let videoView = videoViews[ch]
        videoView.doubleTapEnable = true
        videoView.onDoubleTap = { [weak self] in
            self?.handleDoubleTap(on: ch)
        }

        switch ch {
        case 0:
            videoView.player = players[ch]
            firstView.addSubview(videoView)
            addConstraints(to: videoView, in: firstView)
        case 1:
            videoView.player = players[ch]
            secondView.addSubview(videoView)
            addConstraints(to: videoView, in: secondView)
        case 2:
            videoView.player = players[ch]
            thirdView.addSubview(videoView)
            addConstraints(to: videoView, in: thirdView)
        case 3:
            videoView.player = players[ch]
            fourthView.addSubview(videoView)
            addConstraints(to: videoView, in: fourthView)
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
        if intDisplayMode == 1 {
            for (index, view) in aryVideoView.enumerated() {
                view.isHidden = (index != intCurrentCh)
            }
            return
        }

        for (index, view) in aryVideoView.enumerated() {
            view.isHidden = index >= intDisplayMode
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

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        let vc = segue.destination as? IRRTSPSettingsViewController
        vc?.delegate = self
    }

    // MARK: - Stream Control
    func startStreamConnection(byDeviceIndex index: Int) {
        guard index < videoViews.count, index < aryDevices.count else { return }
        let videoView = videoViews[index]
        videoView.startStreamConnection(with: aryDevices[index])
    }

    func startStreamsForCurrentMode() {
        if intDisplayMode == 1 {
            startStreamConnection(byDeviceIndex: intCurrentCh)
        } else {
            let count = min(intDisplayMode, aryDevices.count)
            for index in 0..<count {
                startStreamConnection(byDeviceIndex: index)
            }
        }
    }

    func stopAllStreams(fromGoBack: Bool) {
        for index in 0..<4 {
            stopStream(byChannel: index, fromGoBack: fromGoBack)
        }
    }

    func stopStream(byChannel channel: Int, fromGoBack: Bool) {
        guard channel < videoViews.count else { return }
        let videoView = videoViews[channel]
        videoView.stopStreaming(stopForever: true)
    }

    // MARK: - Notification Handlers
    @objc func stateAction(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        let state = IRState.state(fromUserInfo: userInfo)
        let currentPlayer = notification.object as? IRPlayerImp
        switch state.current {
        case .none: infoLabel.text = "None"
        case .buffering: infoLabel.text = "Buffering..."
        case .readyToPlay:
            infoLabel.text = "Prepare"
            currentPlayer?.play()
        case .playing: infoLabel.text = "Playing"
        case .suspend: infoLabel.text = "Suspend"
        case .finished: infoLabel.text = "Finished"
        case .failed: infoLabel.text = "Error"
        }
    }

    @objc func progressAction(_ notification: Notification) { }

    @objc func playableAction(_ notification: Notification) { }

    @objc func errorAction(_ notification: Notification) { }

    // MARK: - Utility
    func timeString(fromSeconds seconds: CGFloat) -> String {
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    // MARK: - IRRTSPSettingsViewControllerDelegate
    func updatedSettings(_ device: DeviceClass) {
        aryDevices = IRStreamConnectionRequestFactory.createStreamConnectionRequest()
        loadDisplayModeFromDefaults()
        setBlockShowOrHide(fromViewDidLoad: false)
        resizeViewBlock()
        stopAllStreams(fromGoBack: false)
        startStreamsForCurrentMode()
    }

    private func loadDisplayModeFromDefaults() {
        let savedMode = UserDefaults.standard.integer(forKey: DISPLAY_MODE_KEY)
        if (1...4).contains(savedMode) {
            intDisplayMode = savedMode
        } else {
            intDisplayMode = 4
        }
    }

    private func handleDoubleTap(on channel: Int) {
        if intDisplayMode == 1 {
            if intCurrentCh == channel {
                intDisplayMode = previousDisplayMode
                setBlockShowOrHide(fromViewDidLoad: false)
                resizeViewBlock()
            } else {
                intCurrentCh = channel
                setBlockShowOrHide(fromViewDidLoad: false)
                resizeViewBlock()
            }
            return
        }

        previousDisplayMode = intDisplayMode
        intCurrentCh = channel
        intDisplayMode = 1
        setBlockShowOrHide(fromViewDidLoad: false)
        resizeViewBlock()
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
