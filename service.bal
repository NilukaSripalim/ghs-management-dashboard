
import ballerina/http;
import ballerina/regex;
import ballerinax/scim;

configurable string asgardeoOrg = ?;
configurable string clientId = ?;
configurable string clientSecret = ?;

configurable string[] scope = [
    "internal_user_mgt_view",
    "internal_user_mgt_list",
    "internal_user_mgt_create",
    "internal_user_mgt_delete",
    "internal_user_mgt_update",
    "internal_user_mgt_delete",
    "internal_group_mgt_view",
    "internal_group_mgt_list",
    "internal_group_mgt_create",
    "internal_group_mgt_delete",
    "internal_group_mgt_update",
    "internal_group_mgt_delete"
];

scim:ConnectorConfig scimConfig = {
    orgName: asgardeoOrg,
    clientId: clientId,
    clientSecret: clientSecret,
    scope: scope
};

scim:Client scimClient = check new (scimConfig);

type createUserRequest record {
    string email;
    string name;
    string password;
};

service / on new http:Listener(9090) {

    resource function post createUserAccount(@http:Payload createUserRequest payload) returns http:Created|error|http:BadRequest {
        
        // Use email as the userName
        string userName = string `DEFAULT/${payload.email}`;
        
        // Map to the SCIM UserCreate structure
        scim:UserCreate user = {
            password: payload.password,
            userName: userName,
            emails: [{value: payload.email, type: "work", primary: true}],
            name: {formatted: payload.name}
        };
        
        scim:UserResource|scim:ErrorResponse|error createdUser = check scimClient->createUser(user);

        if createdUser is error {
            return error("Error occurred while creating user");
        }

        if !(createdUser.id is string) {
            return error("Error occurred while creating user");
        }

        string createdUserId = <string>createdUser.id;

        // Find user group by email and patch group
        string|error userGroupId = findUserGroup(payload.email);
        if userGroupId is error {
            return http:BAD_REQUEST;
        }

        scim:GroupPatch group = {Operations: [{op: "add", value: {members: [{"value": createdUserId, "display": user.userName}]}}]};
        scim:GroupResponse|scim:ErrorResponse|error groupResponse = check scimClient->patchGroup(userGroupId, group);

        if groupResponse is error|scim:ErrorResponse {
            error? userDeleteError = deleteUser(createdUserId);
            if userDeleteError is error {
                return error("Error occurred while adding user to group. User could not be deleted");
            }

            return error("Error occurred while creating user");
        }

        return http:CREATED;
    }

    // Other resources...
}
