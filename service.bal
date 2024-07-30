import ballerina/http;

type UserRequest record {
    string emailAddress;
    Name name;
    string password;
    string userName;
};

type Name record {
    string familyName;
    string givenName;
};

service / on new http:Listener(8090) {
    resource function post risk(@http:Payload UserRequest req) returns UserRequest|error? {
        // Return the same request data as the response.
        return req;
    }
}
