import UIKit
import RxCocoa
import RxSwift

final class HomeViewController: UIViewController {

    private let disposeBag = DisposeBag()
    private let spinner = SpinnerViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let helloLabel = UILabel()
        helloLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(helloLabel)

        NSLayoutConstraint.activate([
            helloLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            helloLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])

        showSpinner()

        // MARK: - Old way
        
        login { [weak self] in
            if case .success(let token) = $0 {
                dump(token)
            }
            self?.getAllUsers() { result in
                dump(result)
            }
        }

        // MARK: - RxSwift

        Observable<Void>.just(())
            .flatMapLatest { [weak self] () -> Single<String> in
                guard let self = self else { return .error(CustomError.generic) }
                return self.rxLogin()
            }
            .flatMapLatest { [weak self] token -> Single<[User]> in
                guard let self = self else { return .error(CustomError.generic) }
                print("RxSwift ---- \(token)")
                return self.rxGetUsers()
            }
            .subscribe { users in
                dump(users)
            }
            .disposed(by: disposeBag)

        // MARK: - Concurrency Continuation (bridging)
        /*
        Task {
            do {
                let token = try await asyncContinuationLogin()
                print("Continuation ---- \(token)")
                let users = try await asyncContinuationGetUsers()
                dump("Continuation ---- \(users)")
            } catch {
                dump(error)
            }
        }
        */
//
        // MARK: - Concurrency URLSession

        Task {
            do {
                let token = try await asyncSessionLogin()
                let users = try await asyncSessionGetUsers()
            } catch {
                dump(error)
            }
        }

    }

    private func hideSpinner() {
        spinner.willMove(toParent: nil)
        spinner.view.removeFromSuperview()
        spinner.removeFromParent()
    }

    private func showSpinner() {
        addChild(spinner)
        spinner.view.frame = view.frame
        view.addSubview(spinner.view)
        spinner.didMove(toParent: self)
    }
}

// MARK: - Swift Concurrency

extension HomeViewController {

    // MARK: - Checked Continuation
    /*
     Contination is bridge between closure and async/await
     */

    private func asyncContinuationLogin() async throws -> String {
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            guard let self = self else {
                continuation.resume(throwing: CustomError.generic)
                return
            }
            self.login { result in
                switch result {
                case .success(let token):
                    continuation.resume(returning: token)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func asyncContinuationGetUsers() async throws -> [User] {
        return try await withCheckedThrowingContinuation{ [weak self] continuation in
            guard let self = self else {
//                continuation.resume(throwing: CustomError.generic)
                return
            }
            self.getAllUsers { result in
                switch result {
                case .success(let users):
                    continuation.resume(returning: users)
                case .failure(let error): break
//                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Async URLSession

    private func asyncSessionLogin() async throws -> String {
        var request = URLRequest(url: URL(string: "https://reqres.in/api/login")!)
        request.httpMethod = "POST"
        let params = ["email": "eve.holt@reqres.in", "password": "cityslicka"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: params, options: [])
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as! Dictionary<String, AnyObject>
        return json["token"] as! String
    }

    private func asyncSessionGetUsers() async throws -> [User] {
        var request = URLRequest(url: URL(string: "https://reqres.in/api/users")!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as! Dictionary<String, AnyObject>
        let usersJson = json["data"]
        let usersData = try JSONSerialization.data(withJSONObject: usersJson!, options: [])
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([User].self, from: usersData)
    }
}

// MARK: - RxSwift

extension HomeViewController {

    private func rxLogin() -> Single<String> {
        return .create { [weak self] observer in
            guard let self = self else {
                observer(.failure(CustomError.generic))
                return Disposables.create()
            }
            self.login { result in
                switch result {
                case .success(let token): observer(.success(token))
                case .failure(let error): observer(.failure(error))
                }
            }
            return Disposables.create()
        }
    }

    private func rxGetUsers() -> Single<[User]> {
        return .create { [weak self] observer in
            guard let self = self else {
                observer(.failure(CustomError.generic))
                return Disposables.create()
            }
            self.getAllUsers { result in
                switch result {
                case .success(let users): observer(.success(users))
                case .failure(let error): observer(.failure(error))
                }
            }
            return Disposables.create()
        }
    }
}

// MARK: - Old way

extension HomeViewController {

    private func login(completion: ((Result<String, Error>) -> Void)?) {
        var request = URLRequest(url: URL(string: "https://reqres.in/api/login")!)
        request.httpMethod = "POST"
        let params = ["email": "eve.holt@reqres.in", "password": "cityslicka"]
        request.httpBody = try? JSONSerialization.data(withJSONObject: params, options: [])
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { data, _, apiError in
            if let apiError = apiError {
                completion?(.failure(apiError))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data!) as! Dictionary<String, AnyObject>
                let token = json["token"] as? String ?? ""
                completion?(.success(token))
            } catch {
                completion?(.failure(error))
            }
        }
        task.resume()
    }

    private func getAllUsers(completion: ((Result<[User], Error>) -> Void)?) {
        var request = URLRequest(url: URL(string: "https://reqres.in/api/users")!)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { data, _, apiError in
            if let apiError = apiError {
                completion?(.failure(apiError))
                return
            }
            do {
                let json = try JSONSerialization.jsonObject(with: data!) as! Dictionary<String, AnyObject>
                let usersJson = json["data"]
                let usersData = try JSONSerialization.data(withJSONObject: usersJson!, options: [])
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let users = try decoder.decode([User].self, from: usersData)
                completion?(.success(users))
            } catch {
                completion?(.failure(error))
            }
        }
        task.resume()
    }
}

struct User: Decodable {

    let id: Int
    let email: String
    let firstName: String
    let lastName: String
    let avatar: String
}

enum CustomError: LocalizedError {

    case generic

    var errorDescription: String? {
        return "Error"
    }
}


class SpinnerViewController: UIViewController {
    var spinner = UIActivityIndicatorView(style: .large)

    override func loadView() {
        view = UIView()
        view.backgroundColor = UIColor(white: 0, alpha: 0.7)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
    }
}
