import Vapor

public class DARCSSOAuth: FederatedServiceTokens {
    public static var idEnvKey: String = "DARCSSO_CLIENT_ID"
    public static var secretEnvKey: String = "DARCSSO_CLIENT_SECRET"
    public var clientID: String
    public var clientSecret: String
    
    public required init() throws {
        let idError = ImperialError.missingEnvVar(DARCSSOAuth.idEnvKey)
        let secretError = ImperialError.missingEnvVar(DARCSSOAuth.secretEnvKey)
        
        self.clientID = try Environment.get(DARCSSOAuth.idEnvKey).value(or: idError)
        self.clientSecret = try Environment.get(DARCSSOAuth.secretEnvKey).value(or: secretError)
    }
}
