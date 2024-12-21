//
//  ViewController.swift
//  IRIPCamera-swift
//
//  Created by irons on 2024/12/21.
//

import UIKit

class ViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var tableView: UITableView!

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.navigationBar.isHidden = true
        tableView.delegate = self
        tableView.dataSource = self
    }

    // MARK: - UITableViewDataSource Methods
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

    // MARK: - UITableViewDelegate Methods
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        var player: UIViewController?
        switch indexPath.row {
        case 0:
            player = storyboard.instantiateViewController(withIdentifier: "IRRTSPPlayerViewController")
            if let player = player {
                navigationController?.pushViewController(player, animated: true)
            }
        default:
            break
        }
    }
}
