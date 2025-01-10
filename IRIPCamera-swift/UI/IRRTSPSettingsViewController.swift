//
//  IRRTSPSettingsViewController.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import UIKit

struct DeviceValidationError: OptionSet {
    let rawValue: Int

    static let nameEmpty       = DeviceValidationError(rawValue: 1 << 0)  // 0x01
    static let addressEmpty    = DeviceValidationError(rawValue: 1 << 1)  // 0x02
}

protocol IRRTSPSettingsViewControllerDelegate: AnyObject {
    func updatedSettings(_ device: DeviceClass)
}

class IRRTSPSettingsViewController: UIViewController, UITextFieldDelegate {

    // MARK: - Properties
    weak var delegate: IRRTSPSettingsViewControllerDelegate?
    var device: DeviceClass = DeviceClass()

    @IBOutlet weak var streamConnectionTypeSwitch: UISwitch!
    @IBOutlet weak var rtspUrlTextfield: UITextField!

    override func viewDidLoad() {
        super.viewDidLoad()
        let userDefaults = UserDefaults.standard

        streamConnectionTypeSwitch.isOn = userDefaults.bool(forKey: ENABLE_RTSP_URL_KEY)
        useRtspURL(streamConnectionTypeSwitch.isOn)
        rtspUrlTextfield.text = userDefaults.string(forKey: RTSP_URL_KEY)

        setNavigationBarItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.navigationBar.isHidden = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        var tmpRect = view.frame
        tmpRect.size.height = getScreenSize().height
        view.frame = tmpRect
        keyboardWillHide(nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.navigationBar.isHidden = true
    }

    // MARK: - Helper Methods
    private func getScreenSize() -> CGRect {
        let screenRect = UIScreen.main.bounds
        let screenHeight = screenRect.height
        let screenWidth = screenRect.width
        let setHeight: CGFloat
        let setWidth: CGFloat

        if UIApplication.shared.statusBarOrientation.isLandscape {
            setHeight = screenWidth
            setWidth = screenHeight
        } else {
            setHeight = screenHeight
            setWidth = screenWidth
        }

        return CGRect(x: 0, y: 0, width: setWidth, height: setHeight)
    }

    @IBAction func streamConnectionTypeChanged(_ sender: UISwitch) {
        useRtspURL(sender.isOn)
    }

    private func useRtspURL(_ useRtspURL: Bool) {
        if useRtspURL {
            rtspUrlTextfield.alpha = 1.0
            rtspUrlTextfield.isUserInteractionEnabled = true
        } else {
            rtspUrlTextfield.alpha = 0.3
            rtspUrlTextfield.isUserInteractionEnabled = false
        }
    }

    private func setNavigationBarItems() {
        title = NSLocalizedString("Settings", comment: "")

        let btnLeft = UIButton(frame: CGRect(x: 0, y: 0, width: 55, height: 44))
        btnLeft.setTitle(NSLocalizedString("Back", comment: ""), for: .normal)
        btnLeft.setTitleColor(.black, for: .normal)
        btnLeft.addTarget(self, action: #selector(backButtonPressed), for: .touchDown)

        let btnRight = UIButton(frame: CGRect(x: 0, y: 0, width: 55, height: 44))
        btnRight.setTitle(NSLocalizedString("Done", comment: ""), for: .normal)
        btnRight.setTitleColor(.black, for: .normal)
        btnRight.addTarget(self, action: #selector(doneButtonPressed), for: .touchDown)

        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: btnLeft)
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: btnRight)
    }

    @objc private func keyboardWillHide(_ notification: Notification?) {
        var viewRect = self.view.frame
        viewRect.origin.y = 0.0
        self.view.frame = viewRect
    }

    @objc private func backButtonPressed() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func doneButtonPressed() {
        let userDefaults = UserDefaults.standard
        if streamConnectionTypeSwitch.isOn {
            userDefaults.set(streamConnectionTypeSwitch.isOn, forKey: ENABLE_RTSP_URL_KEY)
            if rtspUrlTextfield.text == "demo" {
                rtspUrlTextfield.text = "rtsp://stream.strba.sk:1935/strba/VYHLAD_JAZERO.stream"
            } else if rtspUrlTextfield.text == "demo2" {
                rtspUrlTextfield.text = "rtsp://807e9439d5ca.entrypoint.cloud.wowza.com:1935/app-rC94792j/068b9c9a_stream2"
            } else if rtspUrlTextfield.text == "demo3" {
                rtspUrlTextfield.text = "rtsp://77.110.228.219/axis-media/media.amp"
            }
            userDefaults.set(rtspUrlTextfield.text, forKey: RTSP_URL_KEY)
            userDefaults.synchronize()
            delegate?.updatedSettings(device)
            navigationController?.popViewController(animated: true)
            return
        }

        let errors = checkEditData()
        if errors.isEmpty {
            userDefaults.set(streamConnectionTypeSwitch.isOn, forKey: ENABLE_RTSP_URL_KEY)
            userDefaults.set(rtspUrlTextfield.text, forKey: RTSP_URL_KEY)
            userDefaults.synchronize()
            delegate?.updatedSettings(device)
            navigationController?.popViewController(animated: true)
        } else {
            var errorMessage = ""
            if errors.contains(.nameEmpty) {
                errorMessage += "\(NSLocalizedString("ModifyDeviceError_DeviceName", comment: ""))\n"
            }
            if errors.contains(.addressEmpty) {
                errorMessage += "\(NSLocalizedString("ModifyDeviceError_Address", comment: ""))\n"
            }
            showMessageByTitle(NSLocalizedString("ModifySaveError", comment: ""), message: errorMessage)
        }
    }

    private func checkEditData() -> DeviceValidationError {
        var errors: DeviceValidationError = []

        if device.deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.insert(.nameEmpty)
        }
        if device.deviceAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.insert(.addressEmpty)
        }

        return errors
    }

    private func showMessageByTitle(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
