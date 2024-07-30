import ballerina/http;
import ballerinax/scim;


service /userManagement on new http:Listener(8080) {

    resource function post createUser(http:Request req) returns http:Response|error {
        json payload = check req.getJsonPayload();
        string email = check payload.email.toString();
        string password = check payload.password.toString();
        string givenName = check payload.name.givenName.toString();
        string familyName = check payload.name.familyName.toString();
        string userName = "DEFAULT/" + email;

        scim:UserCreate newUser = {
            userName: userName,
            password: password,
            name: {
                givenName: givenName,
                familyName: familyName
            },
            emails: [{value: email}]
        };

        scim:UserResource|scim:ErrorResponse|error response = scimClient->createUser(newUser);

        if (response is scim:UserResource) {
            json createdUser = {
                "id": response.id,
                "userName": response.userName,
                "name": {
                    "givenName": response.name?.givenName,
                    "familyName": response.name?.familyName
                },
                "emails": response.emails
            };

            http:Response res = new;
            res.setPayload(createdUser);
            res.setStatusCode(http:STATUS_CREATED);
            return res;
        } else if (response is scim:ErrorResponse) {
            error createError = error(response.detail);
            return createError;
        } else {
            return error("Unexpected response from SCIM server");
        }
    }
}
