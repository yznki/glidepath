import Foundation

/// Linear issue ids and the GraphQL bodies that read and comment on them. Pure: the network call is made elsewhere.
enum Linear {
    /// The issue a PR is for: the first id in its title, else in its branch name.
    static func issueId(title: String, branch: String) -> String? {
        firstId(in: title) ?? firstId(in: branch.uppercased())
    }

    private static func firstId(in text: String) -> String? {
        text.range(of: "[A-Z][A-Z0-9]+-\\d+", options: .regularExpression).map { String(text[$0]) }
    }

    static func lookupBody(id: String) -> Data {
        envelope(query: "query($id: String!) { issue(id: $id) { id } }", variables: ["id": id])
    }

    static func commentBody(issueUUID: String, body: String) -> Data {
        envelope(query: "mutation($issueId: String!, $body: String!) { commentCreate(input: {issueId: $issueId, body: $body}) { success } }",
                 variables: ["issueId": issueUUID, "body": body])
    }

    /// The issue's UUID from a lookup response. Nil when the issue is null or a key is missing.
    static func parseIssueUUID(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any],
              let issue = payload["issue"] as? [String: Any],
              let id = issue["id"] as? String else { return nil }
        return id
    }

    /// The response body and the HTTP status that curl appended with `-w "\n%{http_code}"`. Nil when there is no status.
    static func splitStatus(_ output: String) -> (body: Data, status: Int)? {
        guard let cut = output.range(of: "\n", options: .backwards), let status = Int(output[cut.upperBound...]) else {
            return nil
        }
        return (Data(output[..<cut.lowerBound].utf8), status)
    }

    /// True when a commentCreate response says the comment was made.
    static func commentPosted(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = json["data"] as? [String: Any],
              let create = payload["commentCreate"] as? [String: Any] else { return false }
        return create["success"] as? Bool == true
    }

    static func commentText(n: Int, url: String, reason: String) -> String {
        "PR #\(n) (\(url)) is blocked: \(reason)."
    }

    private static func envelope(query: String, variables: [String: String]) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])) ?? Data()
    }
}
