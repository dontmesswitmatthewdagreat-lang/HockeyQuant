import Foundation
import Observation

@MainActor
@Observable
final class ModelsViewModel {

    enum State {
        case loading
        case loaded([UserModel])
        case error(String)
    }

    private let api: APIClient
    private(set) var state: State = .loading

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func load(token: String) async {
        state = .loading
        do {
            state = .loaded(try await api.models(token: token))
        } catch {
            Log.error("Failed to load models", error)
            state = .error(error.localizedDescription)
        }
    }

    func delete(id: String, token: String) async {
        do {
            try await api.deleteModel(id: id, token: token)
            await load(token: token)
        } catch {
            Log.error("Failed to delete model", error)
        }
    }
}
