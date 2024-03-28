import Vapor

public class CCCHubAuth: FederatedServiceTokens {
    public static var domain: String = "CCCHUB_DOMAIN"
    public static var idEnvKey: String = "CCCHUB_CLIENT_ID"
    public static var secretEnvKey: String = "CCCHUB_CLIENT_SECRET"
    public var domain: String
    public var clientID: String
    public var clientSecret: String
    
    public required init() throws {
        let domainError = ImperialError.missingEnvVar(CCCHubAuth.domain)
        let idError = ImperialError.missingEnvVar(CCCHubAuth.idEnvKey)
        let secretError = ImperialError.missingEnvVar(CCCHubAuth.secretEnvKey)
        
        self.domain = try Environment.get(CCCHubAuth.domain).value(or: domainError)
        self.clientID = try Environment.get(CCCHubAuth.idEnvKey).value(or: idError)
        self.clientSecret = try Environment.get(CCCHubAuth.secretEnvKey).value(or: secretError)
    }
}
