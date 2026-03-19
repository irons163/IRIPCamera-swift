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

class IRRTSPSettingsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate {

    // MARK: - Properties
    weak var delegate: IRRTSPSettingsViewControllerDelegate?
    var device: DeviceClass = DeviceClass()

    @IBOutlet weak var streamConnectionTypeSwitch: UISwitch!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var displayModeControl: UISegmentedControl!

    private struct UrlItem {
        var url: String
        var isEnabled: Bool
    }

    private var urlItems: [UrlItem] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        let userDefaults = UserDefaults.standard

        streamConnectionTypeSwitch.isOn = userDefaults.bool(forKey: ENABLE_RTSP_URL_KEY)
        loadUrlItems(from: userDefaults)
        setupTableView()
        setupDisplayModeControl(with: userDefaults)
        configureDisplayModeControl()
        applyRtspEnabledState(streamConnectionTypeSwitch.isOn)

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
        applyRtspEnabledState(sender.isOn)
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
        let selectedDisplayMode = displayModeControl.selectedSegmentIndex + 1
        userDefaults.set(selectedDisplayMode, forKey: DISPLAY_MODE_KEY)
        if streamConnectionTypeSwitch.isOn {
            userDefaults.set(streamConnectionTypeSwitch.isOn, forKey: ENABLE_RTSP_URL_KEY)
            urlItems = urlItems.map { item in
                UrlItem(url: normalizeDemoURL(item.url), isEnabled: item.isEnabled)
            }
            saveUrlItems(to: userDefaults)
            userDefaults.synchronize()
            delegate?.updatedSettings(device)
            navigationController?.popViewController(animated: true)
            return
        }

        let errors = checkEditData()
        if errors.isEmpty {
            userDefaults.set(streamConnectionTypeSwitch.isOn, forKey: ENABLE_RTSP_URL_KEY)
            saveUrlItems(to: userDefaults)
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

    private func normalizeDemoURL(_ text: String?) -> String {
        switch text {
        case "demo":
            return "rtsp://stream.strba.sk:1935/strba/VYHLAD_JAZERO.stream"
        case "demo2":
            return "rtsp://807e9439d5ca.entrypoint.cloud.wowza.com:1935/app-rC94792j/068b9c9a_stream2"
        case "demo3":
            return "rtsp://77.110.228.219/axis-media/media.amp"
        default:
            return text ?? ""
        }
    }

    private func normalizeDemoURL(_ text: String) -> String {
        return normalizeDemoURL(Optional(text))
    }

    private func setupDisplayModeControl(with userDefaults: UserDefaults) {
        let savedMode = userDefaults.integer(forKey: DISPLAY_MODE_KEY)
        let displayMode = (1...4).contains(savedMode) ? savedMode : 4
        displayModeControl.removeAllSegments()
        for index in 1...4 {
            displayModeControl.insertSegment(withTitle: "\(index)", at: index - 1, animated: false)
        }
        displayModeControl.selectedSegmentIndex = displayMode - 1
    }

    private func configureDisplayModeControl() {
        displayModeControl.backgroundColor = UIColor.systemGray6
        displayModeControl.selectedSegmentTintColor = UIColor.systemBlue
        displayModeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        displayModeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(IRRTSPUrlTableCell.self, forCellReuseIdentifier: "IRRTSPUrlTableCell")
        tableView.rowHeight = 44
        tableView.isEditing = true
        tableView.allowsSelection = false
    }

    private func applyRtspEnabledState(_ enabled: Bool) {
        tableView.isUserInteractionEnabled = enabled
        tableView.alpha = enabled ? 1.0 : 0.3
    }

    private func loadUrlItems(from userDefaults: UserDefaults) {
        let urls = [
            userDefaults.string(forKey: RTSP_URL_KEY) ?? "",
            userDefaults.string(forKey: RTSP_URL_KEY_2) ?? "",
            userDefaults.string(forKey: RTSP_URL_KEY_3) ?? "",
            userDefaults.string(forKey: RTSP_URL_KEY_4) ?? ""
        ]
        let enables = [
            userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_1) as? Bool ?? true,
            userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_2) as? Bool ?? true,
            userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_3) as? Bool ?? true,
            userDefaults.object(forKey: RTSP_URL_ENABLE_KEY_4) as? Bool ?? true
        ]
        urlItems = zip(urls, enables).map { UrlItem(url: $0.0, isEnabled: $0.1) }
    }

    private func saveUrlItems(to userDefaults: UserDefaults) {
        let items = urlItems.count >= 4 ? urlItems : urlItems + Array(repeating: UrlItem(url: "", isEnabled: true), count: 4 - urlItems.count)
        userDefaults.set(items[0].url, forKey: RTSP_URL_KEY)
        userDefaults.set(items[1].url, forKey: RTSP_URL_KEY_2)
        userDefaults.set(items[2].url, forKey: RTSP_URL_KEY_3)
        userDefaults.set(items[3].url, forKey: RTSP_URL_KEY_4)
        userDefaults.set(items[0].isEnabled, forKey: RTSP_URL_ENABLE_KEY_1)
        userDefaults.set(items[1].isEnabled, forKey: RTSP_URL_ENABLE_KEY_2)
        userDefaults.set(items[2].isEnabled, forKey: RTSP_URL_ENABLE_KEY_3)
        userDefaults.set(items[3].isEnabled, forKey: RTSP_URL_ENABLE_KEY_4)
    }

    // MARK: - UITableViewDataSource / UITableViewDelegate
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return urlItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "IRRTSPUrlTableCell", for: indexPath) as? IRRTSPUrlTableCell else {
            return UITableViewCell()
        }
        let item = urlItems[indexPath.row]
        cell.showsReorderControl = true
        cell.configure(placeholder: "RTSP URL \(indexPath.row + 1)", url: item.url, isEnabled: item.isEnabled)
        cell.onTextChanged = { [weak self] text in
            self?.urlItems[indexPath.row].url = text
        }
        cell.onSwitchChanged = { [weak self, weak cell] isOn in
            self?.urlItems[indexPath.row].isEnabled = isOn
            cell?.setUrlEnabled(isOn)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let movedItem = urlItems.remove(at: sourceIndexPath.row)
        urlItems.insert(movedItem, at: destinationIndexPath.row)
        tableView.reloadData()
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .none
    }
}
