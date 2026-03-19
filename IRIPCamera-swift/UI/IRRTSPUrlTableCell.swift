//
//  IRRTSPUrlTableCell.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import UIKit

final class IRRTSPUrlTableCell: UITableViewCell, UITextFieldDelegate {

    var onTextChanged: ((String) -> Void)?
    var onSwitchChanged: ((Bool) -> Void)?

    private let urlTextField = UITextField()
    private let enableSwitch = UISwitch()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(placeholder: String, url: String, isEnabled: Bool) {
        urlTextField.placeholder = placeholder
        urlTextField.text = url
        enableSwitch.isOn = isEnabled
        setUrlEnabled(isEnabled)
    }

    func setUrlEnabled(_ enabled: Bool) {
        urlTextField.isUserInteractionEnabled = enabled
        urlTextField.alpha = enabled ? 1.0 : 0.3
    }

    private func setupViews() {
        selectionStyle = .none
        contentView.addSubview(urlTextField)
        contentView.addSubview(enableSwitch)

        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        enableSwitch.translatesAutoresizingMaskIntoConstraints = false

        urlTextField.borderStyle = .roundedRect
        urlTextField.keyboardType = .URL
        urlTextField.autocorrectionType = .no
        urlTextField.autocapitalizationType = .none
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.returnKeyType = .done
        urlTextField.delegate = self
        urlTextField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)

        enableSwitch.addTarget(self, action: #selector(switchDidChange), for: .valueChanged)

        NSLayoutConstraint.activate([
            urlTextField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            urlTextField.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            enableSwitch.leadingAnchor.constraint(equalTo: urlTextField.trailingAnchor, constant: 8),
            enableSwitch.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            enableSwitch.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            urlTextField.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @objc private func textDidChange() {
        onTextChanged?(urlTextField.text ?? "")
    }

    @objc private func switchDidChange() {
        onSwitchChanged?(enableSwitch.isOn)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
