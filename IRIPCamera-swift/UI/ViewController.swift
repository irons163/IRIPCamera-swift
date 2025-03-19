//
//  ViewController.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import UIKit
import Network

class ViewController: UIViewController {

    // MARK: - Properties
    @IBOutlet weak var tableView: UITableView!
    private var browser: NWBrowser?

    // MARK: - Lifecycle Methods
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.navigationBar.isHidden = true
        tableView.delegate = self
        tableView.dataSource = self
    }
}

// MARK: - UITableViewDataSource Methods
extension ViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        switch indexPath.row {
        case 0:
            cell.textLabel?.text = "RTSP Player"
        default:
            break
        }
        return cell
    }
}

// MARK: - UITableViewDelegate Methods
extension ViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        var player: UIViewController?
        switch indexPath.row {
        case 0:
            let parameters = NWParameters.tcp
            browser = NWBrowser(for: .bonjour(type: "_dummy._tcp", domain: nil), using: parameters)
            var done = false
            browser?.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    player = storyboard.instantiateViewController(withIdentifier: "IRRTSPPlayerViewController")
                    if let player = player {
                        if done {
                            return
                        }
                        done = true
                        navigationController?.pushViewController(player, animated: true)
                    }
                case .failed(let error):
                    print("Browser failed: \(error)")
                case .setup:
                    print("Browser setup")
                case .cancelled:
                    print("Browser cancelled")
                case .waiting(let arg):
                    print("Browser waiting \(arg))")
                @unknown default:
                    print("Browser unexpected state \(state)")
                }
            }
            browser?.start(queue: .main)
        default:
            break
        }
    }
}
