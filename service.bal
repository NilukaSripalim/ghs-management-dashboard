import ballerina/http;
import ballerinax/scim;

// Configurations (replace with actual values)
configurable string asgardeoOrg = ?;
configurable string clientId = ?;
configurable string clientSecret = ?;

configurable string[] scope = [
    "internal_user_mgt_view",
    "internal_user_mgt_list",
    "internal_user_mgt_create",
    "internal_user_mgt_delete",
    "internal_user_mgt_update",
    "internal_group_mgt_view",
    "internal_group_mgt_list",
    "internal_group_mgt_create",
    "internal_group_mgt_delete",
    "internal_group_mgt_update"
];

// Create a SCIM connector configuration
scim:ConnectorConfig scimConfig = {
    orgName: asgardeoOrg,
    clientId: clientId,
    clientSecret: clientSecret,
    scope: scope
};

scim:Client scimClient = new(scimConfig);

service /userManagement on new http:Listener(8080) {

    resource function get groupMemberCount(http:Request request) returns json|error {
        if !hasValidScope(request, "internal_group_mgt_view") {
            return http:FORBIDDEN;
        }

        int studentCount = 0;
        int commerceCount = 0;
        int artCount = 0;
        int scienceCount = 0;

        // Replace with actual group IDs
        string studentGroupId = "studentGroupId";
        string commerceGroupId = "commerceGroupId";
        string artsGroupId = "artsGroupId";
        string scienceGroupId = "scienceGroupId";

        scim:GroupResource studentGroup = check scimClient->getGroup(studentGroupId);
        scim:GroupResource commerceGroup = check scimClient->getGroup(commerceGroupId);
        scim:GroupResource artGroup = check scimClient->getGroup(artsGroupId);
        scim:GroupResource scienceGroup = check scimClient->getGroup(scienceGroupId);

        if studentGroup.members != () {
            studentCount = (<scim:Member[]> studentGroup.members).length();
        }
        if commerceGroup.members != () {
            commerceCount = (<scim:Member[]> commerceGroup.members).length();
        }
        if artGroup.members != () {
            artCount = (<scim:Member[]> artGroup.members).length();
        }
        if scienceGroup.members != () {
            scienceCount = (<scim:Member[]> scienceGroup.members).length();
        }

        json searchResponse = {
            totalStudentCount: studentCount,
            teacherCount: {
                commerce: commerceCount,
                arts: artCount,
                science: scienceCount
            }
        };

        return searchResponse;
    }

    resource function post createUserAccount(http:Request request) returns http:Created|error|http:BadRequest {
        if !hasValidScope(request, "internal_user_mgt_create") {
            return http:FORBIDDEN;
        }

        json payload = check request.getJsonPayload();
        string emailAddress = payload.emailAddress.toString();
        string password = payload.password.toString();
        string givenName = payload.name?.givenName.toString();
        string familyName = payload.name?.familyName.toString();
        string userName = payload.userName.toString();

        string|error userGroupId = findUserGroup(emailAddress);

        if userGroupId is error {
            return http:BAD_REQUEST;
        }

        scim:UserCreate user = {
            password: password,
            userName: userName,
            name: {
                givenName: givenName,
                familyName: familyName
            },
            emails: [{value: emailAddress}]
        };

        scim:UserResource|scim:ErrorResponse|error createdUser = check scimClient->createUser(user);

        if createdUser is error || !(createdUser.id is string) {
            return http:INTERNAL_SERVER_ERROR;
        }

        string createdUserId = <string>createdUser.id;

        scim:GroupPatch groupPatch = {
            Operations: [
                {op: "add", value: {members: [{"value": createdUserId, "display": user.userName}]}}
            ]
        };

        scim:GroupResponse|scim:ErrorResponse|error groupResponse = check scimClient->patchGroup(userGroupId, groupPatch);

        if groupResponse is error|scim:ErrorResponse {
            error? userDeleteError = deleteUser(createdUserId);

            if userDeleteError is error {
                return http:INTERNAL_SERVER_ERROR;
            }

            return http:INTERNAL_SERVER_ERROR;
        }

        return http:CREATED;
    }

    resource function delete deleteUser(http:Request request) returns http:STATUS_NO_CONTENT|error {
        if !hasValidScope(request, "internal_user_mgt_delete") {
            return http:FORBIDDEN;
        }

        json payload = check request.getJsonPayload();
        string emailAddress = payload.emailAddress.toString();
        error|scim:UserResource searchResponse = findUserByEmail(emailAddress);

        if searchResponse is error {
            return http:NOT_FOUND;
        }

        string userId = <string>searchResponse.id;

        if userId == "" {
            return http:NOT_FOUND;
        }

        scim:ErrorResponse|error? deleteResponse = check scimClient->deleteUser(userId);

        if deleteResponse is error {
            return http:INTERNAL_SERVER_ERROR;
        }

        return http:STATUS_NO_CONTENT;
    }

    resource function get searchUserProfile(http:Request request) returns json|error {
        if !hasValidScope(request, "internal_user_mgt_view") {
            return http:FORBIDDEN;
        }

        json payload = check request.getJsonPayload();
        string emailAddress = payload.emailAddress.toString();
        error|scim:UserResource searchResponse = findUserByEmail(emailAddress);

        if searchResponse is error {
            return http:NOT_FOUND;
        }

        return {
            firstName: searchResponse.name?.givenName,
            lastName: searchResponse.name?.familyName,
            userName: searchResponse.userName
        };
    }
}

// Utility functions

function hasValidScope(http:Request request, string requiredScope) returns boolean {
    string[]|error scopes = request.getHeader("x-scopes");
    if scopes is string[] {
        foreach string scope in scopes {
            if (scope == requiredScope) {
                return true;
            }
        }
    }
    return false;
}

function findUserGroup(string emailAddress) returns string|error {
    // Implement logic to find the user group by email address
    // This is a placeholder implementation
    return "exampleGroupId";
}

function findUserByEmail(string emailAddress) returns scim:UserResource|error {
    // Implement logic to find user by email address
    // This is a placeholder implementation
    return error("User not found");
}

function deleteUser(string userId) returns error? {
    // Implement logic to delete user by userId
    // This is a placeholder implementation
    return;
}
