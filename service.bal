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
        // Check for valid scope in request headers
        if !hasValidScope(request, "internal_group_mgt_view") {
            return error("Unauthorized: Insufficient scope");
        }

        int studentCount = 0;
        int commerceCount = 0;
        int artCount = 0;
        int scienceCount = 0;

        // Get the group resources of each required group using the getGroup method. 
        scim:GroupResource studentGroup = check scimClient->getGroup("studentGroupId");
        scim:GroupResource commerceGroup = check scimClient->getGroup("commerceGroupId");
        scim:GroupResource artGroup = check scimClient->getGroup("artsGroupId");
        scim:GroupResource scienceGroup = check scimClient->getGroup("scienceGroupId");

        // Find the member count in each group.
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

        // Create searchResponse
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
        // Check for valid scope in request headers
        if !hasValidScope(request, "internal_user_mgt_create") {
            return http:FORBIDDEN;
        }

        json payload = check request.getJsonPayload();
        string email = payload.email.toString();
        string password = payload.password.toString();
        string givenName = payload.name?.givenName.toString();
        string familyName = payload.name?.familyName.toString();

        string|error userGroupId = findUserGroup(email);

        if userGroupId is error {
            return http:BAD_REQUEST;
        }

        scim:UserCreate user = {
            password: password,
            userName: string `DEFAULT/${email}`,
            name: {
                givenName: givenName,
                familyName: familyName
            },
            email: email
        };

        scim:UserResource|scim:ErrorResponse|error createdUser = check scimClient->createUser(user);

        if createdUser is error || !(createdUser.id is string) {
            return error("Error occurred while creating user");
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
                return error("Error occurred while adding user to group. User could not be deleted");
            }

            return error("Error occurred while creating user");
        }

        return http:CREATED;
    }

    resource function delete deleteUser(http:Request request) returns http:STATUS_NO_CONTENT|error {
        // Check for valid scope in request headers
        if !hasValidScope(request, "internal_user_mgt_delete") {
            return http:FORBIDDEN;
        }

        json payload = check request.getJsonPayload();
        string email = payload.email.toString();
        error|scim:UserResource searchResponse = findUserByEmail(email);

        if searchResponse is error {
            return error("Error occurred while searching the user");
        }

        string userId = <string>searchResponse.id;

        if userId == "" {
            return error("Error occurred while searching the user");
        }

        scim:ErrorResponse|error? deleteResponse = check scimClient->deleteUser(userId);

        if deleteResponse is error {
            return error("Error occurred while deleting the user");
        }

        return http:STATUS_NO_CONTENT;
    }

    resource function get searchUserProfile(http:Request request) returns json|error {
        // Check for valid scope in request headers
        if !hasValidScope(request, "internal_user_mgt_view") {
            return http:FORBIDDEN;
        }

        json payload = check request.getJsonPayload();
        string email = payload.email.toString();
        error|scim:UserResource searchResponse = findUserByEmail(email);

        if searchResponse is error {
            return error("Error in searching user profile");
        }

        return {
            firstName: searchResponse.name?.givenName,
            lastName: searchResponse.name?.familyName,
            userName: searchResponse.userName
        };
    }
}
